extends Node

signal player_speaking_changed(peer_id: int, is_speaking: bool)

const UPDATE_INTERVAL: float = 0.1  
const MAX_VOICE_DISTANCE: float = 6.0 
const MIN_VOICE_DISTANCE: float = 1.0   
const MAX_VOLUME: float = 50.0 

var _update_timer: float = 0.0
var _current_lobby: HLobby = null
var _is_active: bool = false
var _mic_muted: bool = false
var _mic_volume: float = 100.0
var _speaking_states: Dictionary = {}
var _last_rtc_update_time: float = 0.0

# Voice zones system
var _voice_zones: Array[Dictionary] = []
var _players_in_zones: Dictionary = {}  


func _ready() -> void:
	MultiplayerManager.connection_succeeded.connect(_on_connection_succeeded)
	MultiplayerManager.server_disconnected.connect(_on_server_disconnected)
	MultiplayerManager.player_disconnected.connect(_on_player_disconnected)

	if IEOS.rtc_audio_participant_updated:
		IEOS.rtc_audio_participant_updated.connect(_on_rtc_audio_participant_updated)

	print("[VoiceManager] Initialized - waiting for connection")


func _exit_tree() -> void:
	if MultiplayerManager.connection_succeeded.is_connected(_on_connection_succeeded):
		MultiplayerManager.connection_succeeded.disconnect(_on_connection_succeeded)
	if MultiplayerManager.server_disconnected.is_connected(_on_server_disconnected):
		MultiplayerManager.server_disconnected.disconnect(_on_server_disconnected)
	if MultiplayerManager.player_disconnected.is_connected(_on_player_disconnected):
		MultiplayerManager.player_disconnected.disconnect(_on_player_disconnected)
	if IEOS.rtc_audio_participant_updated and IEOS.rtc_audio_participant_updated.is_connected(_on_rtc_audio_participant_updated):
		IEOS.rtc_audio_participant_updated.disconnect(_on_rtc_audio_participant_updated)
	_cleanup()


func _process(delta: float) -> void:
	if not _is_active:
		if Engine.get_frames_drawn() % 300 == 0:  # A cada 5 segundos
			print("[VoiceManager] WARNING: Not active - voice proximity disabled")
		return

	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_update_voice_volumes()

	# Detectar se RTC updates pararam de chegar
	if _is_active and Time.get_ticks_msec() - _last_rtc_update_time > 5000:
		if Engine.get_frames_drawn() % 300 == 0:
			print("[VoiceManager] WARNING: No RTC updates for 5+ seconds")


func _on_connection_succeeded() -> void:
	print("[VoiceManager] Connection succeeded callback triggered")
	print("[VoiceManager] Current mode: ", MultiplayerManager.current_mode)
	print("[VoiceManager] EOS mode value: ", MultiplayerManager.NetworkMode.EOS)

	# Suportar EOS e LAN
	if MultiplayerManager.current_mode == MultiplayerManager.NetworkMode.NONE:
		print("[VoiceManager] Singleplayer mode - voice disabled")
		return

	# Para EOS, precisa de lobby
	if MultiplayerManager.current_mode == MultiplayerManager.NetworkMode.EOS:
		_current_lobby = MultiplayerManager.get_current_lobby()
		print("[VoiceManager] Current lobby: ", _current_lobby)

		if not _current_lobby:
			print("[VoiceManager] ERROR: No lobby in EOS mode")
			return

	# Ativar proximity voice
	_is_active = true
	print("[VoiceManager] ✓ Proximity voice chat ACTIVATED")

	# Aplicar mute state salvo
	if _mic_muted:
		set_mic_muted(true)
		print("[VoiceManager] Applied saved mute state")


func _on_server_disconnected() -> void:
	_cleanup()


func _on_player_disconnected(_peer_id: int) -> void:
	pass


func _cleanup() -> void:
	_is_active = false
	_current_lobby = null
	_update_timer = 0.0
	_speaking_states.clear()
	_voice_zones.clear()
	_players_in_zones.clear()
	print("[Voice] Proximity voice chat deactivated")


