extends Node
## Voice Manager - Proximity-based voice chat volume control using EOS RTC

signal player_speaking_changed(peer_id: int, is_speaking: bool)

const UPDATE_INTERVAL: float = 0.1  # Update volume every 100ms
const MAX_VOICE_DISTANCE: float = 18.0  # Mudo a partir de 18m
const MIN_VOICE_DISTANCE: float = 3.0   # Volume máximo até 3m
const MAX_VOLUME: float = 50.0  # EOS uses 0-100, 50 is normal

var _update_timer: float = 0.0
var _current_lobby: HLobby = null
var _is_active: bool = false
var _mic_muted: bool = false
var _mic_volume: float = 100.0
var _speaking_states: Dictionary = {}  # peer_id -> bool
var _last_rtc_update_time: int = 0
var _player_volume_overrides: Dictionary = {}  # peer_id -> float (0.0 to 2.0, 1.0 is normal)


func _ready() -> void:
	# Connect to multiplayer events
	MultiplayerManager.connection_succeeded.connect(_on_connection_succeeded)
	MultiplayerManager.server_disconnected.connect(_on_server_disconnected)
	MultiplayerManager.player_disconnected.connect(_on_player_disconnected)

	# Connect to RTC audio events for speaking detection
	if IEOS.rtc_audio_participant_updated:
		IEOS.rtc_audio_participant_updated.connect(_on_rtc_audio_participant_updated)


func _check_if_already_connected() -> void:
	"""Verifica se já há uma conexão ativa e ativa voice chat se necessário"""
	if MultiplayerManager.current_mode != MultiplayerManager.NetworkMode.NONE and not _is_active:
		_on_connection_succeeded()


func _exit_tree() -> void:
	# Stop processing immediately
	set_process(false)
	_is_active = false

	# Disconnect MultiplayerManager signals safely
	if is_instance_valid(MultiplayerManager):
		if MultiplayerManager.connection_succeeded.is_connected(_on_connection_succeeded):
			MultiplayerManager.connection_succeeded.disconnect(_on_connection_succeeded)
		if MultiplayerManager.server_disconnected.is_connected(_on_server_disconnected):
			MultiplayerManager.server_disconnected.disconnect(_on_server_disconnected)
		if MultiplayerManager.player_disconnected.is_connected(_on_player_disconnected):
			MultiplayerManager.player_disconnected.disconnect(_on_player_disconnected)

	# Disconnect RTC signals safely - wrap in try to avoid crashes
	if ClassDB.class_exists("IEOS"):
		var ieos = get_node_or_null("/root/IEOS")
		if is_instance_valid(ieos) and ieos.has_signal("rtc_audio_participant_updated"):
			if ieos.rtc_audio_participant_updated.is_connected(_on_rtc_audio_participant_updated):
				ieos.rtc_audio_participant_updated.disconnect(_on_rtc_audio_participant_updated)

	_current_lobby = null
	_speaking_states.clear()


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
		print("[VoiceManager] Not activating - not in EOS mode")
		return

	_current_lobby = MultiplayerManager.get_current_lobby()
	if _current_lobby:
		print("[VoiceManager] Connection succeeded - activating voice chat")
		print("[VoiceManager] RTC Room: ", _current_lobby.rtc_room_name)
		print("[VoiceManager] RTC Room Connected: ", _current_lobby.rtc_room_connected)
		_is_active = true

		# Wait for RTC room to be connected before applying mic settings
		if _current_lobby.rtc_room_connected:
			print("[VoiceManager] RTC already connected, applying mic settings now")
			_apply_mic_settings()
		else:
			print("[VoiceManager] Waiting for RTC connection...")
			_wait_for_rtc_connection()
	else:
		print("[VoiceManager] ERROR: No lobby found after connection")


