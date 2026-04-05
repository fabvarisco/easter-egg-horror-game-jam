extends Node
## SpawnManager - Centralized player spawn management
## Single source of truth for player spawning to avoid duplicates and position conflicts

signal player_spawned(peer_id: int, player: Node3D)
signal player_removed(peer_id: int)

var player_scene: PackedScene = preload("res://scenes/player/player.tscn")

var _spawned_peer_ids: Dictionary = {}  # peer_id -> player node
var _next_spawn_index: int = 0

@onready var multiplayer_manager: Node = get_node("/root/MultiplayerManager")


func _ready() -> void:
	pass


func reset() -> void:
	"""Clears spawn state for scene transitions. Called before spawning in a new scene."""
	# Don't queue_free here - the scene transition handles that
	_spawned_peer_ids.clear()
	_next_spawn_index = 0


func is_player_spawned(peer_id: int) -> bool:
	"""Check if a player is already spawned to avoid duplicates."""
	return _spawned_peer_ids.has(peer_id)


func _get_deterministic_spawn_index(peer_id: int, num_spawn_points: int) -> int:
	"""Calculate spawn index based on peer's position in sorted peer list.
	This ensures all clients calculate the same spawn point for each player."""

	var sorted_peers: Array = multiplayer_manager.connected_peers.duplicate()
	sorted_peers.sort()

	var peer_position := sorted_peers.find(peer_id)
	if peer_position == -1:
		peer_position = abs(peer_id) % num_spawn_points

	return peer_position % num_spawn_points


func get_spawn_points() -> Array[Node3D]:
	"""Get player spawn points from current scene."""
	var spawn_points: Array[Node3D] = []
	var current_scene := get_tree().current_scene

	if not current_scene:
		push_error("[SpawnManager] No current scene!")
		return spawn_points

	# First try to find spawn points in chunks (game scene)
	var chunks_node := current_scene.get_node_or_null("Chunks")
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
		var root_spawns := current_scene.get_node_or_null("PlayerSpawnPoints")
		if root_spawns and root_spawns.get_child_count() > 0:
			for spawn_point in root_spawns.get_children():
				spawn_points.append(spawn_point)

	# Sort spawn points by name to ensure consistent order (SpawnPoint1, SpawnPoint2, etc.)
	if not spawn_points.is_empty():
		spawn_points.sort_custom(func(a, b): return a.name < b.name)

	return spawn_points


func spawn_player(peer_id: int) -> Node3D:
	"""Spawn a single player at a deterministic spawn point based on peer order."""
	if is_player_spawned(peer_id):
		return _spawned_peer_ids.get(peer_id)

	var spawn_points := get_spawn_points()
	if spawn_points.is_empty():
		push_error("[SpawnManager] No player spawn points found!")
		return null

	var player := player_scene.instantiate()
	player.name = str(peer_id)
	player.set_meta("peer_id", peer_id)
	player.add_to_group("players")

	var model_index: int = multiplayer_manager.get_player_model_index(peer_id)
	if model_index >= 0:
		player.set_meta("model_index", model_index)

	if multiplayer_manager.current_mode != multiplayer_manager.NetworkMode.NONE:
		var my_peer_id: int = multiplayer_manager.my_peer_id
		player.set_multiplayer_authority(peer_id if peer_id != my_peer_id else multiplayer.get_unique_id())

	var spawn_index := _get_deterministic_spawn_index(peer_id, spawn_points.size())
	var spawn_point: Node3D = spawn_points[spawn_index]


	var final_position: Vector3
	if spawn_point.is_inside_tree():
		final_position = spawn_point.global_position
	else:
		var pos := spawn_point.position
		var parent := spawn_point.get_parent()
		while parent and parent is Node3D:
			pos = parent.transform * pos
			parent = parent.get_parent()
		final_position = pos

	player.position = final_position

	var players_node := get_tree().current_scene.get_node_or_null("Players")
	if players_node:
		players_node.add_child(player)
		player.global_position = final_position
	else:
		push_error("[SpawnManager] No 'Players' node found in scene!")
		player.queue_free()
		return null

	# Track spawned player
	_spawned_peer_ids[peer_id] = player
	multiplayer_manager.players[peer_id] = player

	player_spawned.emit(peer_id, player)

	return player


func spawn_all_players() -> void:
	"""Spawn all connected players (multiplayer)."""
	var sorted_peers: Array = multiplayer_manager.connected_peers.duplicate()
	sorted_peers.sort()

	for peer_id in sorted_peers:
		spawn_player(peer_id)


func spawn_singleplayer() -> Node3D:
	"""Spawn the local player for singleplayer mode."""
	if multiplayer_manager.get_player_model_index(1) < 0:
		multiplayer_manager.assign_model_index_for_peer(1)

	var player := spawn_player(1)

	if player:
		# Singleplayer specific setup
		player.add_to_group("player")
		player.visible = true
		player.set_physics_process(true)
		player.set_process_input(true)

	return player


func remove_player(peer_id: int) -> void:
	"""Remove a player from the game."""
	if not _spawned_peer_ids.has(peer_id):
		return

	var player: Node = _spawned_peer_ids[peer_id]
	if is_instance_valid(player):
		player.queue_free()

	_spawned_peer_ids.erase(peer_id)
	multiplayer_manager.players.erase(peer_id)

	player_removed.emit(peer_id)


func clear_all_players() -> void:
	"""Remove all players and reset spawn state."""
	for peer_id in _spawned_peer_ids.keys():
		var player: Node = _spawned_peer_ids[peer_id]
		if is_instance_valid(player):
			player.queue_free()

	_spawned_peer_ids.clear()
	multiplayer_manager.players.clear()
	_next_spawn_index = 0


func get_player(peer_id: int) -> Node3D:
	"""Get a spawned player by peer_id."""
	return _spawned_peer_ids.get(peer_id)


func get_all_players() -> Dictionary:
	"""Get dictionary of all spawned players."""
	return _spawned_peer_ids.duplicate()


func get_spawned_count() -> int:
	"""Get the number of currently spawned players."""
	return _spawned_peer_ids.size()
