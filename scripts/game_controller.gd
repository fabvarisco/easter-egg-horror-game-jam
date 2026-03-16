extends Node3D
## Game Controller - Manages gameplay (eggs, bunny, game over)

@export var list_of_points_for_eggs: Array[Vector3] = []

var _player_scene: PackedScene = preload("res://scenes/player.tscn")
var _egg_scene: PackedScene = preload("res://scenes/egg.tscn")
var _pause_menu_scene: PackedScene = preload("res://scenes/pause_menu.tscn")
var _pause_menu: CanvasLayer = null
var _game_hud_scene: PackedScene = preload("res://scenes/game_hud.tscn")
var _game_hud: CanvasLayer = null

@onready var multiplayer_manager: Node = get_node("/root/MultiplayerManager")
@onready var chunks: Node3D = $Chunks
@onready var players_container: Node3D = $Players

var _is_singleplayer: bool = true
var _game_over_scene: PackedScene = preload("res://scenes/game_over.tscn")
var _game_over_instance: Node3D = null
var _is_spectating: bool = false
var _chunk_cameras: Array[Camera3D] = []
var _spectate_camera_index: int = 0

# Egg delivery system
var _total_good_eggs: int = 0
var _eggs_delivered: int = 0
var _players_in_car: Dictionary = {}  # peer_id -> bool
var _car_area: Area3D = null


func _ready() -> void:
	multiplayer_manager.server_disconnected.connect(_on_server_disconnected)

	# Setup pause menu
	_pause_menu = _pause_menu_scene.instantiate()
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_menu.visible = false
	_pause_menu.disconnect_requested.connect(_on_pause_menu_disconnect)
	add_child(_pause_menu)

	# Setup game HUD
	_game_hud = _game_hud_scene.instantiate()
	add_child(_game_hud)

	# Determine if singleplayer based on network mode
	_is_singleplayer = multiplayer_manager.current_mode == multiplayer_manager.NetworkMode.NONE

	# Spawn players and start game (deferred to ensure chunks are ready)
	call_deferred("_start_game")
	call_deferred("_connect_bunny_signals")


func _start_game() -> void:
	if _is_singleplayer:
		_spawn_singleplayer()
	else:
		_spawn_multiplayer()

	# Spawn eggs after players and get good egg count
	_total_good_eggs = spawn_eggs()

	# Setup car delivery
	_setup_car()
	_game_hud.setup_egg_counter(_total_good_eggs)


func _get_player_spawn_points() -> Array[Node3D]:
	var spawn_points: Array[Node3D] = []

	for chunk in chunks.get_children():
		if "start" in chunk.name.to_lower():
			var player_spawns = chunk.get_node_or_null("PlayerSpawnPoints")
			if player_spawns and player_spawns.get_child_count() > 0:
				for spawn_point in player_spawns.get_children():
					spawn_points.append(spawn_point)
				break

	return spawn_points


func _spawn_singleplayer() -> void:
	# Clear old player references from lobby (they were freed when scene changed)
	multiplayer_manager.players.clear()

	var spawn_points := _get_player_spawn_points()
	if spawn_points.is_empty():
		push_error("No player spawn points found in start chunk!")
		return

	var spawn_point: Node3D = spawn_points[0]
	var player := _player_scene.instantiate()
	player.name = "1"
	player.set_meta("peer_id", 1)
	player.add_to_group("players")
	player.add_to_group("player")
	players_container.add_child(player)
	player.global_position = spawn_point.global_position

	player.visible = true
	player.set_physics_process(true)
	player.set_process_input(true)

	if not player.player_died.is_connected(_on_player_died):
		player.player_died.connect(_on_player_died.bind(player))

	multiplayer_manager.players[1] = player

	# Ativar câmera do chunk inicial diretamente (evita race condition)
	_activate_start_chunk_camera()