func _update_voice_volumes() -> void:
	if not _current_lobby:
		if Engine.get_frames_drawn() % 300 == 0:
			print("[VoiceManager] ERROR: No current lobby")
		return

	var local_player = _get_local_player()
	if not local_player:
		if Engine.get_frames_drawn() % 300 == 0:
			print("[VoiceManager] ERROR: Local player not found")
		return

	var local_position: Vector3 = local_player.global_position
	var local_peer_id: int = MultiplayerManager.my_peer_id

	var puid_count = MultiplayerManager.puid_to_peer_id.size()
	if puid_count == 0:
		if Engine.get_frames_drawn() % 300 == 0:
			print("[VoiceManager] WARNING: puid_to_peer_id is empty - no players to process")
		return

	var players_processed = 0
	for puid in MultiplayerManager.puid_to_peer_id:
		var peer_id = MultiplayerManager.puid_to_peer_id[puid] as int

		if peer_id == local_peer_id:
			continue

		var remote_player = _get_player_by_peer_id(peer_id)
		if not remote_player:
			continue

		var zone_settings: Dictionary = _get_zone_settings_for_players(local_peer_id, peer_id)

		# Get remote player's sound radius (affected by their actions and voice)
		var remote_sound_radius: float = _get_player_sound_radius(remote_player)

		# Use the larger of: zone max_distance or player's sound radius
		var effective_max_distance: float = max(zone_settings.max_distance, remote_sound_radius)

		var distance: float = local_position.distance_to(remote_player.global_position)
		var volume: float = _calculate_volume_with_zone(
			distance,
			effective_max_distance,
			zone_settings.min_distance,
			zone_settings.volume_multiplier
		)

		# Debug log (a cada 5 segundos para não spammar)
		if _update_timer < 0.1 and volume > 0.0:  # Primeiro update do ciclo e volume audível
			print("[VoiceManager] Player %d: dist=%.1f, radius=%.1f, vol=%.1f" % [
				peer_id, distance, remote_sound_radius, volume
			])

		_set_participant_volume(puid, volume)
		players_processed += 1

	if players_processed == 0 and Engine.get_frames_drawn() % 300 == 0:
		print("[VoiceManager] WARNING: No players processed in update loop")


func _get_local_player() -> Node3D:
	if MultiplayerManager.players.has(MultiplayerManager.my_peer_id):
		var player = MultiplayerManager.players[MultiplayerManager.my_peer_id]
		if is_instance_valid(player):
			return player

	var players_container := get_tree().current_scene.get_node_or_null("Players")
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
	var players_container := get_tree().current_scene.get_node_or_null("Players")
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
		if Engine.get_frames_drawn() % 600 == 0:
			print("[VoiceManager] Invalid player in get_sound_radius")
		return MAX_VOICE_DISTANCE

	# Tentar obter raio dinâmico do player
	if player.has_method("get_sound_radius"):
		var radius: float = player.get_sound_radius()

		# Debug periódico
		if Engine.get_frames_drawn() % 600 == 0:  # A cada 10 segundos
			print("[VoiceManager] Player sound radius: %.1f" % radius)

		# Validar valor retornado (evitar valores inválidos)
		if radius > 0.0 and radius < 1000.0:  # Sanity check
			return radius
		else:
			if Engine.get_frames_drawn() % 600 == 0:
				print("[VoiceManager] WARNING: Invalid radius value: %.1f" % radius)
	else:
		if Engine.get_frames_drawn() % 600 == 0:
			print("[VoiceManager] Player missing get_sound_radius() method")

	# Fallback: usar distância padrão
	return MAX_VOICE_DISTANCE


func _calculate_volume(distance: float) -> float:

	if distance <= MIN_VOICE_DISTANCE:
		return MAX_VOLUME

	if distance >= MAX_VOICE_DISTANCE:
		return 0.0

	# Linear interpolation
	var t := (distance - MIN_VOICE_DISTANCE) / (MAX_VOICE_DISTANCE - MIN_VOICE_DISTANCE)
	return MAX_VOLUME * (1.0 - t)


