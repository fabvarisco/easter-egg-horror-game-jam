extends Node
## Multiplayer Manager - Unified interface for LAN and EOS multiplayer

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded
signal connection_failed
signal room_created(code: String)
signal server_found(server_info: Dictionary)
signal lobby_join_failed(reason: String)

enum NetworkMode { NONE, LAN, EOS }

const MAX_PLAYERS = 4
const DEFAULT_PORT = 7777
const BROADCAST_PORT = 7778
const BROADCAST_INTERVAL = 1.0

var player_scene: PackedScene = preload("res://scenes/player.tscn")
var players: Dictionary = {}
var room_code: String = ""
var is_host: bool = false
var my_peer_id: int = 0
var host_name: String = "Player"
var current_mode: NetworkMode = NetworkMode.NONE

# LAN variables
var _peer: ENetMultiplayerPeer
var _broadcast_socket: PacketPeerUDP
var _listen_socket: PacketPeerUDP
var _broadcast_timer: float = 0.0
var _is_broadcasting: bool = false
var _is_listening: bool = false
var _found_servers: Dictionary = {}

# EOS variables
var _eos_available: bool = false
var _eos_initialized: bool = false
var _current_lobby_id: String = ""

@onready var spawn_points: Array[Vector3] = [
	Vector3(0, 1, 0),
	Vector3(2, 1, 0),
	Vector3(-2, 1, 0),
	Vector3(0, 1, 2),
]

func _ready() -> void:
	# Setup LAN multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)

	# Check for EOS plugin
	_check_eos_available()

func _check_eos_available() -> void:
	_eos_available = ClassDB.class_exists("HLobby")

	if _eos_available:
		print("EOS plugin detected - online multiplayer available")
		# Connect EOS signals
		HLobby.create_lobby_callback.connect(_on_eos_lobby_created)
		HLobby.join_lobby_callback.connect(_on_eos_lobby_joined)
		HLobby.leave_lobby_callback.connect(_on_eos_lobby_left)
		HLobby.member_update_received.connect(_on_eos_member_update)
	else:
		print("EOS plugin not installed - LAN only mode")

func is_eos_available() -> bool:
	return _eos_available

func _process(delta: float) -> void:
	if current_mode != NetworkMode.LAN:
		return

	# LAN: Broadcast server presence
	if _is_broadcasting:
		_broadcast_timer += delta
		if _broadcast_timer >= BROADCAST_INTERVAL:
			_broadcast_timer = 0.0
			_send_broadcast()

	# LAN: Listen for servers
	if _is_listening and _listen_socket:
		while _listen_socket.get_available_packet_count() > 0:
			var packet := _listen_socket.get_packet()
			var sender_ip := _listen_socket.get_packet_ip()
			_handle_broadcast(packet, sender_ip)

	# Clean old servers
	var now := Time.get_ticks_msec()
	var to_remove: Array[String] = []
	for ip in _found_servers:
		if now - _found_servers[ip].time > 3000:
			to_remove.append(ip)
	for ip in to_remove:
		_found_servers.erase(ip)

# ==========================================
# EOS INITIALIZATION
# ==========================================

func _initialize_eos() -> bool:
	if _eos_initialized:
		return true

	if not _eos_available:
		return false

	print("Initializing EOS...")

	# Setup credentials from config
	var init_options := {
		"product_name": EOSConfig.PRODUCT_NAME,
		"product_version": EOSConfig.PRODUCT_VERSION,
		"product_id": EOSConfig.PRODUCT_ID,
		"sandbox_id": EOSConfig.SANDBOX_ID,
		"deployment_id": EOSConfig.DEPLOYMENT_ID,
		"client_id": EOSConfig.CLIENT_ID,
		"client_secret": EOSConfig.CLIENT_SECRET,
	}

	var result = IEOS.platform_create(init_options)
	if result != OK:
		push_error("Failed to initialize EOS platform: " + str(result))
		return false

	# Login with Device ID (anonymous)
	print("Logging in with Device ID...")
	HAuth.login_callback.connect(_on_eos_login, CONNECT_ONE_SHOT)
	HAuth.login_device_id()

	# Wait for login
	await HAuth.login_callback

	_eos_initialized = HAuth.logged_in
	if _eos_initialized:
		print("EOS initialized successfully! User: ", HAuth.product_user_id)
		my_peer_id = hash(HAuth.product_user_id) % 1000000
	else:
		push_error("EOS login failed")

	return _eos_initialized

