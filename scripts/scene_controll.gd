extends Node3D

@export var list_of_points_for_eggs: Array[Vector3] = []

@onready var player: CharacterBody3D = $Player
@onready var lobby: Control = $Lobby

var _is_singleplayer: bool = true

func _ready() -> void:
	lobby.game_started.connect(_on_game_started)
	_connect_bunny_signals()

func _connect_bunny_signals() -> void:
	# Connect to existing bunny if any
	var bunny := get_tree().get_first_node_in_group("assassin_bunny")
	if bunny:
		if bunny.has_signal("all_players_dead") and not bunny.all_players_dead.is_connected(_on_all_players_dead):
			bunny.all_players_dead.connect(_on_all_players_dead)

func _on_game_started(is_singleplayer: bool) -> void:
	_is_singleplayer = is_singleplayer

	if is_singleplayer:
		_start_singleplayer()
	else:
		_start_multiplayer()

func _start_singleplayer() -> void:
	if player:
		player.visible = true
		player.set_physics_process(true)
		player.set_process_input(true)
		player.add_to_group("player")
		if not player.player_died.is_connected(_on_player_died):
			player.player_died.connect(_on_player_died)

func _start_multiplayer() -> void:
	# In multiplayer, the main player is hidden
	# Players are spawned by MultiplayerManager
	if player:
		player.visible = false
		player.set_physics_process(false)
		player.set_process_input(false)

func _on_player_died() -> void:
	if _is_singleplayer:
		# In singleplayer, wait a moment then return to menu
		await get_tree().create_timer(2.0).timeout
		_return_to_menu()

func _on_all_players_dead() -> void:
	# All players are dead - return to menu
	await get_tree().create_timer(1.0).timeout
	_return_to_menu()

func _return_to_menu() -> void:
	# Reset game state and show lobby
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	lobby.visible = true
	lobby._update_ui(false)

	# Reset player
	if player:
		player.visible = false
		player.set_physics_process(false)
		player.set_process_input(false)

	# Remove any spawned bunnies
	for bunny in get_tree().get_nodes_in_group("assassin_bunny"):
		bunny.queue_free()

	# Reload the scene to reset everything
	get_tree().reload_current_scene()
