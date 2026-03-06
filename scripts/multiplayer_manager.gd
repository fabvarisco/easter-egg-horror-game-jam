extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded
signal connection_failed
signal room_created(code: String)

const MAX_PLAYERS = 4
const RELAY_URL = "wss://your-relay-server.com"  # Configure your relay server URL

var player_scene: PackedScene = preload("res://scenes/player.tscn")
var players: Dictionary = {}
var room_code: String = ""
var is_host: bool = false
var my_peer_id: int = 0
var next_peer_id: int = 2

var _socket: WebSocketPeer
var _connected_to_relay: bool = false

@onready var spawn_points: Array[Vector3] = [
	Vector3(0, 1, 0),
	Vector3(2, 1, 0),
	Vector3(-2, 1, 0),
	Vector3(0, 1, 2),
]

func _ready() -> void:
	_socket = WebSocketPeer.new()

func _process(_delta: float) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		return

	_socket.poll()

	match _socket.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _connected_to_relay:
				_connected_to_relay = true
				_on_relay_connected()
			while _socket.get_available_packet_count() > 0:
				var packet := _socket.get_packet()
				_handle_relay_message(packet.get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			_connected_to_relay = false

func host_game() -> void:
	room_code = _generate_room_code()
	is_host = true
	my_peer_id = 1

	var error := _socket.connect_to_url(RELAY_URL)
	if error != OK:
		push_error("Failed to connect to relay: " + str(error))
		connection_failed.emit()

func join_game(code: String) -> void:
	room_code = code.to_upper()
	is_host = false
	my_peer_id = 0  # Will be assigned by host

	var error := _socket.connect_to_url(RELAY_URL)
	if error != OK:
		push_error("Failed to connect to relay: " + str(error))
		connection_failed.emit()

func leave_game() -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_send_relay({"type": "leave", "room": room_code})
		_socket.close()
	_clear_players()
	room_code = ""
	is_host = false
	_connected_to_relay = false

func _on_relay_connected() -> void:
	if is_host:
		_send_relay({"type": "create", "room": room_code})
		_add_player(my_peer_id)
		room_created.emit(room_code)
		connection_succeeded.emit()
	else:
		_send_relay({"type": "join", "room": room_code})

func _handle_relay_message(message: String) -> void:
	var data: Variant = JSON.parse_string(message)
	if data == null:
		return

	var msg: Dictionary = data as Dictionary
	var msg_type: String = msg.get("type", "")

	match msg_type:
		"joined":
			# We successfully joined a room
			my_peer_id = msg.get("peer_id", 2)
			_add_player(my_peer_id)
			connection_succeeded.emit()
		"peer_joined":
			# A new peer joined our room (we are host)
			var peer_id: int = msg.get("peer_id", 0)
			_add_player(peer_id)
			player_connected.emit(peer_id)
			# Send current state to new player
			_send_game_state_to(peer_id)
		"peer_left":
			var peer_id: int = msg.get("peer_id", 0)
			_remove_player(peer_id)
			player_disconnected.emit(peer_id)
		"game":
			# Game data from another peer
			_handle_game_data(msg.get("from", 0), msg.get("data", {}))
		"error":
			push_error("Relay error: " + msg.get("message", "Unknown"))
			connection_failed.emit()
		"assign_peer":
			# Host assigns peer ID to joiner
			if is_host:
				var new_peer_id := next_peer_id
				next_peer_id += 1
				_send_relay({
					"type": "assign",
					"to": msg.get("from", 0),
					"peer_id": new_peer_id
				})

func _send_relay(data: Dictionary) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(data))

func send_game_data(data: Dictionary, target: int = 0) -> void:
	_send_relay({
		"type": "game",
		"room": room_code,
		"target": target,  # 0 = broadcast
		"data": data
	})

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

func _send_game_state_to(peer_id: int) -> void:
	# Send all current players to the new peer
	for id in players.keys():
		var player: Node3D = players[id]
		if is_instance_valid(player):
			send_game_data({
				"action": "spawn_player",
				"peer_id": id,
				"x": player.global_position.x,
				"y": player.global_position.y,
				"z": player.global_position.z,
				"rot_y": player.rotation.y
			}, peer_id)

func _generate_room_code() -> String:
	var chars := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # Removed similar chars (0,O,1,I)
	var code := ""
	for i in range(6):
		code += chars[randi() % chars.length()]
	return code

func _add_player(id: int) -> void:
	if players.has(id):
		return
	var player := player_scene.instantiate()
	player.name = str(id)
	player.set_meta("peer_id", id)

	# Set authority - only local player controls their character
	if id == my_peer_id:
		player.set_multiplayer_authority(1)  # Local authority
	else:
		player.set_multiplayer_authority(0)  # Remote, no local authority

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
