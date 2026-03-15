extends Node
## Multiplayer Manager - Unified interface for LAN and EOS multiplayer

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded
signal connection_failed
signal server_disconnected
signal room_created(code: String)
signal server_found(server_info: Dictionary)
signal lobby_join_failed(reason: String)
signal player_ready_changed(peer_id: int, is_ready: bool)
signal all_players_ready
signal game_starting


enum NetworkMode { NONE, LAN, EOS }


const MAX_PLAYERS = 4
const DEFAULT_PORT = 7777
const BROADCAST_PORT = 7778
const BROADCAST_INTERVAL = 1.0
const GAME_ID = "easteregghorror"


var player_scene: PackedScene = preload("res://scenes/player.tscn")
var players: Dictionary = {}
var connected_peers: Array[int] = []  # Track connected peers before game starts
var room_code: String = ""
var is_host: bool = false
var my_peer_id: int = 0
var host_name: String = "Player"
var current_mode: NetworkMode = NetworkMode.NONE

# Ready system
var _ready_states: Dictionary = {}  # peer_id -> bool


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
	print("[MultiplayerManager] Handling quit...")
	_cleanup_on_exit()
	# Give a moment for cleanup to process
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()


# ==========================================
# EOS AVAILABILITY & INIT
# ==========================================


func _check_eos_available() -> void:
	_eos_available = ClassDB.class_exists("EOSGMultiplayerPeer")

	if _eos_available:
		print("[EOS] Plugin detectado - multiplayer online disponível")
	else:
		print("[EOS] Plugin não encontrado - modo LAN apenas")


func is_eos_available() -> bool:
	return _eos_available


func _initialize_eos() -> bool:
	if _eos_initialized:
		return true

	if not _eos_available:
		return false

	print("[EOS] Inicializando plataforma...")

	# 1. Initialize EOS Platform
	var init_opts = EOS.Platform.InitializeOptions.new()
	init_opts.product_name = EOSConfig.PRODUCT_NAME
	init_opts.product_version = EOSConfig.PRODUCT_VERSION

	var init_result = EOS.Platform.PlatformInterface.initialize(init_opts)
	if init_result != EOS.Result.Success and init_result != EOS.Result.AlreadyConfigured:
		push_error("[EOS] Falha ao inicializar: " + EOS.result_str(init_result))
		return false

	print("[EOS] SDK inicializado")

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
		push_error("[EOS] Falha ao criar plataforma")
		return false

	print("[EOS] Plataforma criada. Fazendo login anônimo...")

	# 3. Setup logging
	EOS.Logging.set_log_level(EOS.Logging.LogCategory.AllCategories, EOS.Logging.LogLevel.Info)

	# 4. Login anonymously
	var login_success = await HAuth.login_anonymous_async("Player")
	if not login_success:
		push_error("[EOS] Falha no login anônimo")
		return false

	_local_product_user_id = HAuth.product_user_id
	_eos_initialized = true
	my_peer_id = abs(hash(_local_product_user_id)) % 1000000
	print("[EOS] Login OK! PUID: ", _local_product_user_id, " | peer_id: ", my_peer_id)
	return true

# ==========================================
# LAN MULTIPLAYER
# ==========================================


func host_game_lan(player_name: String = "Host") -> void:
	current_mode = NetworkMode.LAN
	host_name = player_name
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(DEFAULT_PORT, MAX_PLAYERS)

	if error != OK:
		push_error("[LAN] Falha ao criar servidor: " + str(error))
		connection_failed.emit()
		return

	multiplayer.multiplayer_peer = _peer
	is_host = true
	my_peer_id = 1
	room_code = host_name

	_start_broadcasting()
	if not connected_peers.has(my_peer_id):
		connected_peers.append(my_peer_id)
	room_created.emit(host_name)
	connection_succeeded.emit()


