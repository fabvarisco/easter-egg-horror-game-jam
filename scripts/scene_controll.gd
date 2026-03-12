extends Node3D

@export var list_of_points_for_eggs: Array[Vector3] = []

var _player_scene: PackedScene = preload("res://scenes/player.tscn")
var player: CharacterBody3D = null

@onready var lobby: Control = $Lobby
@onready var multiplayer_manager: Node = get_node("/root/MultiplayerManager")
@onready var spawn_points: Node3D = $PlayerSpawnPoints

var _is_singleplayer: bool = true
var _game_over_scene: PackedScene = preload("res://scenes/game_over.tscn")
var _game_over_instance: Node3D = null
var _is_spectating: bool = false
var _spectator_camera: Camera3D = null
var _spectate_target_index: int = 0


func _ready() -> void:
	lobby.game_started.connect(_on_game_started)
	multiplayer_manager.server_disconnected.connect(_on_server_disconnected)
	_connect_bunny_signals()


func _on_server_disconnected() -> void:
	_cleanup_spectator()
	_return_to_menu()


func _input(event: InputEvent) -> void:
	if _is_spectating and event.is_action_pressed("interact"):
		_switch_spectate_target()


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


func _start_singleplayer() -> void:
	# Spawn player at first spawn point
	var spawn_point: Node3D = spawn_points.get_child(0)
	player = _player_scene.instantiate()
	player.global_position = spawn_point.global_position
	$Players.add_child(player)

	player.visible = true
	player.set_physics_process(true)
	player.set_process_input(true)
	player.add_to_group("player")
	if not player.player_died.is_connected(_on_player_died):
		player.player_died.connect(_on_player_died)


func _start_multiplayer() -> void:
	# Spawn all connected players at their spawn points
	multiplayer_manager.spawn_all_players()


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

	_return_to_menu()


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
			# Todos morreram, voltar ao menu
			_cleanup_spectator()
			_return_to_menu()


func _on_all_players_dead() -> void:
	_show_game_over()


func _cleanup_spectator() -> void:
	_is_spectating = false
	if _spectator_camera:
		_spectator_camera.queue_free()
		_spectator_camera = null


func _return_to_menu() -> void:
	_cleanup_spectator()

	if _game_over_instance:
		_game_over_instance.queue_free()
		_game_over_instance = null

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	lobby.visible = true
	lobby._show_menu("main")

	if player:
		player.queue_free()
		player = null

	for bunny in get_tree().get_nodes_in_group("assassin_bunny"):
		bunny.queue_free()

	get_tree().reload_current_scene()
