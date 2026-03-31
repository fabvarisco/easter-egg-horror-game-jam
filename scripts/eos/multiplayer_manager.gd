extends Node
## Multiplayer Manager - EOS multiplayer interface

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded
signal connection_failed
signal server_disconnected
signal room_created(code: String)
signal lobby_join_failed(reason: String)
signal player_ready_changed(peer_id: int, is_ready: bool)
signal all_players_ready
signal game_starting


enum NetworkMode { NONE, EOS }


const MAX_PLAYERS = 4
const GAME_ID = "easteregghorror"


var player_scene: PackedScene = preload("res://scenes/player/player.tscn")
var players: Dictionary = {}
var connected_peers: Array[int] = []  # Track connected peers before game starts
var room_code: String = ""
var is_host: bool = false
var my_peer_id: int = 0
var host_name: String = "Player"
var current_mode: NetworkMode = NetworkMode.NONE

# Ready system
var _ready_states: Dictionary = {}  # peer_id -> bool

# Player model indices - assigned once per player and persisted across scenes
var _player_model_indices: Dictionary = {}  # peer_id -> model_index
const NUM_PLAYER_MODELS: int = 5  # Must match PLAYER_MODELS.size() in player.gd


# EOS variables
var _eos_available: bool = false
var _eos_initialized: bool = false
var _eos_peer: EOSGMultiplayerPeer
var _current_lobby: HLobby
var _local_product_user_id: String = ""

# PUID to peer_id mapping for voice chat
var puid_to_peer_id: Dictionary = {}  # product_user_id -> peer_id
var peer_id_to_puid: Dictionary = {}  # peer_id -> product_user_id

var _is_quitting: bool = false


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Prevent auto-quit so we can cleanup properly
	get_tree().set_auto_accept_quit(false)

	_check_eos_available()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _is_quitting:
			return  # Already handling quit
		_is_quitting = true
		_handle_quit()
	elif what == NOTIFICATION_EXIT_TREE:
		_cleanup_on_exit()


func _handle_quit() -> void:
	# Disable all processing immediately to prevent callbacks during shutdown
	set_process(false)
	set_physics_process(false)

	# Clear multiplayer peer FIRST to stop any network callbacks
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer = null

	if _eos_peer:
		_eos_peer.close()
		_eos_peer = null

	# Clear references
	_current_lobby = null
	players.clear()
	connected_peers.clear()
	puid_to_peer_id.clear()
	peer_id_to_puid.clear()

	get_tree().quit()


# ==========================================
# EOS AVAILABILITY & INIT
# ==========================================


func _check_eos_available() -> void:
	_eos_available = ClassDB.class_exists("EOSGMultiplayerPeer")

	pass


func is_eos_available() -> bool:
	return _eos_available


func _initialize_eos() -> bool:
	if _eos_initialized:
		return true

	if not _eos_available:
		return false

	# 1. Initialize EOS Platform
	var init_opts = EOS.Platform.InitializeOptions.new()
	init_opts.product_name = EOSConfig.PRODUCT_NAME
	init_opts.product_version = EOSConfig.PRODUCT_VERSION

	var init_result = EOS.Platform.PlatformInterface.initialize(init_opts)
	if init_result != EOS.Result.Success and init_result != EOS.Result.AlreadyConfigured:
		push_error("[EOS] Failed to initialize: " + EOS.result_str(init_result))
		return false

	# 2. Create EOS Platform
	var create_opts = EOS.Platform.CreateOptions.new()
	create_opts.product_id = EOSConfig.PRODUCT_ID
	create_opts.sandbox_id = EOSConfig.SANDBOX_ID
	create_opts.deployment_id = EOSConfig.DEPLOYMENT_ID
	create_opts.client_id = EOSConfig.CLIENT_ID
	create_opts.client_secret = EOSConfig.CLIENT_SECRET
	create_opts.encryption_key = EOSConfig.ENCRYPTION_KEY

	var create_result = EOS.Platform.PlatformInterface.create(create_opts)
	if not create_result:
		push_error("[EOS] Failed to create platform")
		return false

	# 3. Setup logging
	EOS.Logging.set_log_level(EOS.Logging.LogCategory.AllCategories, EOS.Logging.LogLevel.Info)

	# 4. Login anonymously
	var login_success = await HAuth.login_anonymous_async("Player")
	if not login_success:
		push_error("[EOS] Anonymous login failed")
		return false

	_local_product_user_id = HAuth.product_user_id
	_eos_initialized = true
	my_peer_id = abs(hash(_local_product_user_id)) % 1000000
	return true

# ==========================================
# EOS MULTIPLAYER
# ==========================================