func join_game_lan(ip: String) -> void:
	current_mode = NetworkMode.LAN
	_stop_listening()

	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(ip, DEFAULT_PORT)

	if error != OK:
		push_error("[LAN] Falha ao conectar: " + str(error))
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
		push_error("[EOS] Plugin não disponível")
		connection_failed.emit()
		return

	current_mode = NetworkMode.EOS
	is_host = true
	host_name = room_name

	if not _eos_initialized:
		var success := await _initialize_eos()
		if not success:
			lobby_join_failed.emit("Falha na inicialização do EOS")
			connection_failed.emit()
			current_mode = NetworkMode.NONE
			return

	print("[EOS] Criando lobby...")

	# Create lobby using high-level API
	var create_opts := EOS.Lobby.CreateLobbyOptions.new()
	create_opts.bucket_id = GAME_ID
	create_opts.max_lobby_members = MAX_PLAYERS
	create_opts.enable_rtc_room = true  # Enable voice chat

	_current_lobby = await HLobbies.create_lobby_async(create_opts)
	if not _current_lobby:
		push_error("[EOS] Falha ao criar lobby")
		lobby_join_failed.emit("Falha ao criar lobby")
		connection_failed.emit()
		current_mode = NetworkMode.NONE
		return

	# Create P2P server
	_eos_peer = EOSGMultiplayerPeer.new()
	var result := _eos_peer.create_server(GAME_ID)
	if result != OK:
		push_error("[EOS] Falha ao criar servidor P2P: " + str(result))
		connection_failed.emit()
		current_mode = NetworkMode.NONE
		return

	multiplayer.multiplayer_peer = _eos_peer
	room_code = _generate_lobby_code(_current_lobby.lobby_id)
	my_peer_id = 1

	print("[EOS] Lobby criado! Código: ", room_code)
	if not connected_peers.has(my_peer_id):
		connected_peers.append(my_peer_id)

	# Register own PUID for voice chat mapping
	puid_to_peer_id[_local_product_user_id] = my_peer_id
	peer_id_to_puid[my_peer_id] = _local_product_user_id

	room_created.emit(room_code)
	connection_succeeded.emit()


func join_game_eos(code: String) -> void:
	if not _eos_available:
		lobby_join_failed.emit("EOS não disponível")
		return

	current_mode = NetworkMode.EOS
	is_host = false
	room_code = code.to_upper()

	if not _eos_initialized:
		var success := await _initialize_eos()
		if not success:
			lobby_join_failed.emit("Falha na inicialização do EOS")
			current_mode = NetworkMode.NONE
			return

	print("[EOS] Buscando lobby com código: ", room_code)

	# Search for lobbies by bucket_id
	var lobbies = await HLobbies.search_by_bucket_id_async(GAME_ID)
	if not lobbies or lobbies.size() == 0:
		lobby_join_failed.emit("Nenhum lobby encontrado")
		current_mode = NetworkMode.NONE
		return

	print("[EOS] Encontrados ", lobbies.size(), " lobbies")

	# Find lobby matching the code
	for lobby in lobbies:
		var found_code := _generate_lobby_code(lobby.lobby_id)
		if found_code == room_code:
			print("[EOS] Lobby encontrado! Entrando: ", lobby.lobby_id)

			# Join the lobby
			var joined_lobby = await HLobbies.join_by_id_async(lobby.lobby_id)
			if not joined_lobby:
				lobby_join_failed.emit("Falha ao entrar no lobby")
				current_mode = NetworkMode.NONE
				return

			# Create P2P client connection to lobby owner
			_eos_peer = EOSGMultiplayerPeer.new()
			var result := _eos_peer.create_client(GAME_ID, lobby.owner_product_user_id)
			if result != OK:
				push_error("[EOS] Falha ao criar cliente P2P: " + str(result))
				lobby_join_failed.emit("Falha na conexão P2P")
				current_mode = NetworkMode.NONE
				return

			multiplayer.multiplayer_peer = _eos_peer
			_current_lobby = joined_lobby
			print("[EOS] Conectado ao lobby!")
			return

	lobby_join_failed.emit("Lobby não encontrado: " + room_code)
	current_mode = NetworkMode.NONE


