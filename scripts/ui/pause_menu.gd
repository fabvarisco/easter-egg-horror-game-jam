extends CanvasLayer
## Pause Menu - Display, audio and microphone settings

signal closed
signal disconnect_requested

# Display controls
@onready var resolution_dropdown: OptionButton = $Panel/MarginContainer/VBoxContainer/ResolutionDropdown
@onready var fullscreen_button: CheckButton = $Panel/MarginContainer/VBoxContainer/FullscreenButton
@onready var borderless_button: CheckButton = $Panel/MarginContainer/VBoxContainer/BorderlessButton
@onready var vsync_button: CheckButton = $Panel/MarginContainer/VBoxContainer/VSyncButton

# Audio controls
@onready var master_volume_slider: HSlider = $Panel/MarginContainer/VBoxContainer/MasterVolumeSlider
@onready var music_volume_slider: HSlider = $Panel/MarginContainer/VBoxContainer/MusicVolumeSlider
@onready var sfx_volume_slider: HSlider = $Panel/MarginContainer/VBoxContainer/SFXVolumeSlider
@onready var mic_volume_slider: HSlider = $Panel/MarginContainer/VBoxContainer/MicVolumeSlider
@onready var mic_mute_button: CheckButton = $Panel/MarginContainer/VBoxContainer/MicMuteButton
@onready var audio_output_dropdown: OptionButton = $Panel/MarginContainer/VBoxContainer/AudioOutputDropdown
@onready var mic_input_dropdown: OptionButton = $Panel/MarginContainer/VBoxContainer/MicInputDropdown

# Button controls
@onready var resume_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonsContainer/ResumeButton
@onready var disconnect_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonsContainer/DisconnectButton
@onready var quit_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonsContainer/QuitButton

