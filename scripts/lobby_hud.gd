extends CanvasLayer
## Lobby HUD - Shows player list, ready status, and countdown

@onready var player_list: VBoxContainer = $Control/PlayerList
@onready var instruction_label: Label = $Control/InstructionLabel
@onready var countdown_label: Label = $Control/CountdownLabel
@onready var room_code_label: Label = $Control/RoomCodeLabel

var _player_entries: Dictionary = {}  # peer_id -> HBoxContainer


func _ready() -> void:
	countdown_label.visible = false
	instruction_label.text = "Pressione F no pedestal para confirmar"


func add_player(peer_id: int, is_local: bool = false) -> void:
	if _player_entries.has(peer_id):
		return

	var entry := HBoxContainer.new()
	entry.name = str(peer_id)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	var player_name := "Player " + str(peer_id)
	if is_local:
		player_name += " (You)"
	name_label.text = player_name
	name_label.custom_minimum_size.x = 150
	entry.add_child(name_label)

	var status_label := Label.new()
	status_label.name = "StatusLabel"
	status_label.text = "[Not Ready]"
	status_label.add_theme_color_override("font_color", Color.RED)
	entry.add_child(status_label)

	player_list.add_child(entry)
	_player_entries[peer_id] = entry


func remove_player(peer_id: int) -> void:
	if not _player_entries.has(peer_id):
		return

	var entry: HBoxContainer = _player_entries[peer_id]
	if is_instance_valid(entry):
		entry.queue_free()
	_player_entries.erase(peer_id)


func update_player_ready(peer_id: int, is_ready: bool) -> void:
	if not _player_entries.has(peer_id):
		return

	var entry: HBoxContainer = _player_entries[peer_id]
	var status_label: Label = entry.get_node("StatusLabel")

	if is_ready:
		status_label.text = "[Ready]"
		status_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		status_label.text = "[Not Ready]"
		status_label.add_theme_color_override("font_color", Color.RED)


func show_countdown(seconds: int) -> void:
	countdown_label.visible = true
	countdown_label.text = "Starting in " + str(seconds) + "..."
	instruction_label.visible = false


func hide_countdown() -> void:
	countdown_label.visible = false
	instruction_label.visible = true


func clear_players() -> void:
	for entry in _player_entries.values():
		if is_instance_valid(entry):
			entry.queue_free()
	_player_entries.clear()


func set_room_code(code: String) -> void:
	if code.is_empty():
		room_code_label.text = ""
		room_code_label.visible = false
	else:
		room_code_label.text = "Código: " + code
		room_code_label.visible = true


func clear_room_code() -> void:
	room_code_label.text = ""
	room_code_label.visible = false
