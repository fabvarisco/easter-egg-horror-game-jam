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


# Room/Lobby view
@onready var room_menu: VBoxContainer = $VBoxContainer/RoomMenu
@onready var room_code_label: Label = $VBoxContainer/RoomMenu/RoomCodeLabel
@onready var room_players_label: Label = $VBoxContainer/RoomMenu/PlayersLabel
@onready var start_game_button: Button = $VBoxContainer/RoomMenu/StartGameButton
@onready var leave_button: Button = $VBoxContainer/RoomMenu/LeaveButton

@onready var status_label: Label = $VBoxContainer/StatusLabel

@onready var multiplayer_manager: Node = get_node("/root/MultiplayerManager")

var _current_mode: String = "main" 

func _ready() -> void:
	# Main menu
	singleplayer_button.pressed.connect(_on_singleplayer_pressed)
	online_button.pressed.connect(_on_online_pressed)
	lan_button.pressed.connect(_on_lan_pressed)

	# Online menu
	online_host_button.pressed.connect(_on_online_host_pressed)
	online_join_button.pressed.connect(_on_online_join_pressed)

	# Room menu
	start_game_button.pressed.connect(_on_start_game_pressed)
	leave_button.pressed.connect(_on_leave_pressed)

	# Multiplayer signals
	multiplayer_manager.player_connected.connect(_on_player_connected)
	multiplayer_manager.player_disconnected.connect(_on_player_disconnected)
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

func _show_menu(menu_name: String) -> void:
	_current_mode = menu_name
	main_menu.visible = menu_name == "main"
	online_menu.visible = menu_name == "online"
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
	_update_players_label()
	_show_menu("room")
	status_label.text = "Waiting for players..."

func _on_connection_succeeded() -> void:
	_update_players_label()
	_show_menu("room")
	status_label.text = "Connected!"

func _on_connection_failed() -> void:
	status_label.text = "Connection failed!"

func _on_server_disconnected() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_menu("main")
	status_label.text = "Host disconnected!"

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
	await multiplayer_manager.leave_game()
	multiplayer_manager.stop_searching_lan()
	_show_menu("main")
	status_label.text = ""


func _start_game(is_singleplayer: bool) -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	game_started.emit(is_singleplayer)
