extends Node
## AudioManager - Manages music and sound effects for the game

# Audio streams
var _lobby_music: AudioStream = preload("res://assets/sounds/BunnyTerror.mp3")
var _game_music: AudioStream = preload("res://assets/sounds/mapTerror.mp3")
var _scream_sound: AudioStream = preload("res://assets/sounds/Scream.mp3")
var _roar_sound: AudioStream = preload("res://assets/sounds/Roar.mp3")
var _car_sound: AudioStream = preload("res://assets/sounds/CarSound.mp3")
var _game_over_sound: AudioStream = preload("res://assets/sounds/GameOverSound.mp3")
# Footstep sounds (alternados aleatoriamente)
var _footstep_sounds: Array[AudioStream] = [
	preload("res://assets/sounds/FootSteps_1.mp3"),
	preload("res://assets/sounds/FootSteps_2.mp3"),
]

# Footstep constants
const FOOTSTEP_PITCH_MIN: float = 0.9
const FOOTSTEP_PITCH_MAX: float = 1.1
const FOOTSTEP_VOLUME_DB: float = -10.0

# Ambient sounds (dinâmico - adicione novos sons aqui)
var _ambient_sounds: Array[AudioStream] = [
	preload("res://assets/sounds/Crow.mp3"),
	preload("res://assets/sounds/Bells.mp3"),
]

# Music players for crossfade
var _music_player_a: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer
var _active_player: AudioStreamPlayer
var _inactive_player: AudioStreamPlayer

# SFX player
var _sfx_player: AudioStreamPlayer

# Ambient sound system
var _ambient_player: AudioStreamPlayer
var _ambient_timer: float = 0.0
var _ambient_next_interval: float = 0.0
var _ambient_active: bool = false
const AMBIENT_MIN_INTERVAL: float = 10.0
const AMBIENT_MAX_INTERVAL: float = 30.0

# Crossfade settings
const CROSSFADE_DURATION: float = 1.5

# Volume storage (0.0 to 1.0)
var _music_volume: float = 1.0
var _sfx_volume: float = 1.0


func _ready() -> void:
	# Create music players
	_music_player_a = AudioStreamPlayer.new()
	_music_player_a.bus = "Music"
	add_child(_music_player_a)

	_music_player_b = AudioStreamPlayer.new()
	_music_player_b.bus = "Music"
	add_child(_music_player_b)

	_active_player = _music_player_a
	_inactive_player = _music_player_b

	# Create SFX player
	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = "SFX"
	add_child(_sfx_player)

	# Create ambient sound player
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = "SFX"
	add_child(_ambient_player)


func _process(delta: float) -> void:
	if _ambient_active:
		_update_ambient_sounds(delta)


# ==========================================
# MUSIC METHODS
# ==========================================

func play_lobby_music() -> void:
	_play_music(_lobby_music)


func play_game_music() -> void:
	_play_music(_game_music)


func _play_music(stream: AudioStream) -> void:
	if _active_player.stream == stream and _active_player.playing:
		return

	# Crossfade to new music
	var temp := _active_player
	_active_player = _inactive_player
	_inactive_player = temp

	_active_player.stream = stream
	_active_player.volume_db = -80.0
	_active_player.play()

	# Only create tween if we're actually going to use it
	var tween := create_tween()
	tween.set_parallel(true)

	tween.tween_property(_active_player, "volume_db", linear_to_db(_music_volume), CROSSFADE_DURATION)

	if _inactive_player.playing:
		tween.tween_property(_inactive_player, "volume_db", -80.0, CROSSFADE_DURATION)
		tween.tween_callback(_inactive_player.stop).set_delay(CROSSFADE_DURATION)


func stop_music() -> void:
	if not _active_player.playing and not _inactive_player.playing:
		return

	var tween := create_tween()
	tween.set_parallel(true)

	if _active_player.playing:
		tween.tween_property(_active_player, "volume_db", -80.0, CROSSFADE_DURATION)
		tween.tween_callback(_active_player.stop).set_delay(CROSSFADE_DURATION)

	if _inactive_player.playing:
		tween.tween_property(_inactive_player, "volume_db", -80.0, CROSSFADE_DURATION)
		tween.tween_callback(_inactive_player.stop).set_delay(CROSSFADE_DURATION)