func _on_eos_login(result_code: int) -> void:
	if result_code == 0:
		print("EOS Login successful")
	else:
		push_error("EOS Login failed with code: " + str(result_code))

# ==========================================
# LAN MULTIPLAYER
# ==========================================

func host_game_lan(player_name: String = "Host") -> void:
	current_mode = NetworkMode.LAN
	host_name = player_name
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(DEFAULT_PORT, MAX_PLAYERS)

	if error != OK:
		push_error("Failed to create server: " + str(error))
		connection_failed.emit()
		return

	multiplayer.multiplayer_peer = _peer
	is_host = true
	my_peer_id = 1
	room_code = host_name

	_start_broadcasting()
	_add_player(my_peer_id)
	room_created.emit(host_name)
	connection_succeeded.emit()

func join_game_lan(ip: String) -> void:
	current_mode = NetworkMode.LAN
	_stop_listening()

	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(ip, DEFAULT_PORT)

	if error != OK:
		push_error("Failed to connect to server: " + str(error))
		connection_failed.emit()
		return

	multiplayer.multiplayer_peer = _peer
	is_host = false
	room_code = ip

func start_searching_lan() -> void:
	_found_servers.clear()
	_start_listening()

func stop_searching_lan() -> void:
	_stop_listening()

func get_found_servers() -> Dictionary:
	return _found_servers

# ==========================================
# EOS MULTIPLAYER
# ==========================================

func host_game_eos(room_name: String = "Game") -> void:
	if not _eos_available:
		push_error("EOS not available")
		connection_failed.emit()
		return

	current_mode = NetworkMode.EOS
	is_host = true
	host_name = room_name

	# Initialize EOS if needed
	if not _eos_initialized:
		var success = await _initialize_eos()
		if not success:
			lobby_join_failed.emit("EOS initialization failed")
			connection_failed.emit()
			current_mode = NetworkMode.NONE
			return

	print("Creating EOS lobby...")

	# Create lobby
	var lobby_options := {
		"max_lobby_members": MAX_PLAYERS,
		"permission_level": HLobby.LobbyPermissionLevel.PUBLICADVERTISED,
		"bucket_id": "easter_egg_horror",
		"lobby_attributes": {
			"room_name": room_name,
			"game_id": "easter_egg_horror"
		}
	}

	HLobby.create_lobby(lobby_options)

func _on_eos_lobby_created(result_code: int, lobby_id: String) -> void:
	if result_code != 0:
		push_error("Failed to create lobby: " + str(result_code))
		lobby_join_failed.emit("Failed to create lobby")
		connection_failed.emit()
		current_mode = NetworkMode.NONE
		return

	_current_lobby_id = lobby_id
	room_code = _generate_lobby_code(lobby_id)

	print("Lobby created! Code: ", room_code)

	_add_player(my_peer_id)
	room_created.emit(room_code)
	connection_succeeded.emit()

func join_game_eos(code: String) -> void:
	if not _eos_available:
		lobby_join_failed.emit("EOS not available")
		return

	current_mode = NetworkMode.EOS
	is_host = false
	room_code = code.to_upper()

	# Initialize EOS if needed
	if not _eos_initialized:
		var success = await _initialize_eos()
		if not success:
			lobby_join_failed.emit("EOS initialization failed")
			current_mode = NetworkMode.NONE
			return

	print("Searching for lobby with code: ", room_code)

	# Search for lobbies
	var search_options := {
		"bucket_id": "easter_egg_horror",
		"max_results": 50
	}

	HLobby.search_callback.connect(_on_eos_search_complete.bind(room_code), CONNECT_ONE_SHOT)
	HLobby.search_lobbies(search_options)

