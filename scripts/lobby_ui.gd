extends Control

signal game_started(is_singleplayer: bool)

# Main menu
@onready var main_menu: VBoxContainer = $VBoxContainer/MainMenu
@onready var singleplayer_button: Button = $VBoxContainer/MainMenu/SingleplayerButton
@onready var online_button: Button = $VBoxContainer/MainMenu/OnlineButton
@onready var lan_button: Button = $VBoxContainer/MainMenu/LANButton

# Online menu (EOS)
@onready var online_menu: VBoxContainer = $VBoxContainer/OnlineMenu
@onready var online_host_button: Button = $VBoxContainer/OnlineMenu/HostButton
@onready var online_join_button: Button = $VBoxContainer/OnlineMenu/JoinButton
@onready var online_code_input: LineEdit = $VBoxContainer/OnlineMenu/CodeInput
@onready var online_back_button: Button = $VBoxContainer/OnlineMenu/BackButton

# LAN menu
@onready var lan_menu: VBoxContainer = $VBoxContainer/LANMenu
@onready var lan_host_button: Button = $VBoxContainer/LANMenu/HostButton
@onready var lan_find_button: Button = $VBoxContainer/LANMenu/FindButton
@onready var lan_back_button: Button = $VBoxContainer/LANMenu/BackButton
@onready var server_list: VBoxContainer = $VBoxContainer/LANMenu/ServerList

# Room/Lobby view
@onready var room_menu: VBoxContainer = $VBoxContainer/RoomMenu
@onready var room_code_label: Label = $VBoxContainer/RoomMenu/RoomCodeLabel
@onready var room_players_label: Label = $VBoxContainer/RoomMenu/PlayersLabel
@onready var start_game_button: Button = $VBoxContainer/RoomMenu/StartGameButton
@onready var leave_button: Button = $VBoxContainer/RoomMenu/LeaveButton

@onready var status_label: Label = $VBoxContainer/StatusLabel

@onready var multiplayer_manager: Node = get_node("/root/MultiplayerManager")

var _server_buttons: Dictionary = {}
var _current_mode: String = "main"  # main, online, lan, room

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
	start_game_button.pressed.connect(_on_start_game_pressed)
	leave_button.pressed.connect(_on_leave_pressed)

	# Multiplayer signals
	multiplayer_manager.player_connected.connect(_on_player_connected)
	multiplayer_manager.player_disconnected.connect(_on_player_disconnected)
	multiplayer_manager.connection_succeeded.connect(_on_connection_succeeded)
	multiplayer_manager.connection_failed.connect(_on_connection_failed)
	multiplayer_manager.room_created.connect(_on_room_created)
	multiplayer_manager.server_found.connect(_on_server_found)
	multiplayer_manager.lobby_join_failed.connect(_on_lobby_join_failed)

	_show_menu("main")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Disable Online button if EOS not available
	if not multiplayer_manager.is_eos_available():
		online_button.disabled = true
		online_button.tooltip_text = "EOS not configured"

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
	_start_game(true)

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
	_update_players_label()
	_show_menu("room")
	status_label.text = "Waiting for players..."

func _on_connection_succeeded() -> void:
	_update_players_label()
	_show_menu("room")
	status_label.text = "Connected!"
	_clear_server_list()

func _on_connection_failed() -> void:
	status_label.text = "Connection failed!"

func _on_lobby_join_failed(reason: String) -> void:
	status_label.text = "Failed: " + reason

func _on_player_connected(_id: int) -> void:
	_update_players_label()
	status_label.text = "Player joined!"

func _on_player_disconnected(_id: int) -> void:
	_update_players_label()
	status_label.text = "Player left."

func _update_players_label() -> void:
	room_players_label.text = "Players: " + str(multiplayer_manager.players.size()) + "/4"

func _on_start_game_pressed() -> void:
	_start_game(false)

func _on_leave_pressed() -> void:
	multiplayer_manager.leave_game()
	multiplayer_manager.stop_searching_lan()
	_clear_server_list()
	_show_menu("main")
	status_label.text = ""

func _clear_server_list() -> void:
	for btn in _server_buttons.values():
		if is_instance_valid(btn):
			btn.queue_free()
	_server_buttons.clear()

func _start_game(is_singleplayer: bool) -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	game_started.emit(is_singleplayer)
