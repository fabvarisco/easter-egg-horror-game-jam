extends CanvasLayer
## Connection Menu - Simplified menu for connecting to games

signal connection_established(is_singleplayer: bool)
signal settings_requested

# Main menu
@onready var main_menu: VBoxContainer = $Control/VBoxContainer/MainMenu
@onready var singleplayer_button: Button = $Control/VBoxContainer/MainMenu/SingleplayerButton
@onready var online_button: Button = $Control/VBoxContainer/MainMenu/OnlineButton
@onready var settings_button: Button = $Control/VBoxContainer/MainMenu/SettingsButton

# Online menu (EOS)
@onready var online_menu: VBoxContainer = $Control/VBoxContainer/OnlineMenu
@onready var online_host_button: Button = $Control/VBoxContainer/OnlineMenu/HostButton
@onready var online_join_button: Button = $Control/VBoxContainer/OnlineMenu/JoinButton
@onready var online_code_input: LineEdit = $Control/VBoxContainer/OnlineMenu/CodeInput
@onready var online_back_button: Button = $Control/VBoxContainer/OnlineMenu/BackButton

# Room/Waiting view
@onready var room_menu: VBoxContainer = $Control/VBoxContainer/RoomMenu
@onready var room_code_label: Label = $Control/VBoxContainer/RoomMenu/RoomCodeLabel
@onready var room_status_label: Label = $Control/VBoxContainer/RoomMenu/StatusLabel
@onready var leave_button: Button = $Control/VBoxContainer/RoomMenu/LeaveButton

@onready var status_label: Label = $Control/VBoxContainer/StatusLabel

@onready var multiplayer_manager: Node = get_node("/root/MultiplayerManager")

var _current_mode: String = "main"


func _ready() -> void:
	# Main menu
	singleplayer_button.pressed.connect(_on_singleplayer_pressed)
	online_button.pressed.connect(_on_online_pressed)
	settings_button.pressed.connect(_on_settings_pressed)

	# Online menu
	online_host_button.pressed.connect(_on_online_host_pressed)
	online_join_button.pressed.connect(_on_online_join_pressed)
	online_back_button.pressed.connect(_on_back_pressed)

	# Room menu
	leave_button.pressed.connect(_on_leave_pressed)

	# Multiplayer signals
	multiplayer_manager.connection_succeeded.connect(_on_connection_succeeded)
	multiplayer_manager.connection_failed.connect(_on_connection_failed)
	multiplayer_manager.server_disconnected.connect(_on_server_disconnected)
	multiplayer_manager.room_created.connect(_on_room_created)
	multiplayer_manager.lobby_join_failed.connect(_on_lobby_join_failed)

	_show_menu("main")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Start playing lobby music
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_lobby_music()

	# Disable Online button if EOS not available
	if not multiplayer_manager.is_eos_available():
		online_button.disabled = true
		online_button.tooltip_text = "EOS not configured"


func show_menu() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_menu("main")


func _show_menu(menu_name: String) -> void:
	_current_mode = menu_name
	main_menu.visible = menu_name == "main"
	online_menu.visible = menu_name == "online"
	room_menu.visible = menu_name == "room"

	if menu_name == "main":
		status_label.text = ""


# Main menu handlers
func _on_singleplayer_pressed() -> void:
	_hide_and_emit(true)


func _on_online_pressed() -> void:
	_show_menu("online")
	status_label.text = ""


func _on_lan_pressed() -> void:
	_show_menu("lan")
	status_label.text = ""


func _on_settings_pressed() -> void:
	settings_requested.emit()


func _on_back_pressed() -> void:
	_show_menu("main")

# Online (EOS) handlers
func _on_online_host_pressed() -> void:
	status_label.text = "Creating online lobby..."
	multiplayer_manager.host_game_eos("Player's Game")


func _on_online_join_pressed() -> void:
	var code := online_code_input.text.strip_edges().to_upper()
	if code.length() != 6:
		status_label.text = "Enter a 6-character room code"
		return

	status_label.text = "Joining lobby " + code + "..."
	multiplayer_manager.join_game_eos(code)



# Room handlers
func _on_room_created(code: String) -> void:
	room_code_label.text = "Code: " + code
	room_status_label.text = "Waiting for players..."
	_show_menu("room")
	# Note: Don't emit connection_established here - wait for connection_succeeded


func _on_connection_succeeded() -> void:
	status_label.text = "Connected!"
	# For clients joining, emit connection
	_hide_and_emit(false)


func _on_connection_failed() -> void:
	status_label.text = "Connection failed!"


func _on_server_disconnected() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_menu("main")
	status_label.text = "Host disconnected!"


func _on_lobby_join_failed(reason: String) -> void:
	status_label.text = "Failed: " + reason


func _on_leave_pressed() -> void:
	await multiplayer_manager.leave_game()
	_show_menu("main")
	status_label.text = ""




func _hide_and_emit(is_singleplayer: bool) -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	connection_established.emit(is_singleplayer)
