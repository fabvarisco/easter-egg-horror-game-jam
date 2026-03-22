extends CanvasLayer
## Pause Menu - Audio and microphone settings

signal closed
signal disconnect_requested

@onready var master_volume_slider: HSlider = $Panel/MarginContainer/VBoxContainer/MasterVolumeSlider
@onready var mic_volume_slider: HSlider = $Panel/MarginContainer/VBoxContainer/MicVolumeSlider
@onready var mic_mute_button: CheckButton = $Panel/MarginContainer/VBoxContainer/MicMuteButton
@onready var audio_output_dropdown: OptionButton = $Panel/MarginContainer/VBoxContainer/AudioOutputDropdown
@onready var mic_input_dropdown: OptionButton = $Panel/MarginContainer/VBoxContainer/MicInputDropdown
@onready var resume_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonsContainer/ResumeButton
@onready var disconnect_button: Button = $Panel/MarginContainer/VBoxContainer/ButtonsContainer/DisconnectButton

var _previous_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	# Connect signals
	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	mic_volume_slider.value_changed.connect(_on_mic_volume_changed)
	mic_mute_button.toggled.connect(_on_mic_mute_toggled)
	audio_output_dropdown.item_selected.connect(_on_audio_output_selected)
	mic_input_dropdown.item_selected.connect(_on_mic_input_selected)
	resume_button.pressed.connect(_on_resume_pressed)
	disconnect_button.pressed.connect(_on_disconnect_pressed)

	# Populate devices
	_populate_audio_devices()
	_populate_mic_devices()

	# Load current volume settings
	_load_current_settings()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_close_menu()
		get_viewport().set_input_as_handled()


func show_menu() -> void:
	_previous_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true

	# Only populate devices once, not every time menu opens
	if audio_output_dropdown.item_count == 0:
		_populate_audio_devices()
	if mic_input_dropdown.item_count == 0:
		_populate_mic_devices()

	# Load current mute state
	var voice_manager := get_node_or_null("/root/VoiceManager")
	if voice_manager and voice_manager.has_method("is_mic_muted"):
		mic_mute_button.button_pressed = voice_manager.is_mic_muted()


func _close_menu() -> void:
	visible = false
	Input.mouse_mode = _previous_mouse_mode
	closed.emit()


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
	# Load master volume (convert from dB to linear percentage)
	var master_bus_idx := AudioServer.get_bus_index("Master")
	var master_db := AudioServer.get_bus_volume_db(master_bus_idx)
	var master_linear := db_to_linear(master_db) * 100.0
	master_volume_slider.value = master_linear

	# Mic volume - default to 100 if no saved setting
	mic_volume_slider.value = 100.0


func _on_master_volume_changed(value: float) -> void:
	var master_bus_idx := AudioServer.get_bus_index("Master")
	var db := linear_to_db(value / 100.0)
	AudioServer.set_bus_volume_db(master_bus_idx, db)


func _on_mic_volume_changed(value: float) -> void:
	# Store mic volume for use with EOS voice chat
	# EOS uses 0-100 scale directly
	var voice_manager := get_node_or_null("/root/VoiceManager")
	if voice_manager and voice_manager.has_method("set_mic_volume"):
		voice_manager.set_mic_volume(value)


func _on_mic_mute_toggled(is_muted: bool) -> void:
	var voice_manager := get_node_or_null("/root/VoiceManager")
	if voice_manager and voice_manager.has_method("set_mic_muted"):
		voice_manager.set_mic_muted(is_muted)


func _on_audio_output_selected(index: int) -> void:
	var device_name := audio_output_dropdown.get_item_text(index)
	AudioServer.output_device = device_name


func _on_mic_input_selected(index: int) -> void:
	var device_name := mic_input_dropdown.get_item_text(index)
	AudioServer.input_device = device_name


func _on_resume_pressed() -> void:
	_close_menu()


func _on_disconnect_pressed() -> void:
	_close_menu()
	disconnect_requested.emit()
