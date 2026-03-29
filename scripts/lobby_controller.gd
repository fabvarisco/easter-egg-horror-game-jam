extends Node3D
## Lobby Controller - Manages the 3D lobby state and ready system

enum LobbyState { MENU, WAITING, COUNTDOWN, TRANSITIONING }

const COUNTDOWN_DURATION := 3
const GAME_SCENE_PATH := "res://scenes/main.tscn"

@onready var connection_menu: CanvasLayer = $ConnectionMenu
@onready var lobby_hud: CanvasLayer = $LobbyHUD
@onready var start_game_pedestal: Area3D = $StartGamePedestal
@onready var spawn_points: Node3D = $PlayerSpawnPoints
@onready var players_container: Node3D = $Players

@onready var multiplayer_manager: Node = get_node("/root/MultiplayerManager")
@onready var spawn_manager: Node = get_node("/root/SpawnManager")
@onready var lobby_camera: Camera3D = $Camera3D

var _pause_menu_scene: PackedScene = preload("res://scenes/pause_menu.tscn")
var _fade_scene: PackedScene = preload("res://scenes/fade_scene.tscn")
var _pause_menu: CanvasLayer = null
var _fade_instance: CanvasLayer = null
var _state: LobbyState = LobbyState.MENU
var _is_singleplayer: bool = true
var _countdown_timer: float = 0.0
var _countdown_value: int = COUNTDOWN_DURATION


func _ready() -> void:
	# Connect signals
	connection_menu.connection_established.connect(_on_connection_established)
	connection_menu.settings_requested.connect(_on_settings_requested)
	start_game_pedestal.player_interacted.connect(_on_pedestal_interacted)

	# Multiplayer manager signals
	multiplayer_manager.player_connected.connect(_on_player_connected)
	multiplayer_manager.player_disconnected.connect(_on_player_disconnected)
	multiplayer_manager.player_ready_changed.connect(_on_player_ready_changed)
	multiplayer_manager.all_players_ready.connect(_on_all_players_ready)
	multiplayer_manager.server_disconnected.connect(_on_server_disconnected)
	multiplayer_manager.game_starting.connect(_on_game_starting)

	# Setup pause menu
	_pause_menu = _pause_menu_scene.instantiate()
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_menu.visible = false
	_pause_menu.disconnect_requested.connect(_on_pause_menu_disconnect)
	add_child(_pause_menu)

	# Register lobby camera with CameraManager
	var camera_manager := get_node_or_null("/root/CameraManager")
	if camera_manager and lobby_camera:
		camera_manager.set_active_camera(lobby_camera)

	# Check if we're returning from a game (still connected to multiplayer)
	if _is_returning_from_game():
		_handle_return_from_game()
	else:
		# Initial state
		_set_state(LobbyState.MENU)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _state == LobbyState.WAITING:
		if _pause_menu and not _pause_menu.visible:
			_pause_menu.show_menu()


func _process(delta: float) -> void:
	if _state == LobbyState.COUNTDOWN:
		_countdown_timer -= delta
		var new_value := int(ceil(_countdown_timer))

		if new_value != _countdown_value:
			_countdown_value = new_value
			lobby_hud.show_countdown(_countdown_value)

			# Sync countdown to clients
			if not _is_singleplayer and multiplayer_manager.is_host:
				_sync_countdown.rpc(_countdown_value)

		if _countdown_timer <= 0:
			_transition_to_game()


func _set_state(new_state: LobbyState) -> void:
	_state = new_state

	match _state:
		LobbyState.MENU:
			connection_menu.visible = true
			lobby_hud.visible = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

		LobbyState.WAITING:
			connection_menu.visible = false
			lobby_hud.visible = true
			Input.mouse_mode = Input.MOUSE_MODE_CONFINED
			var audio_manager := get_node_or_null("/root/AudioManager")
			if audio_manager:
				audio_manager.play_lobby_music()

		LobbyState.COUNTDOWN:
			_countdown_timer = COUNTDOWN_DURATION
			_countdown_value = COUNTDOWN_DURATION
			lobby_hud.show_countdown(_countdown_value)

		LobbyState.TRANSITIONING:
			lobby_hud.hide_countdown()
			var audio_manager := get_node_or_null("/root/AudioManager")
			if audio_manager:
				audio_manager.stop_music()


func _is_returning_from_game() -> bool:
	# Only consider returning from game if we're in an active multiplayer session
	if multiplayer_manager.current_mode == multiplayer_manager.NetworkMode.NONE:
		return false
	if not multiplayer.has_multiplayer_peer():
		return false
	if not is_instance_valid(multiplayer.multiplayer_peer):
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _handle_return_from_game() -> void:
	# Determine if we were in singleplayer or multiplayer
	_is_singleplayer = multiplayer_manager.current_mode == multiplayer_manager.NetworkMode.NONE

	# Clean up any existing players first
	_cleanup()

	# Reset ready states for new game
	multiplayer_manager.reset_ready_states()

	# Spawn players
	_spawn_local_player()

	# Setup HUD
	lobby_hud.clear_players()

	if _is_singleplayer:
		lobby_hud.add_player(1, true)
		lobby_hud.clear_room_code()
	else:
		for peer_id in multiplayer_manager.connected_peers:
			var is_local = multiplayer_manager.is_local_player(peer_id)
			lobby_hud.add_player(peer_id, is_local)

		if multiplayer_manager.is_host and not multiplayer_manager.room_code.is_empty():
			lobby_hud.set_room_code(multiplayer_manager.room_code)
		else:
			lobby_hud.clear_room_code()

	_update_pedestal_indicators()
	_set_state(LobbyState.WAITING)


