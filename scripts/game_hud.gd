extends CanvasLayer
## Game HUD - Shows connected players with voice feedback

@onready var _player_list: VBoxContainer = $Control/PlayerList

var _player_panels: Dictionary = {}  # peer_id -> HBoxContainer
var _is_singleplayer: bool = false

const COLOR_DEFAULT := Color.WHITE
const COLOR_SPEAKING := Color.GREEN


func _ready() -> void:
	# Connect to VoiceManager speaking signal
	VoiceManager.player_speaking_changed.connect(_on_player_speaking_changed)

	# Connect to multiplayer events for player join/leave
	MultiplayerManager.player_connected.connect(_on_player_connected)
	MultiplayerManager.player_disconnected.connect(_on_player_disconnected)

	# Check if singleplayer
	_is_singleplayer = MultiplayerManager.current_mode == MultiplayerManager.NetworkMode.NONE

	# Add existing players (deferred to ensure scene is fully loaded)
	call_deferred("_initialize_players")


func _initialize_players() -> void:
	if _is_singleplayer:
		# In singleplayer, just show "Player 1 (You)"
		add_player(1, true)
	else:
		# Add all currently connected players
		for peer_id in MultiplayerManager.players:
			var is_local: bool = peer_id == MultiplayerManager.my_peer_id
			add_player(peer_id, is_local)


func add_player(peer_id: int, is_local: bool) -> void:
	if _player_panels.has(peer_id):
		return

	var panel := HBoxContainer.new()
	panel.name = "Player_%d" % peer_id

	var name_label := Label.new()
	name_label.name = "NameLabel"
	var player_name := "Player %d" % peer_id
	if is_local:
		player_name += " (You)"
	name_label.text = player_name
	name_label.add_theme_color_override("font_color", COLOR_DEFAULT)
	panel.add_child(name_label)

	var voice_label := Label.new()
	voice_label.name = "VoiceLabel"
	voice_label.text = " [Speaking]"
	voice_label.add_theme_color_override("font_color", COLOR_SPEAKING)
	voice_label.visible = false
	panel.add_child(voice_label)

	_player_list.add_child(panel)
	_player_panels[peer_id] = panel


func remove_player(peer_id: int) -> void:
	if not _player_panels.has(peer_id):
		return

	var panel: HBoxContainer = _player_panels[peer_id]
	if is_instance_valid(panel):
		panel.queue_free()
	_player_panels.erase(peer_id)


func update_player_speaking(peer_id: int, is_speaking: bool) -> void:
	if not _player_panels.has(peer_id):
		return

	var panel: HBoxContainer = _player_panels[peer_id]
	if not is_instance_valid(panel):
		return

	var name_label: Label = panel.get_node_or_null("NameLabel")
	var voice_label: Label = panel.get_node_or_null("VoiceLabel")

	if name_label:
		name_label.add_theme_color_override("font_color", COLOR_SPEAKING if is_speaking else COLOR_DEFAULT)

	if voice_label:
		voice_label.visible = is_speaking


func _on_player_speaking_changed(peer_id: int, is_speaking: bool) -> void:
	update_player_speaking(peer_id, is_speaking)


func _on_player_connected(peer_id: int) -> void:
	var is_local: bool = peer_id == MultiplayerManager.my_peer_id
	add_player(peer_id, is_local)


func _on_player_disconnected(peer_id: int) -> void:
	remove_player(peer_id)