func _spawn_multiplayer() -> void:
	# Clear old player references from lobby (they were freed when scene changed)
	multiplayer_manager.players.clear()

	multiplayer_manager.spawn_all_players()

	# Connect death signals for all players
	for peer_id in multiplayer_manager.players:
		var player = multiplayer_manager.players[peer_id] as Node3D
		if is_instance_valid(player) and player.has_signal("player_died") and not player.player_died.is_connected(_on_player_died):
			player.player_died.connect(_on_player_died.bind(player))

	# Ativar câmera do chunk inicial diretamente (evita race condition)
	_activate_start_chunk_camera()


func _activate_start_chunk_camera() -> void:
	# Aguardar frames para garantir que tudo está inicializado
	await get_tree().physics_frame
	await get_tree().physics_frame

	var camera_manager := get_node_or_null("/root/CameraManager")
	if not camera_manager:
		print("[GameController] CameraManager not found!")
		return

	for chunk in chunks.get_children():
		if "start" in chunk.name.to_lower():
			var camera := chunk.get_node_or_null("Camera3D") as Camera3D
			if camera:
				print("[GameController] Activating start chunk camera: ", chunk.name)
				camera_manager.set_active_camera(camera)
			else:
				print("[GameController] No Camera3D found in chunk: ", chunk.name)
			break


func _on_server_disconnected() -> void:
	_cleanup_spectator()
	_cleanup_all_players()
	_cleanup_game_objects()
	call_deferred("_safe_return_to_lobby")


func _on_pause_menu_disconnect() -> void:
	# Disconnect from multiplayer and return to lobby
	await multiplayer_manager.leave_game()
	_safe_return_to_lobby()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _pause_menu and not _pause_menu.visible:
			_pause_menu.show_menu()
		return

	if _is_spectating:
		if event.is_action_pressed("move_forward"):
			_switch_spectate_camera(-1)  # W = câmera anterior
		elif event.is_action_pressed("move_backward"):
			_switch_spectate_camera(1)   # S = próxima câmera


func _connect_bunny_signals() -> void:
	var bunny := get_tree().get_first_node_in_group("assassin_bunny")
	if bunny:
		if bunny.has_signal("all_players_dead") and not bunny.all_players_dead.is_connected(_on_all_players_dead):
			bunny.all_players_dead.connect(_on_all_players_dead)