func _wait_for_rtc_connection() -> void:
	"""Espera até a sala RTC estar conectada antes de aplicar configurações do microfone"""
	var max_attempts = 50  # 5 segundos no máximo (50 * 0.1s)
	var attempts = 0

	while attempts < max_attempts:
		if _current_lobby and _current_lobby.rtc_room_connected:
			print("[VoiceManager] RTC connected after ", attempts * 0.1, " seconds")
			_apply_mic_settings()
			return

		await get_tree().create_timer(0.1).timeout
		attempts += 1

	push_error("[VoiceManager] RTC connection timeout after 5 seconds!")


func _on_server_disconnected() -> void:
	_cleanup()


func _on_player_disconnected(peer_id: int) -> void:
	# Remove volume override for disconnected player
	_player_volume_overrides.erase(peer_id)
	_speaking_states.erase(peer_id)


func _cleanup() -> void:
	_is_active = false
	_current_lobby = null
	_update_timer = 0.0
	_speaking_states.clear()
	_player_volume_overrides.clear()


func _update_voice_volumes() -> void:
	if not _current_lobby:
		return

	# Don't block voice updates just because scene isn't ready
	# The _get_local_player() function will handle null scenes safely
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
		var volume: float = _calculate_volume(distance, peer_id)

		_set_participant_volume(puid, volume)


func _get_local_player() -> Node3D:
	# First try the dictionary
	if MultiplayerManager.players.has(MultiplayerManager.my_peer_id):
		var player = MultiplayerManager.players[MultiplayerManager.my_peer_id]
		if is_instance_valid(player):
			return player

	# Fallback: find player in tree by peer_id
	# Check if tree and current_scene are valid first
	if not is_inside_tree():
		return null

	var current_scene := get_tree().current_scene
	if not current_scene or not is_instance_valid(current_scene):
		return null

	var players_container := current_scene.get_node_or_null("Players")
	if players_container:
		var player := players_container.get_node_or_null(str(MultiplayerManager.my_peer_id))
		if player and is_instance_valid(player):
			return player

	return null


func _get_player_by_peer_id(peer_id: int) -> Node3D:
	# First try the dictionary
	if MultiplayerManager.players.has(peer_id):
		var player = MultiplayerManager.players[peer_id]
		if is_instance_valid(player):
			return player

	# Fallback: find player in tree by peer_id
	# Check if tree and current_scene are valid first
	if not is_inside_tree():
		return null

	var current_scene := get_tree().current_scene
	if not current_scene or not is_instance_valid(current_scene):
		return null

	var players_container := current_scene.get_node_or_null("Players")
	if players_container:
		var player := players_container.get_node_or_null(str(peer_id))
		if player and is_instance_valid(player):
			return player

	return null


func _get_player_sound_radius(player: Node3D) -> float:
	"""
	Obtém o raio de som atual do jogador.
	Se o jogador tiver o método get_sound_radius(), usa esse valor dinâmico.
	Caso contrário, retorna o padrão MAX_VOICE_DISTANCE.
	"""
	if not is_instance_valid(player):
		return MAX_VOICE_DISTANCE

	if player.has_method("get_sound_radius"):
		var radius: float = player.get_sound_radius()
		if radius > 0.0 and radius < 1000.0:  # Sanity check
			return radius

	# Fallback: usar distância padrão
	return MAX_VOICE_DISTANCE


func _calculate_volume(distance: float, peer_id: int = -1) -> float:
	# At MIN_VOICE_DISTANCE or closer: full volume (MAX_VOLUME)
	# At MAX_VOICE_DISTANCE or farther: muted (0)
	# Linear falloff between

	var base_volume: float = 0.0

	if distance <= MIN_VOICE_DISTANCE:
		base_volume = MAX_VOLUME
	elif distance >= MAX_VOICE_DISTANCE:
		base_volume = 0.0
	else:
		# Linear interpolation
		var t := (distance - MIN_VOICE_DISTANCE) / (MAX_VOICE_DISTANCE - MIN_VOICE_DISTANCE)
		base_volume = MAX_VOLUME * (1.0 - t)

	# Apply player volume override (1.0 = normal, 0.0 = mute, 2.0 = 2x)
	if peer_id != -1 and _player_volume_overrides.has(peer_id):
		var multiplier: float = _player_volume_overrides[peer_id]
		base_volume *= multiplier

	return clamp(base_volume, 0.0, 100.0)


