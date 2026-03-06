extends Control

@onready var host_button: Button = $VBoxContainer/HostButton
@onready var join_button: Button = $VBoxContainer/JoinButton
@onready var code_input: LineEdit = $VBoxContainer/CodeInput
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var leave_button: Button = $VBoxContainer/LeaveButton
@onready var room_code_label: Label = $VBoxContainer/RoomCodeLabel

@onready var multiplayer_manager: Node = get_node("/root/MultiplayerManager")

func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	leave_button.pressed.connect(_on_leave_pressed)

	multiplayer_manager.player_connected.connect(_on_player_connected)
	multiplayer_manager.player_disconnected.connect(_on_player_disconnected)
	multiplayer_manager.connection_succeeded.connect(_on_connection_succeeded)
	multiplayer_manager.connection_failed.connect(_on_connection_failed)
	multiplayer_manager.room_created.connect(_on_room_created)

	_update_ui(false)

func _on_host_pressed() -> void:
	status_label.text = "Creating room..."
	multiplayer_manager.host_game()

func _on_join_pressed() -> void:
	var code := code_input.text.strip_edges().to_upper()
	if code.length() != 6:
		status_label.text = "Enter a 6-character room code"
		return

	status_label.text = "Joining room " + code + "..."
	multiplayer_manager.join_game(code)

func _on_leave_pressed() -> void:
	multiplayer_manager.leave_game()
	status_label.text = "Disconnected."
	room_code_label.text = ""
	_update_ui(false)

func _on_room_created(code: String) -> void:
	room_code_label.text = "Room Code: " + code
	status_label.text = "Waiting for players..."
	_update_ui(true)

func _on_connection_succeeded() -> void:
	status_label.text = "Connected! Players: " + str(multiplayer_manager.players.size())
	_update_ui(true)

func _on_connection_failed() -> void:
	status_label.text = "Connection failed. Check the room code."
	_update_ui(false)

func _on_player_connected(id: int) -> void:
	status_label.text = "Player joined! Total: " + str(multiplayer_manager.players.size())

func _on_player_disconnected(id: int) -> void:
	status_label.text = "Player left. Total: " + str(multiplayer_manager.players.size())

func _update_ui(in_game: bool) -> void:
	host_button.visible = not in_game
	join_button.visible = not in_game
	code_input.visible = not in_game
	leave_button.visible = in_game
	room_code_label.visible = in_game