func spawn_eggs() -> int:
	var all_spawn_points: Array[Node3D] = []

	for chunk in chunks.get_children():
		var egg_spawns = chunk.get_node_or_null("EggSpawnPoints")
		if egg_spawns and egg_spawns.get_child_count() > 0:
			for spawn_point in egg_spawns.get_children():
				all_spawn_points.append(spawn_point)

	var egg_count: int = all_spawn_points.size()
	if egg_count == 0:
		return 0

	# Shuffle spawn points and pick first half as monster positions
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345 

	var shuffled_indices: Array[int] = []
	for i in range(egg_count):
		shuffled_indices.append(i)

	# Fisher-Yates shuffle com RNG determinístico
	for i in range(shuffled_indices.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp := shuffled_indices[i]
		shuffled_indices[i] = shuffled_indices[j]
		shuffled_indices[j] = temp

	var monster_count: int = egg_count / 2
	var monster_indices: Array[int] = []
	for i in range(monster_count):
		monster_indices.append(shuffled_indices[i])

	var good_egg_count: int = 0
	var actual_monster_count: int = 0

	for i in range(egg_count):
		var spawn_point: Node3D = all_spawn_points[i]
		if not is_instance_valid(spawn_point) or not spawn_point.is_inside_tree():
			continue

		var egg: Node3D = _egg_scene.instantiate()
		var is_monster: bool = i in monster_indices

		if is_monster:
			egg.is_monster = true
			actual_monster_count += 1
		else:
			good_egg_count += 1

		# Nome determinístico para sincronização multiplayer
		egg.name = "Egg_" + str(i)
		add_child(egg)
		egg.global_position = spawn_point.global_position

	print("Spawned eggs: ", good_egg_count, " good, ", actual_monster_count, " monsters")
	return good_egg_count


func _on_player_died(dead_player: Node3D) -> void:
	if not _is_singleplayer:
		var my_peer_id := multiplayer.get_unique_id()
		var dead_peer_id: int = dead_player.get_meta("peer_id", -1)
		if dead_peer_id != my_peer_id:
			return 

	_show_game_over()


func _show_game_over() -> void:
	if _game_over_instance:
		_game_over_instance.queue_free()

	_game_over_instance = _game_over_scene.instantiate()
	add_child(_game_over_instance)

	_game_over_instance.finished.connect(_on_game_over_finished)
	_game_over_instance.show_game_over()


func _on_game_over_finished() -> void:
	if _game_over_instance:
		_game_over_instance.queue_free()
		_game_over_instance = null

	if not _is_singleplayer:
		var alive_players = _get_alive_players()
		if alive_players.size() > 0:
			_start_spectator_mode()
			return

	_return_to_lobby()


func _start_spectator_mode() -> void:
	_is_spectating = true

	# Coletar todas as câmeras dos chunks
	_chunk_cameras.clear()
	for chunk in chunks.get_children():
		var camera := chunk.get_node_or_null("Camera3D") as Camera3D
		if camera:
			_chunk_cameras.append(camera)

	if _chunk_cameras.is_empty():
		_cleanup_spectator()
		_return_to_lobby()
		return

	_spectate_camera_index = 0
	_activate_spectate_camera()


func _switch_spectate_camera(direction: int) -> void:
	if _chunk_cameras.is_empty():
		return

	_spectate_camera_index = (_spectate_camera_index + direction) % _chunk_cameras.size()
	if _spectate_camera_index < 0:
		_spectate_camera_index = _chunk_cameras.size() - 1

	_activate_spectate_camera()


func _activate_spectate_camera() -> void:
	if _spectate_camera_index < 0 or _spectate_camera_index >= _chunk_cameras.size():
		return

	var camera := _chunk_cameras[_spectate_camera_index]
	var camera_manager := get_node_or_null("/root/CameraManager")
	if camera_manager:
		camera_manager.set_active_camera(camera)


func _get_alive_players() -> Array:
	var alive := []
	for p in get_tree().get_nodes_in_group("players"):
		if p.has_method("is_dead") and not p.is_dead():
			alive.append(p)
		elif not p.has_method("is_dead"):
			alive.append(p)
	return alive


func _process(_delta: float) -> void:
	if _is_spectating:
		var alive_players = _get_alive_players()
		if alive_players.size() == 0:
			_cleanup_spectator()
			_return_to_lobby()


func _on_all_players_dead() -> void:
	_show_game_over()


func _cleanup_spectator() -> void:
	_is_spectating = false
	_chunk_cameras.clear()
	_spectate_camera_index = 0


func _cleanup_all_players() -> void:
	if players_container:
		for child in players_container.get_children():
			if is_instance_valid(child):
				child.queue_free()

	multiplayer_manager.players.clear()


func _cleanup_game_objects() -> void:
	if not is_inside_tree():
		return

	for egg in get_tree().get_nodes_in_group("eggs"):
		if is_instance_valid(egg):
			egg.queue_free()

	for bunny in get_tree().get_nodes_in_group("assassin_bunny"):
		if is_instance_valid(bunny):
			bunny.queue_free()

	if _game_over_instance and is_instance_valid(_game_over_instance):
		_game_over_instance.queue_free()
		_game_over_instance = null


func _safe_return_to_lobby() -> void:
	if not is_inside_tree():
		return

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/lobby_3d.tscn")


func _return_to_lobby() -> void:
	_cleanup_spectator()

	if _game_over_instance and is_instance_valid(_game_over_instance):
		_game_over_instance.queue_free()
		_game_over_instance = null

	if not is_inside_tree():
		return

	for bunny in get_tree().get_nodes_in_group("assassin_bunny"):
		if is_instance_valid(bunny):
			bunny.queue_free()

	# Em multiplayer, o host sincroniza o retorno ao lobby para todos
	if not _is_singleplayer and multiplayer.is_server():
		var host_manager := get_node_or_null("/root/HostManager")
		if host_manager:
			host_manager.sync_return_to_lobby()
			return

	# Singleplayer ou cliente (fallback)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/lobby_3d.tscn")


# ==========================================
# EGG DELIVERY SYSTEM
# ==========================================

func _setup_car() -> void:
	for chunk in chunks.get_children():
		if "start" in chunk.name.to_lower():
			_car_area = chunk.get_node_or_null("Car")
			break


func deliver_egg(player: Node3D) -> bool:
	if not player.is_carrying_egg():
		return false

	var egg: Node3D = player.get_carried_egg()
	if egg.get("is_monster"):
		return false  # Cannot deliver monster egg

	# Remove egg from player and destroy
	player._clear_carried_egg()
	egg.queue_free()

	_eggs_delivered += 1
	_update_hud_eggs()

	# Sync multiplayer
	if not _is_singleplayer:
		_sync_egg_delivered()

	if _eggs_delivered >= _total_good_eggs:
		_on_all_eggs_delivered()

	return true


func can_enter_car() -> bool:
	return _eggs_delivered >= _total_good_eggs


func player_enter_car(peer_id: int) -> void:
	if not can_enter_car():
		return

	_players_in_car[peer_id] = true

	# Hide player
	var player := _get_player_by_peer_id(peer_id)
	if player:
		player.visible = false
		player.set_physics_process(false)
		player.set_process_input(false)

	# Sync multiplayer
	if not _is_singleplayer:
		_sync_player_entered_car(peer_id)

	_check_mission_complete()


func _check_mission_complete() -> void:
	var alive_players := _get_alive_players()
	for p in alive_players:
		var pid: int = p.get_meta("peer_id", 1)
		if not _players_in_car.get(pid, false):
			return
	# All players in car!
	_on_mission_complete()


func _on_all_eggs_delivered() -> void:
	_game_hud.show_car_ready()


func _on_mission_complete() -> void:
	_game_hud.show_mission_complete()
	await get_tree().create_timer(3.0).timeout
	_return_to_lobby()


func _update_hud_eggs() -> void:
	_game_hud.update_egg_counter(_eggs_delivered, _total_good_eggs)


func _get_player_by_peer_id(peer_id: int) -> Node3D:
	for p in get_tree().get_nodes_in_group("players"):
		if p.get_meta("peer_id", -1) == peer_id:
			return p
	return null


func _sync_egg_delivered() -> void:
	var host_manager := get_node_or_null("/root/HostManager")
	if host_manager:
		host_manager.sync_egg_delivered(_eggs_delivered, _total_good_eggs)


func _sync_player_entered_car(peer_id: int) -> void:
	var host_manager := get_node_or_null("/root/HostManager")
	if host_manager:
		host_manager.sync_player_entered_car(peer_id)


func _on_remote_egg_delivered(delivered: int, total: int) -> void:
	_eggs_delivered = delivered
	_total_good_eggs = total
	_update_hud_eggs()
	if _eggs_delivered >= _total_good_eggs:
		_on_all_eggs_delivered()


func _on_remote_player_entered_car(peer_id: int) -> void:
	_players_in_car[peer_id] = true

	var player := _get_player_by_peer_id(peer_id)
	if player:
		player.visible = false
		player.set_physics_process(false)
		player.set_process_input(false)

	_check_mission_complete()


func _on_remote_mission_complete() -> void:
	_game_hud.show_mission_complete()
	await get_tree().create_timer(3.0).timeout
	_return_to_lobby()
