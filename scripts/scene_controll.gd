extends Node3D

@export var list_of_points_for_eggs: Array[Vector3] = []

var _player_scene: PackedScene = preload("res://scenes/player.tscn")
var _egg_scene: PackedScene = preload("res://scenes/egg.tscn")
var player: CharacterBody3D = null

@onready var lobby: Control = $Lobby
@onready var multiplayer_manager: Node = get_node("/root/MultiplayerManager")
@onready var chunks: Node3D = $Chunks

var _is_singleplayer: bool = true
var _game_over_scene: PackedScene = preload("res://scenes/game_over.tscn")
var _game_over_instance: Node3D = null
var _is_spectating: bool = false
var _chunk_cameras: Array[Camera3D] = []
var _spectate_camera_index: int = 0


func _ready() -> void:
	lobby.game_started.connect(_on_game_started)
	multiplayer_manager.server_disconnected.connect(_on_server_disconnected)
	_connect_bunny_signals()


func _on_server_disconnected() -> void:
	# Limpar tudo de forma segura quando o host desconecta
	_cleanup_spectator()
	_cleanup_all_players()
	_cleanup_game_objects()
	# Usar call_deferred para evitar crash durante a desconexão
	call_deferred("_safe_return_to_menu")


func _input(event: InputEvent) -> void:
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


func _on_game_started(is_singleplayer: bool) -> void:
	_is_singleplayer = is_singleplayer
	_is_spectating = false

	if is_singleplayer:
		_start_singleplayer()
	else:
		_start_multiplayer()


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


func _start_singleplayer() -> void:
	var spawn_points := _get_player_spawn_points()
	if spawn_points.is_empty():
		push_error("No player spawn points found in start chunk!")
		return

	var spawn_point: Node3D = spawn_points[0]
	player = _player_scene.instantiate()
	player.global_position = spawn_point.global_position
	$Players.add_child(player)

	player.visible = true
	player.set_physics_process(true)
	player.set_process_input(true)
	player.add_to_group("player")
	if not player.player_died.is_connected(_on_player_died):
		player.player_died.connect(_on_player_died.bind(player))




func spawn_eggs() -> void:
	# Coletar todos os spawn points de todos os chunks
	var all_spawn_points: Array[Node3D] = []

	for chunk in chunks.get_children():
		var egg_spawns = chunk.get_node_or_null("EggSpawnPoints")
		if egg_spawns and egg_spawns.get_child_count() > 0:
			for spawn_point in egg_spawns.get_children():
				all_spawn_points.append(spawn_point)

	var egg_count: int = all_spawn_points.size()
	var monster_count: int = egg_count / 2
	print("Spawning ", egg_count, " eggs (", monster_count, " monsters)")

	# Usar seed fixa para garantir mesma ordem em todos os clientes
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	rng.seed = rng.randi()

	# Criar array de índices e embaralhar com RNG determinístico
	var indices: Array[int] = []
	for i in range(egg_count):
		indices.append(i)

	# Fisher-Yates shuffle determinístico
	for i in range(indices.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var temp := indices[i]
		indices[i] = indices[j]
		indices[j] = temp

	for i in range(egg_count):
		var spawn_point: Node3D = all_spawn_points[i]
		var egg: Node3D = _egg_scene.instantiate()
		egg.global_position = spawn_point.global_position

		# Nome determinístico para sincronização multiplayer
		egg.name = "Egg_" + str(i)

		# Metade dos ovos são monstros (os primeiros após embaralhar)
		if indices.find(i) < monster_count:
			egg.is_monster = true

		egg.add_to_group("eggs")
		add_child(egg)


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
		var alive_players := _get_alive_players()
		if alive_players.size() > 0:
			_start_spectator_mode()
			return

	_return_to_menu()


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
		_return_to_menu()
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
	camera.current = true


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
		var alive_players := _get_alive_players()
		if alive_players.size() == 0:
			_cleanup_spectator()
			_return_to_menu()


func _on_all_players_dead() -> void:
	_show_game_over()


func _cleanup_spectator() -> void:
	_is_spectating = false
	_chunk_cameras.clear()
	_spectate_camera_index = 0


func _cleanup_all_players() -> void:
	# Limpar todos os jogadores do container Players
	var players_node := get_node_or_null("Players")
	if players_node:
		for child in players_node.get_children():
			if is_instance_valid(child):
				child.queue_free()

	# Limpar referência local
	if player and is_instance_valid(player):
		player.queue_free()
	player = null


func _cleanup_game_objects() -> void:
	# Limpar ovos
	for egg in get_tree().get_nodes_in_group("eggs"):
		if is_instance_valid(egg):
			egg.queue_free()

	# Limpar bunnies
	for bunny in get_tree().get_nodes_in_group("assassin_bunny"):
		if is_instance_valid(bunny):
			bunny.queue_free()

	# Limpar game over se existir
	if _game_over_instance and is_instance_valid(_game_over_instance):
		_game_over_instance.queue_free()
		_game_over_instance = null


func _safe_return_to_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if is_instance_valid(lobby):
		lobby.visible = true
		lobby._show_menu("main")

	# Recarregar a cena de forma segura
	get_tree().reload_current_scene()


func _return_to_menu() -> void:
	_cleanup_spectator()

	if _game_over_instance and is_instance_valid(_game_over_instance):
		_game_over_instance.queue_free()
		_game_over_instance = null

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if is_instance_valid(lobby):
		lobby.visible = true
		lobby._show_menu("main")

	if player and is_instance_valid(player):
		player.queue_free()
		player = null

	for bunny in get_tree().get_nodes_in_group("assassin_bunny"):
		if is_instance_valid(bunny):
			bunny.queue_free()

	get_tree().reload_current_scene()