func _set_participant_volume(puid: String, volume: float) -> void:
	if not _current_lobby:
		return

	var room_name: String = _current_lobby.rtc_room_name
	if room_name.is_empty():
		return

	var local_puid = MultiplayerManager.get_local_puid()

	var volume_opts = EOS.RTCAudio.UpdateReceivingVolumeOptions.new()
	volume_opts.local_user_id = local_puid
	volume_opts.room_name = room_name
	volume_opts.participant_id = puid
	volume_opts.volume = volume

	# Debug log (can be removed later)
	var peer_id = MultiplayerManager.puid_to_peer_id.get(puid, -1)
	if Engine.get_frames_drawn() % 60 == 0:  # Log every 60 frames to avoid spam
		print("[VoiceManager] Setting volume for peer ", peer_id, " (", puid.substr(0, 8), "...) to ", volume)

	EOS.RTCAudio.RTCAudioInterface.update_receiving_volume(volume_opts)


# ==========================================
# MIC CONTROL
# ==========================================


func _apply_mic_settings() -> void:
	"""Apply saved mic settings to EOS RTC after connection is established"""
	if not _current_lobby:
		print("[VoiceManager] Cannot apply mic settings - no lobby")
		return

	var room_name: String = _current_lobby.rtc_room_name
	if room_name.is_empty():
		print("[VoiceManager] Cannot apply mic settings - no room name")
		return

	# CRITICAL CHECK: Verify RTC room is connected
	if not _current_lobby.rtc_room_connected:
		push_error("[VoiceManager] ERROR: Attempting to apply mic settings but RTC room is NOT connected!")
		return

	print("[VoiceManager] ========== APPLYING MIC SETTINGS ==========")
	print("[VoiceManager] Room: ", room_name)
	print("[VoiceManager] Muted: ", _mic_muted)
	print("[VoiceManager] Volume: ", _mic_volume)
	print("[VoiceManager] RTC Connected: ", _current_lobby.rtc_room_connected)
	print("[VoiceManager] Local PUID: ", MultiplayerManager.get_local_puid())

	var mute_opts = EOS.RTCAudio.UpdateSendingOptions.new()
	mute_opts.room_name = room_name
	mute_opts.audio_status = EOS.RTCAudio.AudioStatus.Disabled if _mic_muted else EOS.RTCAudio.AudioStatus.Enabled

	print("[VoiceManager] Calling update_sending...")
	EOS.RTCAudio.RTCAudioInterface.update_sending(mute_opts)
	var ret = await IEOS.rtc_audio_interface_update_sending_callback

	print("[VoiceManager] update_sending result: ", EOS.result_str(ret))

	if not EOS.is_success(ret):
		push_error("[VoiceManager] FAILED to apply mic settings: %s" % EOS.result_str(ret))
		print("[VoiceManager] This means the EOS SDK rejected the microphone configuration!")
		return

	print("[VoiceManager] Mic settings applied successfully - audio transmission should be active")
	print("[VoiceManager] ===========================================")
	_apply_mic_volume()


func _apply_mic_volume() -> void:
	if not _current_lobby:
		return

	var room_name: String = _current_lobby.rtc_room_name
	if room_name.is_empty():
		return

	var volume_opts = EOS.RTCAudio.UpdateSendingVolumeOptions.new()
	volume_opts.room_name = room_name
	volume_opts.volume = _mic_volume

	EOS.RTCAudio.RTCAudioInterface.update_sending_volume(volume_opts)