func _calculate_volume_with_zone(
	distance: float,
	max_distance: float,
	min_distance: float,
	volume_multiplier: float
) -> float:
	"""Calcula volume considerando configurações customizadas de zona"""
	if volume_multiplier <= 0.0:
		return 0.0

	if max_distance <= 0.0:
		return 0.0

	var base_volume: float

	if distance <= min_distance:
		base_volume = MAX_VOLUME
	elif distance >= max_distance:
		base_volume = 0.0
	else:
		var t := (distance - min_distance) / (max_distance - min_distance)
		base_volume = MAX_VOLUME * (1.0 - t)

	var final_volume := base_volume * volume_multiplier

	return clamp(final_volume, 0.0, 100.0)


func _set_participant_volume(puid: String, volume: float) -> void:
	if not _current_lobby:
		return

	var room_name = _current_lobby.lobby_id as String
	var local_puid = MultiplayerManager.get_local_puid()

	var volume_opts = EOS.RTCAudio.UpdateReceivingVolumeOptions.new()
	volume_opts.local_user_id = local_puid
	volume_opts.room_name = room_name
	volume_opts.participant_id = puid
	volume_opts.volume = volume

	EOS.RTCAudio.RTCAudioInterface.update_receiving_volume(volume_opts)


# ==========================================
# VOICE ZONES SYSTEM
# ==========================================

func register_voice_zone(
	area: Area3D,
	max_distance: float = MAX_VOICE_DISTANCE,
	min_distance: float = MIN_VOICE_DISTANCE,
	volume_multiplier: float = 1.0,
	mute_outside: bool = false
) -> void:
	"""
	Registra uma Area3D como zona de voz customizada.

	Parâmetros:
	- area: Area3D que define a zona
	- max_distance: Distância máxima de voz dentro da zona (padrão: 6.0)
	- min_distance: Distância mínima de voz dentro da zona (padrão: 1.0)
	- volume_multiplier: Multiplicador de volume (0.0 a 1.0, padrão: 1.0)
	- mute_outside: Se true, jogadores fora desta zona são mutados (padrão: false)

	Exemplo de uso:
	VoiceManager.register_voice_zone($SilentArea, 0.0, 0.0, 0.0, true)  # Zona de silêncio
	VoiceManager.register_voice_zone($LoudArea, 20.0, 5.0, 2.0)  # Zona com alcance ampliado
	"""
	if not area:
		push_error("[VoiceManager] Cannot register null area as voice zone")
		return

	for zone in _voice_zones:
		if zone.area == area:
			print("[VoiceManager] Voice zone already registered: ", area.name)
			return

	var zone_data := {
		"area": area,
		"max_distance": max_distance,
		"min_distance": min_distance,
		"volume_multiplier": volume_multiplier,
		"mute_outside": mute_outside
	}

	_voice_zones.append(zone_data)

	if not area.body_entered.is_connected(_on_voice_zone_body_entered):
		area.body_entered.connect(_on_voice_zone_body_entered.bind(area))
	if not area.body_exited.is_connected(_on_voice_zone_body_exited):
		area.body_exited.connect(_on_voice_zone_body_exited.bind(area))

	print("[VoiceManager] Voice zone registered: %s (max: %.1f, min: %.1f, mult: %.2f, mute_outside: %s)" % [
		area.name, max_distance, min_distance, volume_multiplier, mute_outside
	])


func unregister_voice_zone(area: Area3D) -> void:
	"""Remove uma zona de voz registrada"""
	if not area:
		return

	for i in range(_voice_zones.size() - 1, -1, -1):
		if _voice_zones[i].area == area:
			_voice_zones.remove_at(i)
			print("[VoiceManager] Voice zone unregistered: ", area.name)
			break

	if area.body_entered.is_connected(_on_voice_zone_body_entered):
		area.body_entered.disconnect(_on_voice_zone_body_entered)
	if area.body_exited.is_connected(_on_voice_zone_body_exited):
		area.body_exited.disconnect(_on_voice_zone_body_exited)

	for peer_id in _players_in_zones:
		var zones: Array = _players_in_zones[peer_id]
		if area in zones:
			zones.erase(area)


func _on_voice_zone_body_entered(body: Node3D, area: Area3D) -> void:
	"""Callback quando um jogador entra em uma zona de voz"""
	if not body.is_in_group("players"):
		return

	var peer_id: int = body.get_meta("peer_id", -1)
	if peer_id == -1:
		return

	if not _players_in_zones.has(peer_id):
		_players_in_zones[peer_id] = []

	var zones: Array = _players_in_zones[peer_id]
	if not area in zones:
		zones.append(area)
		print("[VoiceManager] Player %d entered voice zone: %s" % [peer_id, area.name])


