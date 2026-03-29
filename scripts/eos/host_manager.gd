extends Node
const SYNC_INTERVAL: float = 0.05

var _sync_timer: float = 0.0


func _ready() -> void:
	pass


func _exit_tree() -> void:
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return

	if not _is_multiplayer_active():
		return

	# Só o host sincroniza
	if not multiplayer.is_server():
		return

	_sync_timer += delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer = 0.0
		_sync_bunny()


func _is_multiplayer_active() -> bool:
	if not is_inside_tree():
		return false
	if not multiplayer.has_multiplayer_peer():
		return false
	if not is_instance_valid(multiplayer.multiplayer_peer):
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


# ==========================================
# BUNNY SYNC
# ==========================================
func _sync_bunny() -> void:
	# Only sync in game scene (not lobby)
	var current_scene := get_tree().current_scene
	if not current_scene or "lobby" in current_scene.name.to_lower():
		return

	var bunny := get_tree().get_first_node_in_group("assassin_bunny")
	if not bunny or not bunny.is_inside_tree():
		return

	var state: int = bunny.get_state() if bunny.has_method("get_state") else 0
	var approach_count: int = bunny.get_approach_count() if bunny.has_method("get_approach_count") else 0

	_sync_bunny_state.rpc(
		bunny.global_position,
		bunny.rotation.y,
		bunny.visible,
		state,
		approach_count
	)


@rpc("authority", "call_remote", "unreliable")
func _sync_bunny_state(pos: Vector3, rot_y: float, is_visible: bool, state: int, approach_count: int) -> void:
	# Only process in game scene
	var current_scene := get_tree().current_scene
	if not current_scene or "lobby" in current_scene.name.to_lower():
		return

	var bunny := get_tree().get_first_node_in_group("assassin_bunny")
	if not bunny or not bunny.is_inside_tree():
		return

	bunny.global_position = pos
	bunny.rotation.y = rot_y
	bunny.visible = is_visible

	if bunny.has_method("set_synced_state"):
		bunny.set_synced_state(state, approach_count)


func activate_bunny() -> void:
	if not _is_multiplayer_active():
		return

	if not multiplayer.is_server():
		return

	_activate_bunny_rpc.rpc()


@rpc("authority", "call_local", "reliable")
func _activate_bunny_rpc() -> void:
	var bunny := get_tree().get_first_node_in_group("assassin_bunny")
	if bunny and bunny.has_method("activate"):
		bunny.activate()


func bunny_kill_player(player_id: int) -> void:
	if not _is_multiplayer_active():
		return

	if not multiplayer.is_server():
		return

	_bunny_kill_player_rpc.rpc(player_id)


@rpc("authority", "call_remote", "reliable")
func _bunny_kill_player_rpc(player_id: int) -> void:
	var current_scene := get_tree().current_scene
	if not current_scene or "lobby" in current_scene.name.to_lower():
		return

	# Validar que player existe antes de processar
	if not MultiplayerManager.players.has(player_id):
		return

	var player: Node3D = MultiplayerManager.players[player_id]
	if not is_instance_valid(player):
		return

	if player.has_method("die"):
		player.die()


# ==========================================
# EGG SYNC
# ==========================================
func pickup_egg(egg_name: String, player_id: int) -> void:
	if not _is_multiplayer_active():
		return

	_pickup_egg_rpc.rpc(egg_name, player_id)


@rpc("any_peer", "call_local", "reliable")
func _pickup_egg_rpc(egg_name: String, player_id: int) -> void:
	# Validar player existe
	if not MultiplayerManager.players.has(player_id):
		return

	var player: Node3D = MultiplayerManager.players[player_id]
	if not is_instance_valid(player):
		return

	# Se este cliente tem authority sobre o player, ele já processou localmente
	if player.is_multiplayer_authority():
		return

	# Buscar o ovo pelo nome
	var egg: Node3D = null
	for e in get_tree().get_nodes_in_group("eggs"):
		if e.name == egg_name:
			egg = e
			break

	if not egg:
		return

	# Processar pickup no cliente remoto
	if egg.has_method("on_picked_up"):
		egg.on_picked_up()

	var egg_parent := egg.get_parent()
	if egg_parent:
		egg_parent.remove_child(egg)
	player.add_child(egg)

	# Posicionar o ovo corretamente (mesmo código de _update_carried_egg)
	egg.position = Vector3(0, 0.8, -0.5)
	egg.rotation = Vector3.ZERO
	egg.scale = Vector3(1, 1, 1)

	# Atualizar _carried_egg no player remoto
	if "_carried_egg" in player:
		player._carried_egg = egg


func drop_egg(egg_name: String, player_id: int, drop_position: Vector3) -> void:
	if not _is_multiplayer_active():
		return

	_drop_egg_rpc.rpc(egg_name, player_id, drop_position)