func host_game_eos(room_name: String = "Game") -> void:
	if not _eos_available:
		push_error("[EOS] Plugin not available")
		lobby_join_failed.emit("Online services unavailable. Please restart the game.")
		connection_failed.emit()
		return

	current_mode = NetworkMode.EOS
	is_host = true
	host_name = room_name

	if not _eos_initialized:
		var success := await _initialize_eos()
		if not success:
			lobby_join_failed.emit("Connection failed. Check your internet and try again.")
			connection_failed.emit()
			current_mode = NetworkMode.NONE
			return

	# Create lobby using high-level API
	var create_opts := EOS.Lobby.CreateLobbyOptions.new()
	create_opts.bucket_id = GAME_ID
	create_opts.max_lobby_members = MAX_PLAYERS
	create_opts.enable_rtc_room = true  # Enable voice chat

	_current_lobby = await HLobbies.create_lobby_async(create_opts)
	if not _current_lobby:
		push_error("[EOS] Failed to create lobby")
		lobby_join_failed.emit("Failed to create room. Server may be unavailable.")
		connection_failed.emit()
		current_mode = NetworkMode.NONE
		return

	# Create P2P server
	_eos_peer = EOSGMultiplayerPeer.new()
	var result := _eos_peer.create_server(GAME_ID)
	if result != OK:
		push_error("[EOS] Failed to create P2P server: " + str(result))
		# Cleanup on failure
		if _eos_peer:
			_eos_peer.close()
			_eos_peer = null
		if _current_lobby:
			_current_lobby.destroy_async()
			_current_lobby = null
		lobby_join_failed.emit("Failed to start server. Check your firewall settings.")
		connection_failed.emit()
		current_mode = NetworkMode.NONE
		return

	multiplayer.multiplayer_peer = _eos_peer
	room_code = _generate_lobby_code(_current_lobby.lobby_id)
	my_peer_id = 1

	if not connected_peers.has(my_peer_id):
		connected_peers.append(my_peer_id)

	# Assign model index to host
	assign_local_model_index()

	# Register own PUID for voice chat mapping
	puid_to_peer_id[_local_product_user_id] = my_peer_id
	peer_id_to_puid[my_peer_id] = _local_product_user_id

	room_created.emit(room_code)
	connection_succeeded.emit()


func join_game_eos(code: String) -> void:
	if not _eos_available:
		lobby_join_failed.emit("Online services unavailable. Please restart the game.")
		return

	current_mode = NetworkMode.EOS
	is_host = false
	room_code = code.to_upper()

	if not _eos_initialized:
		var success := await _initialize_eos()
		if not success:
			lobby_join_failed.emit("Connection failed. Check your internet and try again.")
			current_mode = NetworkMode.NONE
			return

	# Search for lobbies by bucket_id
	var lobbies = await HLobbies.search_by_bucket_id_async(GAME_ID)
	if not lobbies or lobbies.size() == 0:
		lobby_join_failed.emit("No rooms found. Check if the host is still online.")
		current_mode = NetworkMode.NONE
		return

	# Find lobby matching the code
	for lobby in lobbies:
		var found_code := _generate_lobby_code(lobby.lobby_id)
		if found_code == room_code:

			# Join the lobby
			var joined_lobby = await HLobbies.join_by_id_async(lobby.lobby_id)
			if not joined_lobby:
				lobby_join_failed.emit("Failed to join room. It may be full or closed.")
				current_mode = NetworkMode.NONE
				return

			# Create P2P client connection to lobby owner
			_eos_peer = EOSGMultiplayerPeer.new()
			var result := _eos_peer.create_client(GAME_ID, lobby.owner_product_user_id)
			if result != OK:
				push_error("[EOS] Failed to create P2P client: " + str(result))
				# Cleanup on failure
				if _eos_peer:
					_eos_peer.close()
					_eos_peer = null
				if joined_lobby:
					joined_lobby.leave_async()
				_current_lobby = null
				lobby_join_failed.emit("Connection failed. Check your firewall or try again.")
				current_mode = NetworkMode.NONE
				return

			multiplayer.multiplayer_peer = _eos_peer
			_current_lobby = joined_lobby
			return

	lobby_join_failed.emit("Room '" + room_code + "' not found. Check the code and try again.")
	current_mode = NetworkMode.NONE


# ==========================================
# EOS: Notificações de Lobby
# ==========================================


func _generate_lobby_code(lobby_id: String) -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var hash_val := hash(lobby_id)
	var code := ""
	for i in range(6):
		code += chars[abs(hash_val >> (i * 5)) % chars.length()]
	return code


# ==========================================
# SHARED
# ==========================================


