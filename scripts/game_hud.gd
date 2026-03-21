extends CanvasLayer
## Game HUD - Shows connected players with voice feedback

@onready var _player_list: VBoxContainer = $Control/PlayerList
@onready var _egg_counter: Label = $Control/EggCounter
@onready var _car_message: Label = $Control/CarMessage
@onready var _stamina_bar: ProgressBar = $Control/StaminaContainer/StaminaBar

var _player_panels: Dictionary = {}  # peer_id -> HBoxContainer
var _is_singleplayer: bool = false
var _local_player: Node = null

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
	call_deferred("_find_local_player")


func _process(_delta: float) -> void:
	_update_stamina_bar()


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


# ==========================================
# EGG COUNTER UI
# ==========================================

func setup_egg_counter(total: int) -> void:
	if _egg_counter:
		_egg_counter.text = "Ovos: 0 / %d" % total
		_egg_counter.visible = true


func update_egg_counter(delivered: int, total: int) -> void:
	if _egg_counter:
		_egg_counter.text = "Ovos: %d / %d" % [delivered, total]
		if delivered >= total:
			_egg_counter.add_theme_color_override("font_color", Color.GREEN)


func show_car_ready() -> void:
	if _car_message:
		_car_message.text = "Todos os ovos coletados! Vá para o carro!"
		_car_message.visible = true


func show_mission_complete() -> void:
	if _car_message:
		_car_message.text = "MISSÃO COMPLETA!"
		_car_message.add_theme_color_override("font_color", Color.GOLD)
		_car_message.visible = true


func _find_local_player() -> void:
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		# Tentar grupo alternativo
		players = get_tree().get_nodes_in_group("player")

	for player in players:
		if not multiplayer.has_multiplayer_peer():
			_local_player = player
			print("[GameHUD] Found local player (singleplayer): ", player.name)
			return
		if player.is_multiplayer_authority():
			_local_player = player
			print("[GameHUD] Found local player (multiplayer): ", player.name)
			return

	if not _local_player:
		print("[GameHUD] WARNING: No local player found yet")


func _update_stamina_bar() -> void:
	# Se ainda não encontrou o player, tentar novamente
	if not is_instance_valid(_local_player):
		_find_local_player()

	if not _stamina_bar or not is_instance_valid(_local_player):
		return

	if _local_player and _local_player.has_method("get_stamina_percent"):
		var stamina_percent: float = _local_player.get_stamina_percent()
		_stamina_bar.value = stamina_percent * 100.0

		# Mudar cor baseado no nível de stamina
		if stamina_percent < 0.2:
			_stamina_bar.modulate = Color.RED
		elif stamina_percent < 0.5:
			_stamina_bar.modulate = Color.ORANGE
		else:
			_stamina_bar.modulate = Color.WHITE


func _exit_tree() -> void:
	# Disconnect from autoload signals to prevent errors when scene changes
	if VoiceManager.player_speaking_changed.is_connected(_on_player_speaking_changed):
		VoiceManager.player_speaking_changed.disconnect(_on_player_speaking_changed)
	if MultiplayerManager.player_connected.is_connected(_on_player_connected):
		MultiplayerManager.player_connected.disconnect(_on_player_connected)
	if MultiplayerManager.player_disconnected.is_connected(_on_player_disconnected):
		MultiplayerManager.player_disconnected.disconnect(_on_player_disconnected)
