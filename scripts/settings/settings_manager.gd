extends Node
## SettingsManager - Manages game settings and persistence

# Settings file path
const SETTINGS_FILE_PATH: String = "user://settings.json"

# Default settings
const DEFAULT_SETTINGS: Dictionary = {
	"display": {
		"fullscreen": false,
		"borderless": false,
		"resolution": Vector2i(1920, 1080),
		"vsync": true
	},
	"audio": {
		"master_volume": 1.0,
		"music_volume": 1.0,
		"sfx_volume": 1.0,
		"mic_volume": 100.0,
		"mic_muted": false,
		"audio_output_device": "",
		"mic_input_device": ""
	}
}

# Available resolutions (16:9 aspect ratio)
const AVAILABLE_RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),   # HD
	Vector2i(1600, 900),   # HD+
	Vector2i(1920, 1080),  # Full HD
	Vector2i(2560, 1440),  # QHD
	Vector2i(3840, 2160),  # 4K
]

# Current settings
var current_settings: Dictionary = {}


func _ready() -> void:
	load_settings()
	apply_all_settings()


## Loads settings from JSON file
func load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_FILE_PATH):
		print("[SettingsManager] No settings file found, using defaults")
		current_settings = DEFAULT_SETTINGS.duplicate(true)
		save_settings()
		return

	var file := FileAccess.open(SETTINGS_FILE_PATH, FileAccess.READ)
	if file == null:
		push_error("[SettingsManager] Failed to open settings file: " + str(FileAccess.get_open_error()))
		current_settings = DEFAULT_SETTINGS.duplicate(true)
		return

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var error := json.parse(json_string)

	if error != OK:
		push_error("[SettingsManager] Failed to parse settings JSON: " + json.get_error_message())
		current_settings = DEFAULT_SETTINGS.duplicate(true)
		return

	current_settings = json.data

	# Merge with defaults to ensure all keys exist
	_merge_with_defaults()

	print("[SettingsManager] Settings loaded successfully")


## Saves current settings to JSON file
func save_settings() -> void:
	var file := FileAccess.open(SETTINGS_FILE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[SettingsManager] Failed to save settings file: " + str(FileAccess.get_open_error()))
		return

	var json_string := JSON.stringify(current_settings, "\t")
	file.store_string(json_string)
	file.close()

	print("[SettingsManager] Settings saved to: " + SETTINGS_FILE_PATH)


## Merges current settings with defaults to ensure all keys exist
func _merge_with_defaults() -> void:
	for category in DEFAULT_SETTINGS:
		if not current_settings.has(category):
			current_settings[category] = DEFAULT_SETTINGS[category].duplicate(true)
		else:
			for key in DEFAULT_SETTINGS[category]:
				if not current_settings[category].has(key):
					current_settings[category][key] = DEFAULT_SETTINGS[category][key]


## Applies all settings to the game
func apply_all_settings() -> void:
	apply_display_settings()
	apply_audio_settings()


# ==========================================
# DISPLAY SETTINGS
# ==========================================

func apply_display_settings() -> void:
	var display: Dictionary = current_settings.get("display", {})

	# Apply fullscreen
	var fullscreen: bool = display.get("fullscreen", false)
	var borderless: bool = display.get("borderless", false)

	if fullscreen:
		if borderless:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
	else:
		if borderless:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)

	# Apply resolution
	var resolution: Vector2i = _parse_resolution(display.get("resolution", Vector2i(1920, 1080)))
	DisplayServer.window_set_size(resolution)

	# Center window if windowed
	if not fullscreen:
		var screen_size := DisplayServer.screen_get_size()
		var window_pos := (screen_size - resolution) / 2
		DisplayServer.window_set_position(window_pos)

	# Apply VSync
	var vsync: bool = display.get("vsync", true)
	if vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)


func set_fullscreen(enabled: bool) -> void:
	current_settings["display"]["fullscreen"] = enabled
	apply_display_settings()
	save_settings()


func get_fullscreen() -> bool:
	return current_settings.get("display", {}).get("fullscreen", false)