func leave_game() -> void:
	if _is_quitting:
		return

	# Aguardar RPCs pendentes (with safety check)
	if is_inside_tree() and get_tree() != null:
		await get_tree().create_timer(0.3).timeout

	if current_mode == NetworkMode.EOS:
		if is_inside_tree() and get_tree() != null:
			await _leave_eos()
		else:
			_leave_eos_sync()

	# Agora sim limpar
	current_mode = NetworkMode.NONE
	_clear_players()
	connected_peers.clear()
	puid_to_peer_id.clear()
	peer_id_to_puid.clear()
	_player_model_indices.clear()
	room_code = ""
	is_host = false
	my_peer_id = 0


func _leave_eos_sync() -> void:
	"""Synchronous EOS cleanup for when tree is not available"""
	if _eos_peer:
		_eos_peer.close()
		_eos_peer = null
	multiplayer.multiplayer_peer = null
	_current_lobby = null


func _leave_eos() -> void:
	# Close peer first to stop network traffic
	if _eos_peer:
		_eos_peer.close()
		_eos_peer = null

	multiplayer.multiplayer_peer = null

	# Handle lobby cleanup - fire and forget to avoid blocking
	if _current_lobby and not _is_quitting:
		var lobby_ref := _current_lobby
		_current_lobby = null  # Clear reference immediately to prevent re-entry

		# Start async cleanup but don't wait indefinitely
		if is_host:
			lobby_ref.destroy_async()
		else:
			lobby_ref.leave_async()

		# Give a brief moment for the cleanup to start (with safety check)
		if is_inside_tree() and get_tree() != null:
			await get_tree().create_timer(0.1).timeout
	else:
		_current_lobby = null


func _cleanup_on_exit() -> void:
	# Synchronous cleanup when game is closing
	multiplayer.multiplayer_peer = null

	if _eos_peer:
		_eos_peer.close()
		_eos_peer = null

	_current_lobby = null
	players.clear()
	connected_peers.clear()
	puid_to_peer_id.clear()
	peer_id_to_puid.clear()


# ==========================================
# Connection Callbacks
# ==========================================


func _on_peer_connected(id: int) -> void:
	if _is_quitting or current_mode == NetworkMode.NONE:
		return
	if not connected_peers.has(id):
		connected_peers.append(id)

	# Host sends existing data to new peer
	if is_host:
		# Assign a random model index to the new peer if not already assigned
		if not _player_model_indices.has(id):
			_player_model_indices[id] = randi() % NUM_PLAYER_MODELS

		# Send existing ready states
		for peer_id in _ready_states:
			_sync_ready_state.rpc_id(id, peer_id, _ready_states[peer_id])

		# Send all model indices to new peer
		for peer_id in _player_model_indices:
			_sync_model_index.rpc_id(id, peer_id, _player_model_indices[peer_id])

		# Send list of all connected peers so new client knows about everyone
		_sync_peer_list.rpc_id(id, connected_peers)

	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if _is_quitting or current_mode == NetworkMode.NONE:
		return
	connected_peers.erase(id)
	_remove_player(id)
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	if _is_quitting or current_mode == NetworkMode.NONE:
		return
	my_peer_id = multiplayer.get_unique_id()
	if not connected_peers.has(my_peer_id):
		connected_peers.append(my_peer_id)

	# Assign local model index (will be overwritten by host sync if needed)
	assign_local_model_index()

	# Register PUID mapping for voice chat (EOS only)
	if current_mode == NetworkMode.EOS and _local_product_user_id != "":
		_register_puid.rpc(_local_product_user_id, my_peer_id)

	connection_succeeded.emit()


func _on_connection_failed() -> void:
	if _is_quitting or current_mode == NetworkMode.NONE:
		return
	connection_failed.emit()


func _on_server_disconnected() -> void:
	if _is_quitting:
		return
	_clear_players()
	connected_peers.clear()
	current_mode = NetworkMode.NONE
	room_code = ""
	is_host = false
	my_peer_id = 0
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()


# ==========================================
# Player Management
# ==========================================


func send_game_data(data: Dictionary, target: int = 0) -> void:
	_send_network_data(data, target)


func _send_network_data(data: Dictionary, target: int = 0) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if target == 0:
		_broadcast_game_data.rpc(data)
	else:
		_receive_game_data.rpc_id(target, data)




