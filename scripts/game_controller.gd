extends Node3D

@export var grid_size: Vector2i = Vector2i(4, 4)
@export var generation_seed: int = 0 

@export var spawnable_items: Array[PackedScene] = []

var _egg_scene: PackedScene = preload("res://scenes/egg.tscn")
var _pause_menu_scene: PackedScene = preload("res://scenes/pause_menu.tscn")
var _pause_menu: CanvasLayer = null
var _game_hud_scene: PackedScene = preload("res://scenes/game_hud.tscn")
var _game_hud: CanvasLayer = null

@onready var multiplayer_manager: Node = get_node("/root/MultiplayerManager")
@onready var spawn_manager: Node = get_node("/root/SpawnManager")
@onready var chunks: Node3D = $Chunks
@onready var players_container: Node3D = $Players

var _is_singleplayer: bool = true
var _map_generator: ProceduralMapGenerator = null
var _game_over_scene: PackedScene = preload("res://scenes/game_over.tscn")
var _game_over_instance: Node3D = null
var _is_spectating: bool = false
var _chunk_cameras: Array[Camera3D] = []
var _spectate_camera_index: int = 0
var _loading_screen: CanvasLayer = null

var _total_good_eggs: int = 0
var _eggs_delivered: int = 0
var _players_in_car: Dictionary = {}  # peer_id -> bool
var _car_area: Area3D = null

func _ready() -> void:
	multiplayer_manager.server_disconnected.connect(_on_server_disconnected)

	_show_loading_screen()

	_pause_menu = _pause_menu_scene.instantiate()
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_menu.visible = false
	_pause_menu.disconnect_requested.connect(_on_pause_menu_disconnect)
	add_child(_pause_menu)

	_game_hud = _game_hud_scene.instantiate()
	add_child(_game_hud)

	_is_singleplayer = multiplayer_manager.current_mode == multiplayer_manager.NetworkMode.NONE

	call_deferred("_initialize_game_async")


func _show_loading_screen() -> void:
	_loading_screen = CanvasLayer.new()
	_loading_screen.layer = 100 

	var background := ColorRect.new()
	background.color = Color(0, 0, 0, 1)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_screen.add_child(background)

	var label := Label.new()
	label.text = "Loading..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 48)
	_loading_screen.add_child(label)

	add_child(_loading_screen)


func _hide_loading_screen() -> void:
	if _loading_screen:
		_loading_screen.queue_free()
		_loading_screen = null


func _initialize_game_async() -> void:
	await get_tree().process_frame

	_map_generator = ProceduralMapGenerator.new()
	_generate_procedural_map()

	await get_tree().process_frame

	_start_game()
	_connect_bunny_signals()

	await get_tree().process_frame

	_hide_loading_screen()


func _generate_procedural_map() -> void:
	"""Generates the procedural map using cemetery definition"""
	var cemetery_map := load("res://resources/maps/cemetery_map.tres") as MapTypeDefinition
	if not cemetery_map:
		push_error("[GameController] Failed to load cemetery_map.tres")
		return

	var seed_value := generation_seed
	if seed_value == 0:
		seed_value = randi()

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_map_seed.rpc(seed_value)

	var generated_chunks := _map_generator.generate_map(cemetery_map, grid_size, seed_value)

	for chunk in generated_chunks:
		chunks.add_child(chunk)



@rpc("authority", "call_local", "reliable")
func _sync_map_seed(seed_value: int) -> void:
	"""Receives seed from host for deterministic map generation"""
	generation_seed = seed_value


func _start_game() -> void:
	if _is_singleplayer:
		_spawn_singleplayer()
	else:
		_spawn_multiplayer()

	_total_good_eggs = spawn_eggs()

	spawn_items()

	_setup_car()
	_game_hud.setup_egg_counter(_total_good_eggs)


func _spawn_singleplayer() -> void:
	spawn_manager.reset()

	var player: Node3D = spawn_manager.spawn_singleplayer()
	if not player:
		push_error("[GameController] Failed to spawn singleplayer!")
		return

	if not player.player_died.is_connected(_on_player_died):
		player.player_died.connect(_on_player_died.bind(player))

	_activate_start_chunk_camera()


func _spawn_multiplayer() -> void:
	spawn_manager.reset()

	spawn_manager.spawn_all_players()

	for peer_id in multiplayer_manager.players:
		var player = multiplayer_manager.players[peer_id] as Node3D
		if is_instance_valid(player) and player.has_signal("player_died") and not player.player_died.is_connected(_on_player_died):
			player.player_died.connect(_on_player_died.bind(player))

	_activate_start_chunk_camera()


func _activate_start_chunk_camera() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame

	var camera_manager := get_node_or_null("/root/CameraManager")
	if not camera_manager:
		return

	for chunk in chunks.get_children():
		if "start" in chunk.name.to_lower():
			var camera := chunk.get_node_or_null("Camera3D") as Camera3D
			if camera:
				camera_manager.set_active_camera(camera)
			break


func _on_server_disconnected() -> void:
	_cleanup_spectator()
	_cleanup_all_players()
	_cleanup_game_objects()
	call_deferred("_safe_return_to_lobby")


