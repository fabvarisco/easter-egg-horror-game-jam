extends Node
## AudioManager - Manages music and sound effects for the game

# Audio streams
var _lobby_music: AudioStream = preload("res://assets/sounds/BunnyTerror.mp3")
var _game_music: AudioStream = preload("res://assets/sounds/mapTerror.mp3")
var _scream_sound: AudioStream = preload("res://assets/sounds/Scream.mp3")
var _roar_sound: AudioStream = preload("res://assets/sounds/Roar.mp3")
var _car_sound: AudioStream = preload("res://assets/sounds/CarSound.mp3")
var _game_over_sound: AudioStream = preload("res://assets/sounds/GameOverSound.mp3")

# Music players for crossfade
var _music_player_a: AudioStreamPlayer
var _music_player_b: AudioStreamPlayer
var _active_player: AudioStreamPlayer
var _inactive_player: AudioStreamPlayer

# SFX player
var _sfx_player: AudioStreamPlayer

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

	var tween := create_tween()
	tween.set_parallel(true)

	# Fade in new music
	tween.tween_property(_active_player, "volume_db", linear_to_db(_music_volume), CROSSFADE_DURATION)

	# Fade out old music
	if _inactive_player.playing:
		tween.tween_property(_inactive_player, "volume_db", -80.0, CROSSFADE_DURATION)
		tween.tween_callback(_inactive_player.stop).set_delay(CROSSFADE_DURATION)


func stop_music() -> void:
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