func _on_eos_search_complete(result_code: int, lobbies: Array, target_code: String) -> void:
	if result_code != 0:
		lobby_join_failed.emit("Search failed")
		current_mode = NetworkMode.NONE
		return

	print("Found ", lobbies.size(), " lobbies")

	# Find lobby with matching code
	for lobby in lobbies:
		var lobby_id: String = lobby.get("lobby_id", "")
		var found_code := _generate_lobby_code(lobby_id)
		print("Checking lobby ", lobby_id, " -> code: ", found_code)

		if found_code == target_code:
			print("Found matching lobby! Joining...")
			HLobby.join_lobby(lobby_id)
			return

	lobby_join_failed.emit("Lobby not found: " + target_code)
	current_mode = NetworkMode.NONE

func _on_eos_lobby_joined(result_code: int, lobby_id: String) -> void:
	if result_code != 0:
		push_error("Failed to join lobby: " + str(result_code))
		lobby_join_failed.emit("Failed to join lobby")
		current_mode = NetworkMode.NONE
		return

	_current_lobby_id = lobby_id
	print("Joined lobby: ", lobby_id)

	_add_player(my_peer_id)
	connection_succeeded.emit()

func _on_eos_lobby_left(result_code: int, lobby_id: String) -> void:
	print("Left lobby: ", lobby_id)
	_current_lobby_id = ""

func _on_eos_member_update(lobby_id: String, member_id: String, update_type: int) -> void:
	if lobby_id != _current_lobby_id:
		return

	var peer_id = hash(member_id) % 1000000

	# 0 = joined, 1 = left, 2 = updated
	match update_type:
		0:  # Joined
			if peer_id != my_peer_id:
				print("EOS: Player joined: ", peer_id)
				_add_player(peer_id)
				player_connected.emit(peer_id)
		1:  # Left
			print("EOS: Player left: ", peer_id)
			_remove_player(peer_id)
			player_disconnected.emit(peer_id)

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
	match current_mode:
		NetworkMode.LAN:
			_leave_lan()
		NetworkMode.EOS:
			_leave_eos()

	current_mode = NetworkMode.NONE
	_clear_players()
	room_code = ""
	is_host = false
	my_peer_id = 0

func _leave_lan() -> void:
	_stop_broadcasting()
	_stop_listening()

	if _peer:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null

func _leave_eos() -> void:
	if _current_lobby_id != "":
		HLobby.leave_lobby(_current_lobby_id)
		_current_lobby_id = ""

# ==========================================
# LAN Helpers
# ==========================================

func _on_peer_connected(id: int) -> void:
	if current_mode != NetworkMode.LAN:
		return
	print("Peer connected: ", id)
	_add_player(id)
	player_connected.emit(id)

func _on_peer_disconnected(id: int) -> void:
	if current_mode != NetworkMode.LAN:
		return
	print("Peer disconnected: ", id)
	_remove_player(id)
	player_disconnected.emit(id)

func _on_connected_to_server() -> void:
	if current_mode != NetworkMode.LAN:
		return
	print("Connected to server!")
	my_peer_id = multiplayer.get_unique_id()
	_add_player(my_peer_id)
	connection_succeeded.emit()

func _on_connection_failed() -> void:
	if current_mode != NetworkMode.LAN:
		return
	print("Connection failed!")
	connection_failed.emit()

func _start_broadcasting() -> void:
	_broadcast_socket = PacketPeerUDP.new()
	_broadcast_socket.set_broadcast_enabled(true)
	_broadcast_socket.set_dest_address("255.255.255.255", BROADCAST_PORT)
	_is_broadcasting = true
	_broadcast_timer = 0.0

