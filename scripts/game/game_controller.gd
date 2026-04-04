extends Node3D

var grid_size: Vector2i = Vector2i(4, 4)
@export var generation_seed: int = 0

@export var spawnable_items: Array[PackedScene] = []

var _egg_scene: PackedScene = preload("res://scenes/eggs/egg.tscn")
var _assassin_bunny_egg_scene: PackedScene = preload("res://scenes/eggs/assassin_bunny_egg.tscn")
var _pause_menu_scene: PackedScene = preload("res://scenes/ui/pause_menu.tscn")
var _pause_menu: CanvasLayer = null
var _game_hud_scene: PackedScene = preload("res://scenes/ui/game_hud.tscn")
var _game_hud: CanvasLayer = null
var _fade_scene: PackedScene = preload("res://scenes/ui/fade_scene.tscn")
var _fade_instance: CanvasLayer = null
var _dialog_scene: PackedScene = preload("res://scenes/dialog.tscn")
var _dialog_instance: Node3D = null

@onready var multiplayer_manager: Node = get_node("/root/MultiplayerManager")
@onready var spawn_manager: Node = get_node("/root/SpawnManager")
@onready var chunks: Node3D = $Chunks
@onready var players_container: Node3D = $Players

var _is_singleplayer: bool = true
var _map_generator: ProceduralMapGenerator = null
var _game_over_scene: PackedScene = preload("res://scenes/ui/game_over.tscn")
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

	grid_size = ProgressionManager.get_current_grid_size()
	print("Starting game with grid size: %s (run %d)" % [grid_size, ProgressionManager.runs_completed])

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


func _show_intro_dialogue() -> void:
	# In multiplayer, only host shows the intro dialogue
	if not _is_singleplayer and not multiplayer.is_server():
		return

	_dialog_instance = _dialog_scene.instantiate()
	add_child(_dialog_instance)

	# TODO: Definir os textos especificos da intro
	var dialogues: Array[String] = [
		"Texto 1...",
		"Texto 2...",
		"Texto 3...",
	]

	_dialog_instance.start_dialogue(dialogues)
	await _dialog_instance.dialogue_finished
	_dialog_instance.queue_free()
	_dialog_instance = null


func _initialize_game_async() -> void:
	await get_tree().process_frame

	_map_generator = ProceduralMapGenerator.new()
	_generate_procedural_map()

	await get_tree().process_frame

	_start_game()
	_connect_bunny_signals()

	await get_tree().process_frame

	# Show intro dialogue before hiding loading screen
	await _show_intro_dialogue()

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
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_game_music()
		audio_manager.start_ambient_sounds()

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
	# In multiplayer, only server generates egg data and syncs to clients
	if not _is_singleplayer:
		if multiplayer.is_server():
			return _generate_and_sync_eggs()
		else:
			# Clients wait for server to sync eggs
			return 0

	# Singleplayer: generate locally
	return _generate_eggs_local()