func _process(_delta: float) -> void:
	if current_mode != NetworkMode.LAN:
		return

	if _is_broadcasting:
		_broadcast_timer += _delta
		if _broadcast_timer >= BROADCAST_INTERVAL:
			_broadcast_timer = 0.0
			_send_broadcast()

	if _is_listening and _listen_socket:
		while _listen_socket.get_available_packet_count() > 0:
			var packet := _listen_socket.get_packet()
			var sender_ip := _listen_socket.get_packet_ip()
			_handle_broadcast(packet, sender_ip)

	var now := Time.get_ticks_msec()
	var to_remove: Array[String] = []
	for ip in _found_servers:
		if now - _found_servers[ip].time > 3000:
			to_remove.append(ip)
	for ip in to_remove:
		_found_servers.erase(ip)


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
	match current_mode:
		NetworkMode.LAN:
			_leave_lan()
		NetworkMode.EOS:
			await _leave_eos()

	current_mode = NetworkMode.NONE
	_clear_players()
	connected_peers.clear()
	puid_to_peer_id.clear()
	peer_id_to_puid.clear()
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

		# Give a brief moment for the cleanup to start
		await get_tree().create_timer(0.1).timeout
	else:
		_current_lobby = null


func _cleanup_on_exit() -> void:
	# Synchronous cleanup when game is closing
	print("[MultiplayerManager] Cleanup on exit...")
	_stop_broadcasting()
	_stop_listening()

	# Clear multiplayer peer first to stop network callbacks
	multiplayer.multiplayer_peer = null

	if _peer:
		_peer.close()
		_peer = null

	if _eos_peer:
		_eos_peer.close()
		_eos_peer = null

	_current_lobby = null
	players.clear()
	connected_peers.clear()
	puid_to_peer_id.clear()
	peer_id_to_puid.clear()
	print("[MultiplayerManager] Cleanup complete")


# ==========================================
# LAN Helpers
# ==========================================


func _on_peer_connected(id: int) -> void:
	if _is_quitting or current_mode == NetworkMode.NONE:
		return
	var mode_str = "LAN" if current_mode == NetworkMode.LAN else "EOS"
	print("[%s] Peer conectado: %d" % [mode_str, id])
	if not connected_peers.has(id):
		connected_peers.append(id)

	# Host sends existing data to new peer
	if is_host:
		# Send existing ready states
		for peer_id in _ready_states:
			_sync_ready_state.rpc_id(id, peer_id, _ready_states[peer_id])

		# Send list of all connected peers so new client knows about everyone
		_sync_peer_list.rpc_id(id, connected_peers)

	player_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	if _is_quitting or current_mode == NetworkMode.NONE:
		return
	var mode_str = "LAN" if current_mode == NetworkMode.LAN else "EOS"
	print("[%s] Peer desconectado: %d" % [mode_str, id])
	connected_peers.erase(id)
	_remove_player(id)
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	if _is_quitting or current_mode == NetworkMode.NONE:
		return
	var mode_str = "LAN" if current_mode == NetworkMode.LAN else "EOS"
	print("[%s] Conectado ao servidor!" % mode_str)
	my_peer_id = multiplayer.get_unique_id()
	if not connected_peers.has(my_peer_id):
		connected_peers.append(my_peer_id)

	# Register PUID mapping for voice chat (EOS only)
	if current_mode == NetworkMode.EOS and _local_product_user_id != "":
		_register_puid.rpc(_local_product_user_id, my_peer_id)

	connection_succeeded.emit()


func _on_connection_failed() -> void:
	if _is_quitting or current_mode == NetworkMode.NONE:
		return
	var mode_str = "LAN" if current_mode == NetworkMode.LAN else "EOS"
	print("[%s] Conexão falhou!" % mode_str)
	connection_failed.emit()


func _on_server_disconnected() -> void:
	if _is_quitting:
		return
	var mode_str = "LAN" if current_mode == NetworkMode.LAN else "EOS"
	print("[%s] Servidor desconectou!" % mode_str)
	_clear_players()
	connected_peers.clear()
	current_mode = NetworkMode.NONE
	room_code = ""
	is_host = false
	my_peer_id = 0
	multiplayer.multiplayer_peer = null
	server_disconnected.emit()


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
		"game": GAME_ID,
		"name": host_name,
		"players": players.size(),
		"max": MAX_PLAYERS
	}
	_broadcast_socket.put_packet(JSON.stringify(data).to_utf8_buffer())


