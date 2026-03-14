extends Node3D
## Game Controller - Manages gameplay (eggs, bunny, game over)

@export var list_of_points_for_eggs: Array[Vector3] = []

var _player_scene: PackedScene = preload("res://scenes/player.tscn")
var _egg_scene: PackedScene = preload("res://scenes/egg.tscn")

@onready var multiplayer_manager: Node = get_node("/root/MultiplayerManager")
@onready var spawn_points: Node3D = $PlayerSpawnPoints
@onready var egg_spawn_points: Node3D = $EggSpawnPoints
@onready var players_container: Node3D = $Players

var _is_singleplayer: bool = true
var _game_over_scene: PackedScene = preload("res://scenes/game_over.tscn")
var _game_over_instance: Node3D = null
var _is_spectating: bool = false
var _spectator_camera: Camera3D = null
var _spectate_target_index: int = 0


func _ready() -> void:
	multiplayer_manager.server_disconnected.connect(_on_server_disconnected)

	# Determine if singleplayer based on network mode
	_is_singleplayer = multiplayer_manager.current_mode == multiplayer_manager.NetworkMode.NONE

	# Spawn players and start game
	_start_game()
	_connect_bunny_signals()


func _start_game() -> void:
	if _is_singleplayer:
		_spawn_singleplayer()
	else:
		_spawn_multiplayer()

	# Spawn eggs after players
	spawn_eggs()


func _spawn_singleplayer() -> void:
	var spawn_point: Node3D = spawn_points.get_child(0)
	var player := _player_scene.instantiate()
	player.name = "1"
	player.set_meta("peer_id", 1)
	player.global_position = spawn_point.global_position
	player.add_to_group("players")
	player.add_to_group("player")
	players_container.add_child(player)

	player.visible = true
	player.set_physics_process(true)
	player.set_process_input(true)

	if not player.player_died.is_connected(_on_player_died):
		player.player_died.connect(_on_player_died)

	multiplayer_manager.players[1] = player


func _spawn_multiplayer() -> void:
	multiplayer_manager.spawn_all_players()

	# Connect death signals for all players
	for peer_id in multiplayer_manager.players:
		var player: Node3D = multiplayer_manager.players[peer_id]
		if player.has_signal("player_died") and not player.player_died.is_connected(_on_player_died):
			player.player_died.connect(_on_player_died)


func _on_server_disconnected() -> void:
	_cleanup_spectator()
	_cleanup_all_players()
	_cleanup_game_objects()
	call_deferred("_safe_return_to_lobby")


func _input(event: InputEvent) -> void:
	if _is_spectating and event.is_action_pressed("interact"):
		_switch_spectate_target()


func _connect_bunny_signals() -> void:
	var bunny := get_tree().get_first_node_in_group("assassin_bunny")
	if bunny:
		if bunny.has_signal("all_players_dead") and not bunny.all_players_dead.is_connected(_on_all_players_dead):
			bunny.all_players_dead.connect(_on_all_players_dead)


func spawn_eggs() -> void:
	if not egg_spawn_points:
		return

	var egg_count: int = egg_spawn_points.get_child_count()
	if egg_count == 0:
		return

	var monster_count: int = egg_count / 2
	print("Spawning ", egg_count, " eggs (", monster_count, " monsters)")

	var indices: Array[int] = []
	for i in range(egg_count):
		indices.append(i)
	indices.shuffle()

	for i in range(egg_count):
		var spawn_point: Node3D = egg_spawn_points.get_child(i)
		var egg: Node3D = _egg_scene.instantiate()
		egg.global_position = spawn_point.global_position

		if indices.find(i) < monster_count:
			egg.is_monster = true

		add_child(egg)


func _on_player_died() -> void:
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

	_return_to_lobby()


func _start_spectator_mode() -> void:
	_is_spectating = true

	_spectator_camera = Camera3D.new()
	_spectator_camera.name = "SpectatorCamera"
	add_child(_spectator_camera)
	_spectator_camera.current = true

	_spectate_target_index = 0


func _switch_spectate_target() -> void:
	var alive_players := _get_alive_players()
	if alive_players.size() == 0:
		return

	_spectate_target_index = (_spectate_target_index + 1) % alive_players.size()


func _get_alive_players() -> Array:
	var alive := []
	for p in get_tree().get_nodes_in_group("players"):
		if p.has_method("is_dead") and not p.is_dead():
			alive.append(p)
		elif not p.has_method("is_dead"):
			alive.append(p)
	return alive


func _process(_delta: float) -> void:
	if _is_spectating and _spectator_camera:
		var alive_players := _get_alive_players()
		if alive_players.size() > 0:
			_spectate_target_index = min(_spectate_target_index, alive_players.size() - 1)
			var target: Node3D = alive_players[_spectate_target_index]
			var offset := Vector3(0, 5, 5)
			_spectator_camera.global_position = target.global_position + offset
			_spectator_camera.look_at(target.global_position, Vector3.UP)
		else:
			_cleanup_spectator()
			_return_to_lobby()


func _on_all_players_dead() -> void:
	_show_game_over()


func _cleanup_spectator() -> void:
	_is_spectating = false
	if _spectator_camera and is_instance_valid(_spectator_camera):
		_spectator_camera.queue_free()
		_spectator_camera = null


func _cleanup_all_players() -> void:
	if players_container:
		for child in players_container.get_children():
			if is_instance_valid(child):
				child.queue_free()

	multiplayer_manager.players.clear()


func _cleanup_game_objects() -> void:
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://scenes/lobby_3d.tscn")


func _return_to_lobby() -> void:
	_cleanup_spectator()

	if _game_over_instance and is_instance_valid(_game_over_instance):
		_game_over_instance.queue_free()
		_game_over_instance = null

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	for bunny in get_tree().get_nodes_in_group("assassin_bunny"):
		if is_instance_valid(bunny):
			bunny.queue_free()

	get_tree().change_scene_to_file("res://scenes/lobby_3d.tscn")