func is_mic_muted() -> bool:
	return _mic_muted


func set_mic_muted(muted: bool) -> void:
	_mic_muted = muted

	if not _current_lobby:
		return

	var room_name: String = _current_lobby.rtc_room_name
	if room_name.is_empty():
		return

	var mute_opts = EOS.RTCAudio.UpdateSendingOptions.new()
	mute_opts.room_name = room_name
	mute_opts.audio_status = EOS.RTCAudio.AudioStatus.Disabled if muted else EOS.RTCAudio.AudioStatus.Enabled

	EOS.RTCAudio.RTCAudioInterface.update_sending(mute_opts)
	var ret = await IEOS.rtc_audio_interface_update_sending_callback

	if not EOS.is_success(ret):
		push_error("[VoiceManager] Failed to set mic muted: %s" % EOS.result_str(ret))


func set_mic_volume(volume: float) -> void:
	_mic_volume = volume
	_apply_mic_volume()


# ==========================================
# PLAYER VOLUME CONTROL
# ==========================================


func set_player_volume(peer_id: int, multiplier: float) -> void:
	"""
	Ajusta o volume de um jogador específico.
	multiplier: 0.0 = mudo, 1.0 = normal, 2.0 = 2x volume
	"""
	multiplier = clamp(multiplier, 0.0, 2.0)
	_player_volume_overrides[peer_id] = multiplier
	print("[VoiceManager] Set volume for peer ", peer_id, " to ", multiplier)


func get_player_volume(peer_id: int) -> float:
	"""Retorna o multiplicador de volume atual de um jogador (1.0 = normal)"""
	return _player_volume_overrides.get(peer_id, 1.0)


func reset_player_volume(peer_id: int) -> void:
	"""Reseta o volume de um jogador para o normal"""
	_player_volume_overrides.erase(peer_id)


func reset_all_player_volumes() -> void:
	"""Reseta o volume de todos os jogadores para o normal"""
	_player_volume_overrides.clear()


func get_all_players_with_custom_volume() -> Dictionary:
	"""Retorna um dicionário de peer_id -> multiplier para todos os jogadores com volume customizado"""
	return _player_volume_overrides.duplicate()


# ==========================================
# SPEAKING DETECTION
# ==========================================


func _on_rtc_audio_participant_updated(data: Dictionary) -> void:
	_last_rtc_update_time = Time.get_ticks_msec()

	if not _current_lobby:
		return

	# Verify this is for our room
	if data.room_name != _current_lobby.rtc_room_name:
		return

	var puid: String = data.participant_id
	var is_speaking: bool = data.speaking
	var audio_status = data.get("audio_status", -1)

	# Convert PUID to peer_id
	if not MultiplayerManager.puid_to_peer_id.has(puid):
		# DEBUG: Se não encontrar o PUID, pode ser um problema
		print("[VoiceManager] WARNING: RTC update for unknown PUID: ", puid.substr(0, 8), "...")
		return

	var peer_id: int = MultiplayerManager.puid_to_peer_id[puid]
	var is_local: bool = (peer_id == MultiplayerManager.my_peer_id)

	# DEBUG: Log TODOS os updates, especialmente do jogador local
	if is_local or is_speaking:
		print("[VoiceManager] RTC Audio Update - Peer: ", peer_id, " (", "LOCAL" if is_local else "REMOTE", ") Speaking: ", is_speaking, " Audio Status: ", audio_status)

	# Check if state changed
	var previous_state: bool = _speaking_states.get(peer_id, false)
	if previous_state != is_speaking:
		_speaking_states[peer_id] = is_speaking
		print("[VoiceManager] Speaking state CHANGED for peer ", peer_id, " (", "LOCAL" if is_local else "REMOTE", "): ", is_speaking)
		player_speaking_changed.emit(peer_id, is_speaking)


func is_player_speaking(peer_id: int) -> bool:
	return _speaking_states.get(peer_id, false)