func _stop_broadcasting() -> void:
	_is_broadcasting = false
	if _broadcast_socket:
		_broadcast_socket.close()
		_broadcast_socket = null

func _send_broadcast() -> void:
	if not _broadcast_socket:
		return

	var data := {
		"game": "easter_egg_horror",
		"name": host_name,
		"players": players.size(),
		"max": MAX_PLAYERS
	}
	var json := JSON.stringify(data)
	_broadcast_socket.put_packet(json.to_utf8_buffer())

func _start_listening() -> void:
	_listen_socket = PacketPeerUDP.new()
	var error := _listen_socket.bind(BROADCAST_PORT)
	if error != OK:
		push_error("Failed to bind listen socket: " + str(error))
		return
	_is_listening = true

func _stop_listening() -> void:
	_is_listening = false
	if _listen_socket:
		_listen_socket.close()
		_listen_socket = null

func _handle_broadcast(packet: PackedByteArray, sender_ip: String) -> void:
	var json := packet.get_string_from_utf8()
	var data: Variant = JSON.parse_string(json)

	if data == null or not data is Dictionary:
		return

	if data.get("game") != "easter_egg_horror":
		return

	var server_info := {
		"name": data.get("name", "Unknown"),
		"players": data.get("players", 1),
		"max": data.get("max", MAX_PLAYERS),
		"ip": sender_ip,
		"time": Time.get_ticks_msec()
	}

	var is_new := not _found_servers.has(sender_ip)
	_found_servers[sender_ip] = server_info

	if is_new:
		server_found.emit(server_info)

# ==========================================
# Player Management
# ==========================================

func send_game_data(data: Dictionary, target: int = 0) -> void:
	match current_mode:
		NetworkMode.LAN:
			_send_lan_data(data, target)
		NetworkMode.EOS:
			_send_eos_data(data)

func _send_lan_data(data: Dictionary, target: int = 0) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if target == 0:
		_broadcast_game_data.rpc(data)
	else:
		_receive_game_data.rpc_id(target, data)

func _send_eos_data(data: Dictionary) -> void:
	if _current_lobby_id == "":
		return
	var json := JSON.stringify(data)
	HP2P.send_packet_to_lobby(_current_lobby_id, json.to_utf8_buffer())

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
	var action: String = data.get("action", "")

	match action:
		"sync_position":
			_sync_player_position(from_peer, data)
		"spawn_player":
			if not players.has(from_peer):
				_add_player(from_peer)

func _sync_player_position(peer_id: int, data: Dictionary) -> void:
	if not players.has(peer_id):
		return
	var player: Node3D = players[peer_id]
	if is_instance_valid(player):
		player.global_position = Vector3(data.get("x", 0), data.get("y", 0), data.get("z", 0))
		player.rotation.y = data.get("rot_y", 0)

func _add_player(id: int) -> void:
	if players.has(id):
		return

	var player := player_scene.instantiate()
	player.name = str(id)
	player.set_meta("peer_id", id)
	player.add_to_group("players")

	if current_mode == NetworkMode.LAN:
		if id == my_peer_id:
			player.set_multiplayer_authority(multiplayer.get_unique_id())
		else:
			player.set_multiplayer_authority(id)

	var spawn_index := players.size() % spawn_points.size()
	player.position = spawn_points[spawn_index]

	var players_node := get_tree().current_scene.get_node_or_null("Players")
	if players_node:
		players_node.add_child(player)
	players[id] = player

func _remove_player(id: int) -> void:
	if not players.has(id):
		return
	var player: Node = players[id]
	if is_instance_valid(player):
		player.queue_free()
	players.erase(id)

func _clear_players() -> void:
	for id in players.keys():
		_remove_player(id)
	players.clear()

func is_local_player(peer_id: int) -> bool:
	return peer_id == my_peer_id