func _on_connection_established(is_singleplayer: bool) -> void:
	_is_singleplayer = is_singleplayer

	# Reset ready states
	multiplayer_manager.reset_ready_states()

	# Spawn local player
	_spawn_local_player()

	# Setup HUD
	lobby_hud.clear_players()

	if is_singleplayer:
		# Single player mode - add just local player
		lobby_hud.add_player(1, true)
		lobby_hud.clear_room_code()
	else:
		# Multiplayer - add all connected peers
		for peer_id in multiplayer_manager.connected_peers:
			var is_local = multiplayer_manager.is_local_player(peer_id)
			lobby_hud.add_player(peer_id, is_local)

		# Show room code for multiplayer
		if multiplayer_manager.is_host and not multiplayer_manager.room_code.is_empty():
			lobby_hud.set_room_code(multiplayer_manager.room_code)
		else:
			lobby_hud.clear_room_code()

	# Update pedestal indicators
	_update_pedestal_indicators()

	_set_state(LobbyState.WAITING)


func _spawn_local_player() -> void:
	# Reset spawn state for new lobby session
	spawn_manager.reset()

	if _is_singleplayer:
		spawn_manager.spawn_singleplayer()
	else:
		# Let spawn manager handle spawning all connected players
		spawn_manager.spawn_all_players()


func _on_player_connected(peer_id: int) -> void:
	if _state == LobbyState.MENU:
		return

	# Spawn the new player visually if not already spawned
	if not spawn_manager.is_player_spawned(peer_id):
		spawn_manager.spawn_player(peer_id)

	var is_local = multiplayer_manager.is_local_player(peer_id)
	lobby_hud.add_player(peer_id, is_local)
	_update_pedestal_indicators()


func _on_player_disconnected(peer_id: int) -> void:
	if _state == LobbyState.MENU:
		return

	lobby_hud.remove_player(peer_id)
	_update_pedestal_indicators()

	# Cancel countdown if someone disconnects
	if _state == LobbyState.COUNTDOWN:
		_set_state(LobbyState.WAITING)
		lobby_hud.hide_countdown()


func _on_pedestal_interacted(peer_id: int) -> void:
	if _state != LobbyState.WAITING and _state != LobbyState.COUNTDOWN:
		return

	# Toggle ready state
	var current_ready = multiplayer_manager.get_ready_state(peer_id)
	multiplayer_manager.set_player_ready(not current_ready)


func _on_player_ready_changed(peer_id: int, is_ready: bool) -> void:
	lobby_hud.update_player_ready(peer_id, is_ready)
	_update_pedestal_indicators()

	# Cancel countdown if someone becomes not ready
	if not is_ready and _state == LobbyState.COUNTDOWN:
		_set_state(LobbyState.WAITING)
		lobby_hud.hide_countdown()


func _on_all_players_ready() -> void:
	if _state == LobbyState.WAITING:
		_set_state(LobbyState.COUNTDOWN)

		# Notify clients to start countdown
		if not _is_singleplayer and multiplayer_manager.is_host:
			_start_countdown_on_clients.rpc()


func _update_pedestal_indicators() -> void:
	var ready_states = multiplayer_manager.get_all_ready_states()
	var connected_peers: Array[int] = []

	if _is_singleplayer:
		connected_peers.append(1)
	else:
		for peer_id in multiplayer_manager.connected_peers:
			connected_peers.append(peer_id)

	start_game_pedestal.update_ready_indicators(ready_states, connected_peers)


func _transition_to_game() -> void:
	_set_state(LobbyState.TRANSITIONING)

	if _is_singleplayer or multiplayer_manager.is_host:
		# Host or singleplayer initiates the transition
		if not _is_singleplayer:
			multiplayer_manager.broadcast_game_start()

		_start_fade_and_load_game()
	# Clients will receive broadcast_game_start via multiplayer_manager


func _start_fade_and_load_game() -> void:
	_fade_instance = _fade_scene.instantiate()
	add_child(_fade_instance)
	_fade_instance.fade_out_car_and_change_scene(GAME_SCENE_PATH)


func _load_game_scene() -> void:
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_server_disconnected() -> void:
	# Clean up and return to menu
	_cleanup()
	_set_state(LobbyState.MENU)
	connection_menu.show_menu()


func _on_game_starting() -> void:
	# Called on clients when host broadcasts game start
	if not multiplayer_manager.is_host:
		_set_state(LobbyState.TRANSITIONING)
		_start_fade_and_load_game()


func _cleanup() -> void:
	# Clear players using SpawnManager
	spawn_manager.clear_all_players()
	lobby_hud.clear_players()


func _on_settings_requested() -> void:
	if _pause_menu:
		_pause_menu.show_menu()


func _on_pause_menu_disconnect() -> void:
	await multiplayer_manager.leave_game()
	_cleanup()
	_set_state(LobbyState.MENU)
	connection_menu.show_menu()


# ==========================================
# MULTIPLAYER RPC
# ==========================================


@rpc("authority", "call_remote", "reliable")
func _start_countdown_on_clients() -> void:
	_set_state(LobbyState.COUNTDOWN)


@rpc("authority", "call_remote", "reliable")
func _sync_countdown(value: int) -> void:
	_countdown_value = value
	lobby_hud.show_countdown(value)