func _start_listening() -> void:
	_listen_socket = PacketPeerUDP.new()
	var error := _listen_socket.bind(BROADCAST_PORT)
	if error != OK:
		push_error("[LAN] Falha ao bind socket: " + str(error))
		return
	_is_listening = true


func _stop_listening() -> void:
	_is_listening = false
	if _listen_socket:
		_listen_socket.close()
		_listen_socket = null


func _handle_broadcast(packet: PackedByteArray, sender_ip: String) -> void:
	var data: Variant = JSON.parse_string(packet.get_string_from_utf8())
	if data == null or not data is Dictionary:
		return
	if data.get("game") != GAME_ID:
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
			# EOS uses same RPC system via EOSGMultiplayerPeer
			_send_lan_data(data, target)


func _send_lan_data(data: Dictionary, target: int = 0) -> void:
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
				_spawn_player(from_peer)


func _sync_player_position(peer_id: int, data: Dictionary) -> void:
	if not players.has(peer_id):
		return
	var player: Node3D = players[peer_id]
	if is_instance_valid(player):
		player.global_position = Vector3(data.get("x", 0.0), data.get("y", 0.0), data.get("z", 0.0))
		player.rotation.y = data.get("rot_y", 0.0)


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


func spawn_all_players() -> void:
	for peer_id in connected_peers:
		_spawn_player(peer_id)


func _get_player_spawn_points() -> Array[Node3D]:
	var spawn_points: Array[Node3D] = []

	# First try to find spawn points in chunks (game scene)
	var chunks_node := get_tree().current_scene.get_node_or_null("Chunks")
	if chunks_node:
		for chunk in chunks_node.get_children():
			if "start" in chunk.name.to_lower():
				var player_spawns = chunk.get_node_or_null("PlayerSpawnPoints")
				if player_spawns and player_spawns.get_child_count() > 0:
					for spawn_point in player_spawns.get_children():
						spawn_points.append(spawn_point)
					break

	# Fallback: check for PlayerSpawnPoints directly in scene root (lobby)
	if spawn_points.is_empty():
		var root_spawns := get_tree().current_scene.get_node_or_null("PlayerSpawnPoints")
		if root_spawns and root_spawns.get_child_count() > 0:
			for spawn_point in root_spawns.get_children():
				spawn_points.append(spawn_point)

	return spawn_points


func _spawn_player(id: int) -> void:
	if players.has(id):
		return

	var spawn_points := _get_player_spawn_points()
	if spawn_points.is_empty():
		push_error("No player spawn points found!")
		return

	var player := player_scene.instantiate()
	player.name = str(id)
	player.set_meta("peer_id", id)
	player.add_to_group("players")

	if current_mode == NetworkMode.LAN or current_mode == NetworkMode.EOS:
		player.set_multiplayer_authority(id if id != my_peer_id else multiplayer.get_unique_id())

	# Add to tree first, then set position
	var players_node := get_tree().current_scene.get_node_or_null("Players")
	if players_node:
		players_node.add_child(player)

	var spawn_index := players.size() % spawn_points.size()
	var spawn_point: Node3D = spawn_points[spawn_index]

	# Calculate global position from spawn point's transform
	if spawn_point.is_inside_tree():
		player.global_position = spawn_point.global_position
	else:
		# Fallback: use local position relative to parent chain
		var pos := spawn_point.position
		var parent := spawn_point.get_parent()
		while parent and parent is Node3D:
			pos = parent.transform * pos
			parent = parent.get_parent()
		player.global_position = pos

	players[id] = player


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
	print("[Multiplayer] Synced peer list: ", connected_peers)


# ==========================================
# PUID REGISTRATION FOR VOICE CHAT
# ==========================================


@rpc("any_peer", "call_local", "reliable")
func _register_puid(puid: String, peer_id: int) -> void:
	puid_to_peer_id[puid] = peer_id
	peer_id_to_puid[peer_id] = puid
	print("[Voice] Registered PUID mapping: %s -> peer %d" % [puid, peer_id])


func get_current_lobby() -> HLobby:
	return _current_lobby


func get_local_puid() -> String:
	return _local_product_user_id