func _on_pause_menu_disconnect() -> void:
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
	var selected_spawn_points: Array[Node3D] = []

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	rng.seed = rng.randi()
	for chunk in chunks.get_children():
		var egg_spawns = chunk.get_node_or_null("EggSpawnPoints")
		if egg_spawns and egg_spawns.get_child_count() > 0:
			var chunk_spawn_points: Array[Node3D] = []
			for spawn_point in egg_spawns.get_children():
				chunk_spawn_points.append(spawn_point)

			var random_index: int = rng.randi_range(0, chunk_spawn_points.size() - 1)
			var selected_point: Node3D = chunk_spawn_points[random_index]
			selected_spawn_points.append(selected_point)

	var egg_count: int = selected_spawn_points.size()

	if egg_count == 0:
		return 0

	rng.randomize()
	rng.seed = rng.randi()

	for i in range(egg_count - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var temp = selected_spawn_points[i]
		selected_spawn_points[i] = selected_spawn_points[j]
		selected_spawn_points[j] = temp

	var monster_count: int = ceili(egg_count / 2.0)
	var monster_indices: Array[int] = []

	while monster_indices.size() < monster_count:
		var random_index: int = rng.randi_range(0, egg_count - 1)
		if not random_index in monster_indices:
			monster_indices.append(random_index)

	var good_egg_count: int = 0

	for i in range(egg_count):
		var spawn_point: Node3D = selected_spawn_points[i]
		if not is_instance_valid(spawn_point) or not spawn_point.is_inside_tree():
			continue

		var egg: Node3D = _egg_scene.instantiate()
		var is_monster: bool = i in monster_indices

		if is_monster:
			egg.is_monster = true
		else:
			good_egg_count += 1

		egg.name = "Egg_" + str(i)
		egg.add_to_group("eggs")
		var target_chunk: Node3D = spawn_point.get_parent().get_parent()
		target_chunk.add_child(egg)
		egg.global_position = spawn_point.global_position

	return good_egg_count


func _fisher_yates_shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	"""Shuffles array in-place using Fisher-Yates algorithm"""
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var temp = arr[i]
		arr[i] = arr[j]
		arr[j] = temp


func spawn_items() -> void:
	"""Spawns interactable items (notes/papers) across chunks"""
	print("[GameController] spawn_items() - spawnable_items: %d" % spawnable_items.size())

	if spawnable_items.is_empty():
		print("[GameController] ERRO: spawnable_items está vazio! Configure no inspector.")
		return

	var all_spawn_points: Array[Node3D] = []
	var chunk_for_spawn_point: Dictionary = {}  

	for chunk in chunks.get_children():
		var item_spawns = chunk.get_node_or_null("IntectableItemSpawnPoints")
		if item_spawns:
			print("[GameController] Chunk '%s' tem IntectableItemSpawnPoints com %d filhos" % [chunk.name, item_spawns.get_child_count()])
			if item_spawns.get_child_count() > 0:
				for spawn_point in item_spawns.get_children():
					all_spawn_points.append(spawn_point)
					chunk_for_spawn_point[spawn_point] = chunk

	print("[GameController] spawn_points encontrados: %d" % all_spawn_points.size())

	if all_spawn_points.is_empty():
		print("[GameController] ERRO: Nenhum IntectableItemSpawnPoints encontrado nos chunks!")
		return

	var total_items: int = spawnable_items.size()
	var min_spawns: int = ceili(all_spawn_points.size() / 3.0) 
	var max_spawns: int = ceili(all_spawn_points.size() / 2.0)

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var items_to_spawn: int = rng.randi_range(min_spawns, max_spawns)

	var shuffled_spawn_points: Array = []
	for sp in all_spawn_points:
		shuffled_spawn_points.append(sp)
	_fisher_yates_shuffle(shuffled_spawn_points, rng)

	const MAX_ITEMS_PER_CHUNK: int = 1
	var chunk_item_count: Dictionary = {} 
	var spawned_count: int = 0

	for i in range(items_to_spawn):
		var item_index: int = i % total_items
		var item_scene: PackedScene = spawnable_items[item_index]

		var selected_spawn_point: Node3D = null
		for spawn_point in shuffled_spawn_points:
			var chunk = chunk_for_spawn_point.get(spawn_point)
			var current_count: int = chunk_item_count.get(chunk, 0)
			if chunk and current_count < MAX_ITEMS_PER_CHUNK:
				selected_spawn_point = spawn_point
				chunk_item_count[chunk] = current_count + 1
				shuffled_spawn_points.erase(spawn_point)
				break

		if not selected_spawn_point:
			break

		var item: Node3D = item_scene.instantiate()
		item.name = "SpawnedItem_" + str(i)
		item.add_to_group("spawned_items")
		var target_chunk: Node3D = chunk_for_spawn_point[selected_spawn_point]
		target_chunk.add_child(item)
		item.global_position = selected_spawn_point.global_position

		spawned_count += 1

	print("[GameController] Items spawned: %d/%d spawn points (unique items: %d)" % [spawned_count, all_spawn_points.size(), total_items])


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

	spawn_manager.clear_all_players()


func _cleanup_game_objects() -> void:
	if not is_inside_tree():
		return

	for egg in get_tree().get_nodes_in_group("eggs"):
		if is_instance_valid(egg):
			egg.queue_free()

	for item in get_tree().get_nodes_in_group("spawned_items"):
		if is_instance_valid(item):
			item.queue_free()

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

	if not _is_singleplayer and multiplayer.is_server():
		var host_manager := get_node_or_null("/root/HostManager")
		if host_manager:
			host_manager.sync_return_to_lobby()
			return

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
		return false 

	player._clear_carried_egg()
	egg.queue_free()

	_eggs_delivered += 1
	_update_hud_eggs()

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

	var player := _get_player_by_peer_id(peer_id)
	if player:
		player.visible = false
		player.set_physics_process(false)
		player.set_process_input(false)

	if not _is_singleplayer:
		_sync_player_entered_car(peer_id)

	_check_mission_complete()


func _check_mission_complete() -> void:
	var alive_players := _get_alive_players()
	for p in alive_players:
		var pid: int = p.get_meta("peer_id", 1)
		if not _players_in_car.get(pid, false):
			return
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
