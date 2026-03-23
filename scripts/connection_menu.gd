extends CanvasLayer
## Connection Menu - Simplified menu for connecting to games

signal connection_established(is_singleplayer: bool)

# Main menu
@onready var main_menu: VBoxContainer = $Control/VBoxContainer/MainMenu
@onready var singleplayer_button: Button = $Control/VBoxContainer/MainMenu/SingleplayerButton
@onready var online_button: Button = $Control/VBoxContainer/MainMenu/OnlineButton
@onready var lan_button: Button = $Control/VBoxContainer/MainMenu/LANButton

# Online menu (EOS)
@onready var online_menu: VBoxContainer = $Control/VBoxContainer/OnlineMenu
@onready var online_host_button: Button = $Control/VBoxContainer/OnlineMenu/HostButton
@onready var online_join_button: Button = $Control/VBoxContainer/OnlineMenu/JoinButton
@onready var online_code_input: LineEdit = $Control/VBoxContainer/OnlineMenu/CodeInput
@onready var online_back_button: Button = $Control/VBoxContainer/OnlineMenu/BackButton

# LAN menu
@onready var lan_menu: VBoxContainer = $Control/VBoxContainer/LANMenu
@onready var lan_host_button: Button = $Control/VBoxContainer/LANMenu/HostButton
@onready var lan_find_button: Button = $Control/VBoxContainer/LANMenu/FindButton
@onready var lan_back_button: Button = $Control/VBoxContainer/LANMenu/BackButton
@onready var server_list: VBoxContainer = $Control/VBoxContainer/LANMenu/ServerList

# Room/Waiting view
@onready var room_menu: VBoxContainer = $Control/VBoxContainer/RoomMenu
@onready var room_code_label: Label = $Control/VBoxContainer/RoomMenu/RoomCodeLabel
@onready var room_status_label: Label = $Control/VBoxContainer/RoomMenu/StatusLabel
@onready var leave_button: Button = $Control/VBoxContainer/RoomMenu/LeaveButton

@onready var status_label: Label = $Control/VBoxContainer/StatusLabel

@onready var multiplayer_manager: Node = get_node("/root/MultiplayerManager")

var _server_buttons: Dictionary = {}
var _current_mode: String = "main"


func _ready() -> void:
	# Main menu
	singleplayer_button.pressed.connect(_on_singleplayer_pressed)
	online_button.pressed.connect(_on_online_pressed)
	lan_button.pressed.connect(_on_lan_pressed)

	# Online menu
	online_host_button.pressed.connect(_on_online_host_pressed)
	online_join_button.pressed.connect(_on_online_join_pressed)
	online_back_button.pressed.connect(_on_back_pressed)

	# LAN menu
	lan_host_button.pressed.connect(_on_lan_host_pressed)
	lan_find_button.pressed.connect(_on_lan_find_pressed)
	lan_back_button.pressed.connect(_on_back_pressed)

	# Room menu
	leave_button.pressed.connect(_on_leave_pressed)

	# Multiplayer signals
	multiplayer_manager.connection_succeeded.connect(_on_connection_succeeded)
	multiplayer_manager.connection_failed.connect(_on_connection_failed)
	multiplayer_manager.server_disconnected.connect(_on_server_disconnected)
	multiplayer_manager.room_created.connect(_on_room_created)
	multiplayer_manager.server_found.connect(_on_server_found)
	multiplayer_manager.lobby_join_failed.connect(_on_lobby_join_failed)

	_show_menu("main")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

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
	lan_menu.visible = menu_name == "lan"
	room_menu.visible = menu_name == "room"
	server_list.visible = menu_name == "lan_searching"

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


func _on_back_pressed() -> void:
	multiplayer_manager.stop_searching_lan()
	_clear_server_list()
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


# LAN handlers
func _on_lan_host_pressed() -> void:
	status_label.text = "Creating LAN game..."
	multiplayer_manager.host_game_lan("Player's Game")


func _on_lan_find_pressed() -> void:
	_clear_server_list()
	status_label.text = "Searching for LAN games..."
	lan_menu.visible = false
	server_list.visible = true
	multiplayer_manager.start_searching_lan()

	# Add back button to server list
	var back_btn := Button.new()
	back_btn.text = "< Back"
	back_btn.pressed.connect(func():
		multiplayer_manager.stop_searching_lan()
		_clear_server_list()
		_show_menu("lan")
	)
	server_list.add_child(back_btn)
	_server_buttons["_back"] = back_btn


func _on_server_found(server_info: Dictionary) -> void:
	var ip: String = server_info.ip
	if _server_buttons.has(ip):
		return

	var btn := Button.new()
	btn.text = "%s (%d/%d)" % [server_info.name, server_info.players, server_info.max]
	btn.pressed.connect(_on_server_button_pressed.bind(ip))
	server_list.add_child(btn)
	_server_buttons[ip] = btn


func _on_server_button_pressed(ip: String) -> void:
	status_label.text = "Connecting..."
	multiplayer_manager.join_game_lan(ip)


# Room handlers
func _on_room_created(code: String) -> void:
	room_code_label.text = "Code: " + code
	room_status_label.text = "Waiting for players..."
	_show_menu("room")
	# Note: Don't emit connection_established here - wait for connection_succeeded


func _on_connection_succeeded() -> void:
	_clear_server_list()
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
	multiplayer_manager.stop_searching_lan()
	_clear_server_list()
	_show_menu("main")
	status_label.text = ""


func _clear_server_list() -> void:
	for btn in _server_buttons.values():
		if is_instance_valid(btn):
			btn.queue_free()
	_server_buttons.clear()


func _hide_and_emit(is_singleplayer: bool) -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	connection_established.emit(is_singleplayer)