var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	# Connect display signals
	resolution_dropdown.item_selected.connect(_on_resolution_selected)
	fullscreen_button.toggled.connect(_on_fullscreen_toggled)
	borderless_button.toggled.connect(_on_borderless_toggled)
	vsync_button.toggled.connect(_on_vsync_toggled)

	# Connect audio signals
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	music_volume_slider.value_changed.connect(_on_music_volume_changed)
	sfx_volume_slider.value_changed.connect(_on_sfx_volume_changed)
	mic_volume_slider.value_changed.connect(_on_mic_volume_changed)
	mic_mute_button.toggled.connect(_on_mic_mute_toggled)
	audio_output_dropdown.item_selected.connect(_on_audio_output_selected)
	mic_input_dropdown.item_selected.connect(_on_mic_input_selected)

	# Connect button signals
	resume_button.pressed.connect(_on_resume_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Populate dropdowns
	_populate_resolutions()
	_populate_audio_devices()
	_populate_mic_devices()

	# Load current settings
	_load_current_settings()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_close_menu()
		get_viewport().set_input_as_handled()


func show_menu(in_game: bool = true) -> void:
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true

	# Hide disconnect button when not in-game (e.g., from main menu)
	disconnect_button.visible = in_game

	# Only populate devices once, not every time menu opens
	if audio_output_dropdown.item_count == 0:
		_populate_audio_devices()
	if mic_input_dropdown.item_count == 0:
		_populate_mic_devices()

	# Reload settings in case they changed
	_load_current_settings()


func _close_menu() -> void:
	visible = false
	Input.mouse_mode = _previous_mouse_mode
	closed.emit()


# ==========================================
# DISPLAY SETTINGS
# ==========================================

func _populate_resolutions() -> void:
	resolution_dropdown.clear()

	var resolutions := SettingsManager.AVAILABLE_RESOLUTIONS
	var current_resolution := SettingsManager.get_resolution()

	for i in range(resolutions.size()):
		var res := resolutions[i]
		var label := "%dx%d" % [res.x, res.y]
		resolution_dropdown.add_item(label, i)

		# Select current resolution
		if res == current_resolution:
			resolution_dropdown.select(i)


func _on_resolution_selected(index: int) -> void:
	var resolution := SettingsManager.AVAILABLE_RESOLUTIONS[index]
	SettingsManager.set_resolution(resolution)


func _on_fullscreen_toggled(enabled: bool) -> void:
	SettingsManager.set_fullscreen(enabled)


func _on_borderless_toggled(enabled: bool) -> void:
	SettingsManager.set_borderless(enabled)


func _on_vsync_toggled(enabled: bool) -> void:
	SettingsManager.set_vsync(enabled)


# ==========================================
# AUDIO SETTINGS
# ==========================================

func _populate_audio_devices() -> void:
	audio_output_dropdown.clear()

	var devices := AudioServer.get_output_device_list()
	var current_device := AudioServer.output_device

	for i in range(devices.size()):
		audio_output_dropdown.add_item(devices[i], i)
		if devices[i] == current_device:
			audio_output_dropdown.select(i)


func _populate_mic_devices() -> void:
	mic_input_dropdown.clear()

	var devices := AudioServer.get_input_device_list()
	var current_device := AudioServer.input_device

	for i in range(devices.size()):
		mic_input_dropdown.add_item(devices[i], i)
		if devices[i] == current_device:
			mic_input_dropdown.select(i)


func _load_current_settings() -> void:
	# Load display settings
	fullscreen_button.button_pressed = SettingsManager.get_fullscreen()
	borderless_button.button_pressed = SettingsManager.get_borderless()
	vsync_button.button_pressed = SettingsManager.get_vsync()

	# Select current resolution
	var current_resolution := SettingsManager.get_resolution()
	var resolutions := SettingsManager.AVAILABLE_RESOLUTIONS
	for i in range(resolutions.size()):
		if resolutions[i] == current_resolution:
			resolution_dropdown.select(i)
			break

	# Load audio settings
	master_volume_slider.value = SettingsManager.get_master_volume() * 100.0
	music_volume_slider.value = SettingsManager.get_music_volume() * 100.0
	sfx_volume_slider.value = SettingsManager.get_sfx_volume() * 100.0
	mic_volume_slider.value = SettingsManager.get_mic_volume()

	# Load mic mute state
	var voice_manager := get_node_or_null("/root/VoiceManager")
	if voice_manager and voice_manager.has_method("is_mic_muted"):
		mic_mute_button.button_pressed = voice_manager.is_mic_muted()
	else:
		mic_mute_button.button_pressed = SettingsManager.get_mic_muted()


func _on_master_volume_changed(value: float) -> void:
	SettingsManager.set_master_volume(value / 100.0)


func _on_music_volume_changed(value: float) -> void:
	SettingsManager.set_music_volume(value / 100.0)


func _on_sfx_volume_changed(value: float) -> void:
	SettingsManager.set_sfx_volume(value / 100.0)


func _on_mic_volume_changed(value: float) -> void:
	SettingsManager.set_mic_volume(value)

	var voice_manager := get_node_or_null("/root/VoiceManager")
	if voice_manager and voice_manager.has_method("set_mic_volume"):
		voice_manager.set_mic_volume(value)


func _on_mic_mute_toggled(is_muted: bool) -> void:
	SettingsManager.set_mic_muted(is_muted)

	var voice_manager := get_node_or_null("/root/VoiceManager")
	if voice_manager and voice_manager.has_method("set_mic_muted"):
		voice_manager.set_mic_muted(is_muted)


func _on_audio_output_selected(index: int) -> void:
	var device_name := audio_output_dropdown.get_item_text(index)
	SettingsManager.set_audio_output_device(device_name)


func _on_mic_input_selected(index: int) -> void:
	var device_name := mic_input_dropdown.get_item_text(index)
	SettingsManager.set_mic_input_device(device_name)


# ==========================================
# BUTTON HANDLERS
# ==========================================

func _on_resume_pressed() -> void:
	_close_menu()


func _on_disconnect_pressed() -> void:
	_close_menu()
	disconnect_requested.emit()


func _on_quit_pressed() -> void:
	get_tree().quit()