# ==========================================
# SFX METHODS
# ==========================================

func play_scream() -> void:
	_play_sfx(_scream_sound)


func play_roar() -> void:
	_play_sfx(_roar_sound)

func play_car() -> void:
	_play_sfx(_car_sound)

func play_game_over() -> void:
	_play_sfx(_game_over_sound)


func play_footstep() -> void:
	"""Toca som de footstep aleatório com variação de pitch"""
	if _footstep_sounds.is_empty():
		return

	var random_index := randi() % _footstep_sounds.size()
	var sound: AudioStream = _footstep_sounds[random_index]

	var player := AudioStreamPlayer.new()
	player.stream = sound
	player.bus = "SFX"
	player.volume_db = FOOTSTEP_VOLUME_DB
	player.pitch_scale = randf_range(FOOTSTEP_PITCH_MIN, FOOTSTEP_PITCH_MAX)
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func _play_sfx(stream: AudioStream) -> void:
	# Create a new player for overlapping sounds
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "SFX"
	player.volume_db = linear_to_db(_sfx_volume)
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


# ==========================================
# VOLUME CONTROL METHODS
# ==========================================

func set_music_volume(volume: float) -> void:
	_music_volume = clamp(volume, 0.0, 1.0)
	var music_bus_idx := AudioServer.get_bus_index("Music")
	if music_bus_idx >= 0:
		AudioServer.set_bus_volume_db(music_bus_idx, linear_to_db(_music_volume))


func get_music_volume() -> float:
	return _music_volume


func set_sfx_volume(volume: float) -> void:
	_sfx_volume = clamp(volume, 0.0, 1.0)
	var sfx_bus_idx := AudioServer.get_bus_index("SFX")
	if sfx_bus_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_bus_idx, linear_to_db(_sfx_volume))


func get_sfx_volume() -> float:
	return _sfx_volume


# ==========================================
# AMBIENT SOUNDS METHODS
# ==========================================

func start_ambient_sounds() -> void:
	"""Inicia o sistema de sons ambientes"""
	if _ambient_sounds.is_empty():
		return

	_ambient_active = true
	_ambient_timer = 0.0
	_ambient_next_interval = randf_range(AMBIENT_MIN_INTERVAL, AMBIENT_MAX_INTERVAL)


func stop_ambient_sounds() -> void:
	"""Para o sistema de sons ambientes"""
	_ambient_active = false
	_ambient_timer = 0.0
	if _ambient_player.playing:
		_ambient_player.stop()


func _update_ambient_sounds(delta: float) -> void:
	"""Atualiza o timer e toca sons ambientes aleatoriamente"""
	_ambient_timer += delta

	if _ambient_timer >= _ambient_next_interval:
		_play_random_ambient_sound()
		_ambient_timer = 0.0
		_ambient_next_interval = randf_range(AMBIENT_MIN_INTERVAL, AMBIENT_MAX_INTERVAL)


func _play_random_ambient_sound() -> void:
	"""Toca um som ambiente aleatório"""
	if _ambient_sounds.is_empty():
		return

	# Não tocar se já estiver tocando
	if _ambient_player.playing:
		return

	var random_index := randi() % _ambient_sounds.size()
	var sound: AudioStream = _ambient_sounds[random_index]

	if sound:
		# Variação de pitch ±5% para evitar repetição
		_ambient_player.pitch_scale = randf_range(0.95, 1.05)
		_ambient_player.volume_db = linear_to_db(_sfx_volume)
		_ambient_player.stream = sound
		_ambient_player.play()


func add_ambient_sound(sound: AudioStream) -> void:
	"""Adiciona um novo som ao array de sons ambientes"""
	if sound and not _ambient_sounds.has(sound):
		_ambient_sounds.append(sound)