func _generate_and_sync_eggs() -> int:
	"""Server generates eggs and syncs positions to all clients"""
	var egg_data: Array = []  # [{pos: Vector3, is_monster: bool, chunk_index: int}]
	var good_egg_count: int = 0

	var rng := RandomNumberGenerator.new()
	rng.seed = generation_seed + 1000

	var chunk_list := chunks.get_children()
	var selected_spawn_points: Array = []  # [{point: Node3D, chunk_idx: int}]

	for chunk_idx in range(chunk_list.size()):
		var chunk = chunk_list[chunk_idx]
		var egg_spawns = chunk.get_node_or_null("EggSpawnPoints")
		if egg_spawns and egg_spawns.get_child_count() > 0:
			var chunk_spawn_points: Array[Node3D] = []
			for spawn_point in egg_spawns.get_children():
				chunk_spawn_points.append(spawn_point)

			var random_index: int = rng.randi_range(0, chunk_spawn_points.size() - 1)
			var selected_point: Node3D = chunk_spawn_points[random_index]
			selected_spawn_points.append({
				"point": selected_point,
				"chunk_idx": chunk_idx
			})

	var egg_count: int = selected_spawn_points.size()
	if egg_count == 0:
		return 0

	# Shuffle spawn points
	for i in range(egg_count - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var temp = selected_spawn_points[i]
		selected_spawn_points[i] = selected_spawn_points[j]
		selected_spawn_points[j] = temp

	# Determine monster eggs
	var monster_count: int = ceili(egg_count / 2.0)
	var monster_indices: Array[int] = []
	while monster_indices.size() < monster_count:
		var random_index: int = rng.randi_range(0, egg_count - 1)
		if not random_index in monster_indices:
			monster_indices.append(random_index)

	# Build egg data and spawn locally
	for i in range(egg_count):
		var spawn_data = selected_spawn_points[i]
		var spawn_point: Node3D = spawn_data["point"]
		var chunk_idx: int = spawn_data["chunk_idx"]

		if not is_instance_valid(spawn_point) or not spawn_point.is_inside_tree():
			continue

		var is_monster: bool = i in monster_indices
		if not is_monster:
			good_egg_count += 1

		var pos: Vector3 = spawn_point.global_position
		egg_data.append({
			"pos": pos,
			"is_monster": is_monster,
			"chunk_idx": chunk_idx,
			"idx": i
		})

		# Spawn locally on server
		_spawn_single_egg(pos, is_monster, chunk_idx, i)

	# Sync to clients
	_sync_egg_spawns.rpc(_serialize_egg_data(egg_data), good_egg_count)

	return good_egg_count


func _serialize_egg_data(egg_data: Array) -> Array:
	"""Convert egg data to serializable format"""
	var result: Array = []
	for data in egg_data:
		result.append([
			data["pos"].x,
			data["pos"].y,
			data["pos"].z,
			data["is_monster"],
			data["chunk_idx"],
			data["idx"]
		])
	return result


@rpc("authority", "call_remote", "reliable")
func _sync_egg_spawns(serialized_data: Array, good_count: int) -> void:
	"""Clients receive egg spawn data from server"""
	for data in serialized_data:
		var pos := Vector3(data[0], data[1], data[2])
		var is_monster: bool = data[3]
		var chunk_idx: int = data[4]
		var idx: int = data[5]
		_spawn_single_egg(pos, is_monster, chunk_idx, idx)

	_total_good_eggs = good_count
	_game_hud.setup_egg_counter(_total_good_eggs)


func _spawn_single_egg(pos: Vector3, is_monster: bool, _chunk_idx: int, idx: int) -> void:
	"""Spawn a single egg at the given position"""
	var egg: Node3D

	if is_monster:
		egg = _assassin_bunny_egg_scene.instantiate()
	else:
		egg = _egg_scene.instantiate()

	egg.name = "Egg_" + str(idx)
	egg.add_to_group("eggs")
	# Add to chunks container directly to avoid chunk index mismatch issues
	chunks.add_child(egg)
	egg.global_position = pos


func _generate_eggs_local() -> int:
	"""Generate eggs locally (for singleplayer)"""
	var selected_spawn_points: Array[Node3D] = []

	var rng := RandomNumberGenerator.new()
	rng.seed = generation_seed + 1000

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

		var is_monster: bool = i in monster_indices
		var egg: Node3D

		if is_monster:
			egg = _assassin_bunny_egg_scene.instantiate()
		else:
			egg = _egg_scene.instantiate()
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
	if spawnable_items.is_empty():
		return

	# In multiplayer, only server spawns items and syncs to clients
	if not _is_singleplayer:
		if multiplayer.is_server():
			_generate_and_sync_items()
		# Clients wait for server to sync items
		return

	_generate_items_local()


func _generate_and_sync_items() -> void:
	"""Server generates items and syncs positions to all clients"""
	var all_spawn_points: Array[Node3D] = []
	var chunk_for_spawn_point: Dictionary = {}
	var chunk_list := chunks.get_children()

	for chunk_idx in range(chunk_list.size()):
		var chunk = chunk_list[chunk_idx]
		var item_spawns = chunk.get_node_or_null("IntectableItemSpawnPoints")
		if item_spawns and item_spawns.get_child_count() > 0:
			for spawn_point in item_spawns.get_children():
				all_spawn_points.append(spawn_point)
				chunk_for_spawn_point[spawn_point] = chunk_idx

	if all_spawn_points.is_empty():
		return

	var total_items: int = spawnable_items.size()
	var min_spawns: int = ceili(all_spawn_points.size() / 2.0)
	var max_spawns: int = all_spawn_points.size()

	var rng := RandomNumberGenerator.new()
	rng.seed = generation_seed + 2000

	var items_to_spawn: int = rng.randi_range(min_spawns, max_spawns)

	var shuffled_spawn_points: Array = []
	for sp in all_spawn_points:
		shuffled_spawn_points.append(sp)
	_fisher_yates_shuffle(shuffled_spawn_points, rng)

	const MAX_ITEMS_PER_CHUNK: int = 3
	var chunk_item_count: Dictionary = {}
	var item_data: Array = []  # [[pos_x, pos_y, pos_z, item_index, chunk_idx, spawn_idx]]

	for i in range(items_to_spawn):
		var item_index: int = i % total_items

		var selected_spawn_point: Node3D = null
		var selected_chunk_idx: int = -1
		for spawn_point in shuffled_spawn_points:
			var chunk_idx = chunk_for_spawn_point.get(spawn_point, -1)
			var current_count: int = chunk_item_count.get(chunk_idx, 0)
			if chunk_idx >= 0 and current_count < MAX_ITEMS_PER_CHUNK:
				selected_spawn_point = spawn_point
				selected_chunk_idx = chunk_idx
				chunk_item_count[chunk_idx] = current_count + 1
				shuffled_spawn_points.erase(spawn_point)
				break

		if not selected_spawn_point:
			break

		var pos: Vector3 = selected_spawn_point.global_position
		item_data.append([pos.x, pos.y, pos.z, item_index, selected_chunk_idx, i])

		# Spawn locally on server
		_spawn_single_item(pos, item_index, selected_chunk_idx, i)

	# Sync to clients
	_sync_item_spawns.rpc(item_data)


@rpc("authority", "call_remote", "reliable")
func _sync_item_spawns(item_data: Array) -> void:
	"""Clients receive item spawn data from server"""
	for data in item_data:
		var pos := Vector3(data[0], data[1], data[2])
		var item_index: int = data[3]
		var chunk_idx: int = data[4]
		var spawn_idx: int = data[5]
		_spawn_single_item(pos, item_index, chunk_idx, spawn_idx)


func _spawn_single_item(pos: Vector3, item_index: int, _chunk_idx: int, spawn_idx: int) -> void:
	"""Spawn a single item at the given position"""
	if item_index < 0 or item_index >= spawnable_items.size():
		return

	var item_scene: PackedScene = spawnable_items[item_index]
	var item: Node3D = item_scene.instantiate()

	item.name = "SpawnedItem_" + str(spawn_idx)
	item.add_to_group("spawned_items")
	# Add to chunks container directly to avoid chunk index mismatch issues
	chunks.add_child(item)
	item.global_position = pos


func _generate_items_local() -> void:
	"""Generate items locally (for singleplayer)"""
	var all_spawn_points: Array[Node3D] = []
	var chunk_for_spawn_point: Dictionary = {}

	for chunk in chunks.get_children():
		var item_spawns = chunk.get_node_or_null("IntectableItemSpawnPoints")
		if item_spawns and item_spawns.get_child_count() > 0:
			for spawn_point in item_spawns.get_children():
				all_spawn_points.append(spawn_point)
				chunk_for_spawn_point[spawn_point] = chunk

	if all_spawn_points.is_empty():
		return

	var total_items: int = spawnable_items.size()
	var min_spawns: int = ceili(all_spawn_points.size() / 2.0)
	var max_spawns: int = all_spawn_points.size()

	var rng := RandomNumberGenerator.new()
	rng.seed = generation_seed + 2000

	var items_to_spawn: int = rng.randi_range(min_spawns, max_spawns)

	var shuffled_spawn_points: Array = []
	for sp in all_spawn_points:
		shuffled_spawn_points.append(sp)
	_fisher_yates_shuffle(shuffled_spawn_points, rng)

	const MAX_ITEMS_PER_CHUNK: int = 3
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
	_game_over_instance.show_game_over()

	# Inicia o fade durante a tela de game over
	if _fade_instance:
		_fade_instance.queue_free()

	_fade_instance = _fade_scene.instantiate()
	add_child(_fade_instance)
	_fade_instance.fade_out_game_over(_on_fade_game_over_completed)


func _on_fade_game_over_completed() -> void:
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

	# Fade in para ver as câmeras
	if _fade_instance and is_instance_valid(_fade_instance):
		_fade_instance.fade_in()


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
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.stop_music()
		audio_manager.stop_ambient_sounds()

	if not is_inside_tree():
		return

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/lobby/lobby_3d.tscn")


func _return_to_lobby() -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.stop_music()
		audio_manager.stop_ambient_sounds()

	# Mark that we're returning from game (for singleplayer lobby detection)
	multiplayer_manager.set_returning_from_game(true)

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
	get_tree().change_scene_to_file("res://scenes/lobby/lobby_3d.tscn")


func _start_fade_and_return_to_lobby() -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.stop_music()
		audio_manager.stop_ambient_sounds()

	# Mark that we're returning from game (for singleplayer lobby detection)
	multiplayer_manager.set_returning_from_game(true)

	if _fade_instance:
		_fade_instance.queue_free()

	_fade_instance = _fade_scene.instantiate()
	add_child(_fade_instance)
	_fade_instance.fade_out_car_and_change_scene("res://scenes/lobby/lobby_3d.tscn")


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

	var egg_name := egg.name
	player._clear_carried_egg()
	egg.queue_free()

	_eggs_delivered += 1

	ProgressionManager.add_currency(5, "egg_delivered")

	_update_hud_eggs()

	if not _is_singleplayer:
		_sync_egg_delivered()
		_sync_player_egg_delivery(player, egg_name)

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

	ProgressionManager.complete_run()

	await get_tree().create_timer(2.0).timeout
	_start_fade_and_return_to_lobby()


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


func _sync_player_egg_delivery(player: Node3D, egg_name: String) -> void:
	var host_manager := get_node_or_null("/root/HostManager")
	if host_manager:
		var player_id: int = player.get_meta("peer_id", -1)
		if player_id != -1:
			host_manager.sync_player_delivered_egg(player_id, egg_name)


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