func _on_voice_zone_body_exited(body: Node3D, area: Area3D) -> void:
	"""Callback quando um jogador sai de uma zona de voz"""
	if not body.is_in_group("players"):
		return

	var peer_id: int = body.get_meta("peer_id", -1)
	if peer_id == -1:
		return

	if _players_in_zones.has(peer_id):
		var zones: Array = _players_in_zones[peer_id]
		if area in zones:
			zones.erase(area)
			print("[VoiceManager] Player %d exited voice zone: %s" % [peer_id, area.name])


func _get_zone_settings_for_players(local_peer_id: int, remote_peer_id: int) -> Dictionary:
	"""
	Retorna as configurações de zona aplicáveis entre dois jogadores.
	Prioriza zonas com mute_outside ativado.
	"""
	var local_zones: Array = _players_in_zones.get(local_peer_id, [])
	var remote_zones: Array = _players_in_zones.get(remote_peer_id, [])

	for zone_data in _voice_zones:
		var area: Area3D = zone_data.area

		var local_in_zone: bool = area in local_zones
		var remote_in_zone: bool = area in remote_zones

		if zone_data.mute_outside:
			if local_in_zone != remote_in_zone:
				# Mutar completamente
				return {
					"max_distance": 0.0,
					"min_distance": 0.0,
					"volume_multiplier": 0.0
				}

		if local_in_zone and remote_in_zone:
			return zone_data

	return {
		"max_distance": MAX_VOICE_DISTANCE,
		"min_distance": MIN_VOICE_DISTANCE,
		"volume_multiplier": 1.0
	}


# ==========================================
# MIC CONTROL
# ==========================================


func is_mic_muted() -> bool:
	return _mic_muted


func set_mic_muted(muted: bool) -> void:
	_mic_muted = muted
	print("[VoiceManager] Mic muted state set to: %s" % muted)

	if not _current_lobby:
		print("[VoiceManager] No active lobby - mute state saved for later")
		return

	var room_name = _current_lobby.lobby_id as String
	var local_puid = MultiplayerManager.get_local_puid()

	if local_puid.is_empty():
		print("[VoiceManager] ERROR: Local PUID is empty")
		return

	var mute_opts = EOS.RTCAudio.UpdateSendingOptions.new()
	mute_opts.local_user_id = local_puid
	mute_opts.room_name = room_name
	mute_opts.audio_status = EOS.RTCAudio.AudioStatus.Disabled if muted else EOS.RTCAudio.AudioStatus.Enabled

	EOS.RTCAudio.RTCAudioInterface.update_sending(mute_opts)
	print("[VoiceManager] Mic mute applied to EOS: %s" % muted)


func set_mic_volume(volume: float) -> void:
	_mic_volume = volume
	print("[Voice] Mic volume set to: ", volume)


# ==========================================
# SPEAKING DETECTION
# ==========================================


func _on_rtc_audio_participant_updated(data: Dictionary) -> void:
	_last_rtc_update_time = Time.get_ticks_msec()

	if not _current_lobby:
		if Engine.get_frames_drawn() % 300 == 0:
			print("[VoiceManager] RTC update but no lobby")
		return

	if data.room_name != _current_lobby.lobby_id:
		if Engine.get_frames_drawn() % 300 == 0:
			print("[VoiceManager] RTC update for wrong room")
		return

	var puid: String = data.participant_id
	var is_speaking: bool = data.speaking

	if not MultiplayerManager.puid_to_peer_id.has(puid):
		if Engine.get_frames_drawn() % 300 == 0:
			print("[VoiceManager] WARNING: PUID not in dictionary: ", puid)
		return

	var peer_id: int = MultiplayerManager.puid_to_peer_id[puid]

	var previous_state: bool = _speaking_states.get(peer_id, false)
	if previous_state != is_speaking:
		_speaking_states[peer_id] = is_speaking
		print("[VoiceManager] Player %d speaking state: %s" % [peer_id, is_speaking])
		player_speaking_changed.emit(peer_id, is_speaking)


func is_player_speaking(peer_id: int) -> bool:
	return _speaking_states.get(peer_id, false)