func set_borderless(enabled: bool) -> void:
	current_settings["display"]["borderless"] = enabled
	apply_display_settings()
	save_settings()


func get_borderless() -> bool:
	return current_settings.get("display", {}).get("borderless", false)


func set_resolution(resolution: Vector2i) -> void:
	current_settings["display"]["resolution"] = {"x": resolution.x, "y": resolution.y}
	apply_display_settings()
	save_settings()


func get_resolution() -> Vector2i:
	return _parse_resolution(current_settings.get("display", {}).get("resolution", Vector2i(1920, 1080)))


func set_vsync(enabled: bool) -> void:
	current_settings["display"]["vsync"] = enabled
	apply_display_settings()
	save_settings()


func get_vsync() -> bool:
	return current_settings.get("display", {}).get("vsync", true)


## Helper function to parse resolution from dictionary or Vector2i
func _parse_resolution(value) -> Vector2i:
	if value is Vector2i:
		return value
	elif value is Dictionary:
		return Vector2i(value.get("x", 1920), value.get("y", 1080))
	else:
		return Vector2i(1920, 1080)


# ==========================================
# AUDIO SETTINGS
# ==========================================

func apply_audio_settings() -> void:
	var audio: Dictionary = current_settings.get("audio", {})

	# Apply master volume
	var master_volume: float = audio.get("master_volume", 1.0)
	var master_bus_idx := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_bus_idx, linear_to_db(master_volume))

	# Apply music and SFX volumes through AudioManager
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager:
		var music_volume: float = audio.get("music_volume", 1.0)
		var sfx_volume: float = audio.get("sfx_volume", 1.0)
		audio_manager.set_music_volume(music_volume)
		audio_manager.set_sfx_volume(sfx_volume)

	# Apply audio devices
	var output_device: String = audio.get("audio_output_device", "")
	if not output_device.is_empty():
		AudioServer.output_device = output_device

	var input_device: String = audio.get("mic_input_device", "")
	if not input_device.is_empty():
		AudioServer.input_device = input_device


func set_master_volume(volume: float) -> void:
	current_settings["audio"]["master_volume"] = clamp(volume, 0.0, 1.0)
	var master_bus_idx := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_bus_idx, linear_to_db(current_settings["audio"]["master_volume"]))
	save_settings()


func get_master_volume() -> float:
	return current_settings.get("audio", {}).get("master_volume", 1.0)


func set_music_volume(volume: float) -> void:
	current_settings["audio"]["music_volume"] = clamp(volume, 0.0, 1.0)
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.set_music_volume(current_settings["audio"]["music_volume"])
	save_settings()


func get_music_volume() -> float:
	return current_settings.get("audio", {}).get("music_volume", 1.0)


func set_sfx_volume(volume: float) -> void:
	current_settings["audio"]["sfx_volume"] = clamp(volume, 0.0, 1.0)
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.set_sfx_volume(current_settings["audio"]["sfx_volume"])
	save_settings()


func get_sfx_volume() -> float:
	return current_settings.get("audio", {}).get("sfx_volume", 1.0)


func set_mic_volume(volume: float) -> void:
	current_settings["audio"]["mic_volume"] = clamp(volume, 0.0, 100.0)
	save_settings()


func get_mic_volume() -> float:
	return current_settings.get("audio", {}).get("mic_volume", 100.0)


func set_mic_muted(muted: bool) -> void:
	current_settings["audio"]["mic_muted"] = muted
	save_settings()


func get_mic_muted() -> bool:
	return current_settings.get("audio", {}).get("mic_muted", false)


func set_audio_output_device(device: String) -> void:
	current_settings["audio"]["audio_output_device"] = device
	AudioServer.output_device = device
	save_settings()


func get_audio_output_device() -> String:
	return current_settings.get("audio", {}).get("audio_output_device", "")


func set_mic_input_device(device: String) -> void:
	current_settings["audio"]["mic_input_device"] = device
	AudioServer.input_device = device
	save_settings()


func get_mic_input_device() -> String:
	return current_settings.get("audio", {}).get("mic_input_device", "")