@rpc("any_peer", "call_local", "reliable")
func _drop_egg_rpc(_egg_name: String, player_id: int, drop_position: Vector3) -> void:
	# Validar player existe
	if not MultiplayerManager.players.has(player_id):
		return

	var player: Node3D = MultiplayerManager.players[player_id]
	if not is_instance_valid(player):
		return

	# Se este cliente tem authority sobre o player, ele já processou localmente
	if player.is_multiplayer_authority():
		return

	# Buscar o ovo nos filhos do player
	var egg: Node3D = null
	for child in player.get_children():
		if child.is_in_group("eggs"):
			egg = child
			break

	if not egg:
		return

	# Processar drop no cliente remoto
	player.remove_child(egg)
	get_tree().current_scene.add_child(egg)
	egg.global_position = drop_position

	# Atualizar _carried_egg no player remoto
	if "_carried_egg" in player:
		player._carried_egg = null


func release_monster(egg_position: Vector3) -> void:
	if not _is_multiplayer_active():
		return

	if not multiplayer.is_server():
		return

	_release_monster_rpc.rpc(egg_position)


@rpc("authority", "call_local", "reliable")
func _release_monster_rpc(egg_position: Vector3) -> void:
	var camera_manager := get_node_or_null("/root/CameraManager")
	if camera_manager:
		camera_manager.shake_camera(0.5, 1.0)

	# Always spawn a new bunny for each monster egg
	_spawn_bunny_at_position(egg_position)


func _spawn_bunny_at_position(pos: Vector3) -> void:
	var current_scene := get_tree().current_scene
	if not current_scene or not current_scene.is_inside_tree():
		return

	var bunny_scene := preload("res://scenes/monsters/assassin_bunny.tscn")
	var bunny := bunny_scene.instantiate()
	current_scene.add_child(bunny)
	bunny.global_position = pos
	bunny.add_to_group("assassin_bunny")

	# Connect to game controller
	var scene_controller := get_tree().current_scene
	if scene_controller and scene_controller.has_method("_on_all_players_dead"):
		if bunny.has_signal("all_players_dead") and not bunny.all_players_dead.is_connected(scene_controller._on_all_players_dead):
			bunny.all_players_dead.connect(scene_controller._on_all_players_dead)

	bunny.activate()


func spawn_egg(pos: Vector3, is_monster: bool = false) -> void:
	if not _is_multiplayer_active():
		return

	if not multiplayer.is_server():
		return

	var egg_id := randi()
	_spawn_egg_rpc.rpc(egg_id, pos, is_monster)


@rpc("authority", "call_local", "reliable")
func _spawn_egg_rpc(egg_id: int, pos: Vector3, is_monster: bool) -> void:
	var egg_scene := preload("res://scenes/eggs/egg.tscn")
	var egg := egg_scene.instantiate()
	egg.name = str(egg_id)
	egg.is_monster = is_monster
	egg.global_position = pos
	egg.add_to_group("eggs")
	get_tree().current_scene.add_child(egg)


# ==========================================
# DELIVERY & CAR SYNC
# ==========================================

func sync_egg_delivered(delivered: int, total: int) -> void:
	if not _is_multiplayer_active():
		return
	_sync_egg_delivered_rpc.rpc(delivered, total)


@rpc("any_peer", "call_remote", "reliable")
func _sync_egg_delivered_rpc(delivered: int, total: int) -> void:
	var game_ctrl := get_tree().current_scene
	if game_ctrl and game_ctrl.has_method("_on_remote_egg_delivered"):
		game_ctrl._on_remote_egg_delivered(delivered, total)


func sync_player_entered_car(peer_id: int) -> void:
	if not _is_multiplayer_active():
		return
	_sync_player_entered_car_rpc.rpc(peer_id)


@rpc("any_peer", "call_remote", "reliable")
func _sync_player_entered_car_rpc(peer_id: int) -> void:
	var game_ctrl := get_tree().current_scene
	if game_ctrl and game_ctrl.has_method("_on_remote_player_entered_car"):
		game_ctrl._on_remote_player_entered_car(peer_id)


func sync_mission_complete() -> void:
	if not _is_multiplayer_active():
		return
	if not multiplayer.is_server():
		return
	_sync_mission_complete_rpc.rpc()


@rpc("authority", "call_local", "reliable")
func _sync_mission_complete_rpc() -> void:
	var game_ctrl := get_tree().current_scene
	if game_ctrl and game_ctrl.has_method("_on_remote_mission_complete"):
		game_ctrl._on_remote_mission_complete()


# ==========================================
# LOBBY RETURN SYNC
# ==========================================

func sync_return_to_lobby() -> void:
	if not _is_multiplayer_active():
		return
	if not multiplayer.is_server():
		return
	_sync_return_to_lobby_rpc.rpc()


@rpc("authority", "call_local", "reliable")
func _sync_return_to_lobby_rpc() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/lobby_3d.tscn")