@rpc("any_peer", "call_local", "reliable")
func _broadcast_game_data(data: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = my_peer_id
	_handle_game_data(sender_id, data)


@rpc("any_peer", "reliable")
func _receive_game_data(data: Dictionary) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	_handle_game_data(sender_id, data)


func _handle_game_data(from_peer: int, data: Dictionary) -> void:
	match data.get("action", ""):
		"sync_position":
			_sync_player_position(from_peer, data)
		"spawn_player":
			if not players.has(from_peer):
				var spawn_manager := get_node_or_null("/root/SpawnManager")
				if spawn_manager:
					spawn_manager.spawn_player(from_peer)


func _sync_player_position(peer_id: int, data: Dictionary) -> void:
	if not players.has(peer_id):
		return
	var player: Node3D = players[peer_id]
	if is_instance_valid(player):
		player.global_position = Vector3(data.get("x", 0.0), data.get("y", 0.0), data.get("z", 0.0))
		player.rotation.y = data.get("rot_y", 0.0)


func _remove_player(id: int) -> void:
	var spawn_manager := get_node_or_null("/root/SpawnManager")
	if spawn_manager:
		spawn_manager.remove_player(id)
	else:
		# Fallback if SpawnManager not available
		if not players.has(id):
			return
		var player: Node = players[id]
		if is_instance_valid(player):
			player.queue_free()
		players.erase(id)


func _clear_players() -> void:
	var spawn_manager := get_node_or_null("/root/SpawnManager")
	if spawn_manager:
		spawn_manager.clear_all_players()
	else:
		# Fallback if SpawnManager not available
		for id in players.keys():
			var player: Node = players[id]
			if is_instance_valid(player):
				player.queue_free()
		players.clear()


func spawn_all_players() -> void:
	var spawn_manager := get_node_or_null("/root/SpawnManager")
	if spawn_manager:
		spawn_manager.spawn_all_players()
	else:
		push_error("[MultiplayerManager] SpawnManager not found!")

	# Aguardar registro de PUIDs antes de ativar voice (EOS apenas)
	if current_mode == NetworkMode.EOS:
		call_deferred("_verify_puid_registration")


func _verify_puid_registration() -> void:
	"""Verifica e loga o estado do registro de PUIDs para debug"""
	await get_tree().create_timer(0.5).timeout


func is_local_player(peer_id: int) -> bool:
	return peer_id == my_peer_id


# ==========================================
# READY SYSTEM
# ==========================================

func set_player_ready(is_ready: bool) -> void:
	if current_mode == NetworkMode.NONE:
		# Singleplayer mode
		_ready_states[1] = is_ready
		player_ready_changed.emit(1, is_ready)
		if is_ready:
			all_players_ready.emit()
	else:
		# Multiplayer mode - sync via RPC
		_sync_ready_state.rpc(my_peer_id, is_ready)


func get_ready_state(peer_id: int) -> bool:
	return _ready_states.get(peer_id, false)


func get_all_ready_states() -> Dictionary:
	return _ready_states.duplicate() as Dictionary


func reset_ready_states() -> void:
	_ready_states.clear()


func _check_all_ready() -> void:
	if connected_peers.size() == 0:
		return

	for peer_id in connected_peers:
		if not _ready_states.get(peer_id, false):
			return

	# All players are ready
	all_players_ready.emit()


@rpc("any_peer", "call_local", "reliable")
func _sync_ready_state(peer_id: int, is_ready: bool) -> void:
	_ready_states[peer_id] = is_ready
	player_ready_changed.emit(peer_id, is_ready)

	if is_host:
		_check_all_ready()


func broadcast_game_start() -> void:
	if current_mode != NetworkMode.NONE:
		_receive_game_start.rpc()


@rpc("authority", "call_local", "reliable")
func _receive_game_start() -> void:
	game_starting.emit()


@rpc("authority", "reliable")
func _sync_peer_list(peers: Array) -> void:
	for peer_id in peers:
		if not connected_peers.has(peer_id):
			connected_peers.append(peer_id)
			player_connected.emit(peer_id)


# ==========================================
# PLAYER MODEL INDEX SYSTEM
# ==========================================


@rpc("authority", "call_local", "reliable")
func _sync_model_index(peer_id: int, model_index: int) -> void:
	_player_model_indices[peer_id] = model_index


func get_player_model_index(peer_id: int) -> int:
	"""Returns the model index for a player, or -1 if not assigned"""
	return _player_model_indices.get(peer_id, -1)


func assign_local_model_index() -> void:
	"""Assigns a model index to the local player (called when hosting or in singleplayer)"""
	if not _player_model_indices.has(my_peer_id):
		_player_model_indices[my_peer_id] = randi() % NUM_PLAYER_MODELS


# ==========================================
# PUID REGISTRATION FOR VOICE CHAT
# ==========================================


@rpc("any_peer", "call_local", "reliable")
func _register_puid(puid: String, peer_id: int) -> void:
	puid_to_peer_id[puid] = peer_id
	peer_id_to_puid[peer_id] = puid


func get_current_lobby() -> HLobby:
	return _current_lobby


func get_local_puid() -> String:
	return _local_product_user_id
