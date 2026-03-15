extends Node
## Voice Manager - Proximity-based voice chat volume control using EOS RTC

const UPDATE_INTERVAL: float = 0.1  # Update volume every 100ms
const MAX_VOICE_DISTANCE: float = 20.0  # Volume = 0 at this distance
const MIN_VOICE_DISTANCE: float = 2.0   # Volume = 50 (normal) at this distance
const MAX_VOLUME: float = 50.0  # EOS uses 0-100, 50 is normal

var _update_timer: float = 0.0
var _current_lobby: HLobby = null
var _is_active: bool = false


func _ready() -> void:
	# Connect to multiplayer events
	MultiplayerManager.connection_succeeded.connect(_on_connection_succeeded)
	MultiplayerManager.server_disconnected.connect(_on_server_disconnected)
	MultiplayerManager.player_disconnected.connect(_on_player_disconnected)


func _process(delta: float) -> void:
	if not _is_active:
		return

	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_update_voice_volumes()


func _on_connection_succeeded() -> void:
	# Only activate for EOS mode
	if MultiplayerManager.current_mode != MultiplayerManager.NetworkMode.EOS:
		return

	_current_lobby = MultiplayerManager.get_current_lobby()
	if _current_lobby:
		_is_active = true
		print("[Voice] Proximity voice chat activated")


func _on_server_disconnected() -> void:
	_cleanup()


func _on_player_disconnected(_peer_id: int) -> void:
	# Volume will be updated on next tick, no special handling needed
	pass


func _cleanup() -> void:
	_is_active = false
	_current_lobby = null
	_update_timer = 0.0
	print("[Voice] Proximity voice chat deactivated")


func _update_voice_volumes() -> void:
	if not _current_lobby:
		return

	var local_player = _get_local_player()
	if not local_player:
		return

	var local_position: Vector3 = local_player.global_position

	# Update volume for each remote player
	for puid in MultiplayerManager.puid_to_peer_id:
		var peer_id = MultiplayerManager.puid_to_peer_id[puid] as int

		# Skip local player
		if peer_id == MultiplayerManager.my_peer_id:
			continue

		var remote_player = _get_player_by_peer_id(peer_id)
		if not remote_player:
			continue

		var distance: float = local_position.distance_to(remote_player.global_position)
		var volume: float = _calculate_volume(distance)

		_set_participant_volume(puid, volume)


func _get_local_player() -> Node3D:
	if not MultiplayerManager.players.has(MultiplayerManager.my_peer_id):
		return null
	return MultiplayerManager.players[MultiplayerManager.my_peer_id]


func _get_player_by_peer_id(peer_id: int) -> Node3D:
	if not MultiplayerManager.players.has(peer_id):
		return null
	return MultiplayerManager.players[peer_id]


func _calculate_volume(distance: float) -> float:
	# At MIN_VOICE_DISTANCE or closer: full volume (MAX_VOLUME)
	# At MAX_VOICE_DISTANCE or farther: muted (0)
	# Linear falloff between

	if distance <= MIN_VOICE_DISTANCE:
		return MAX_VOLUME

	if distance >= MAX_VOICE_DISTANCE:
		return 0.0

	# Linear interpolation
	var t := (distance - MIN_VOICE_DISTANCE) / (MAX_VOICE_DISTANCE - MIN_VOICE_DISTANCE)
	return MAX_VOLUME * (1.0 - t)


func _set_participant_volume(puid: String, volume: float) -> void:
	if not _current_lobby:
		return

	var room_name = _current_lobby.lobby_id as String

	var volume_opts = EOS.RTCAudio.UpdateReceivingVolumeOptions.new()
	volume_opts.local_user_id = MultiplayerManager.get_local_puid()
	volume_opts.room_name = room_name
	volume_opts.participant_id = puid
	volume_opts.volume = volume

	EOS.RTCAudio.RTCAudioInterface.update_receiving_volume(volume_opts)
