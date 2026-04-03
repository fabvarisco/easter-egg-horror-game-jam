extends CanvasLayer
## Game HUD - Shows connected players with voice feedback

@onready var _player_list: VBoxContainer = $Control/PlayerList
@onready var _egg_counter: Label = $Control/EggCounter
@onready var _car_message: Label = $Control/CarMessage
@onready var _stamina_bar: ProgressBar = $Control/StaminaContainer/StaminaBar
@onready var _health_bar: ProgressBar = $Control/HealthContainer/HealthBar
@onready var _currency_label: Label = $Control/CurrencyLabel

var _player_panels: Dictionary = {}
var _is_singleplayer: bool = false
var _local_player: Node = null
var _player_health_connection_made: bool = false

const COLOR_DEFAULT := Color.WHITE
const COLOR_SPEAKING := Color.GREEN


func _ready() -> void:
	VoiceManager.player_speaking_changed.connect(_on_player_speaking_changed)

	MultiplayerManager.player_connected.connect(_on_player_connected)
	MultiplayerManager.player_disconnected.connect(_on_player_disconnected)

	_is_singleplayer = MultiplayerManager.current_mode == MultiplayerManager.NetworkMode.NONE

	ProgressionManager.currency_changed.connect(_on_currency_changed)
	_update_currency_display()

	call_deferred("_initialize_players")
	call_deferred("_find_local_player")


func _process(_delta: float) -> void:
	_update_stamina_bar()


func _initialize_players() -> void:
	if _is_singleplayer:
		add_player(1, true)
	else:
		for peer_id in MultiplayerManager.players:
			var is_local: bool = peer_id == MultiplayerManager.my_peer_id
			add_player(peer_id, is_local)


func add_player(peer_id: int, is_local: bool) -> void:
	if _player_panels.has(peer_id):
		return

	var panel := HBoxContainer.new()
	panel.name = "Player_%d" % peer_id
	panel.custom_minimum_size = Vector2(300, 0)

	var name_label := Label.new()
	name_label.name = "NameLabel"
	name_label.custom_minimum_size = Vector2(120, 0)
	var player_name := "Player %d" % peer_id
	if is_local:
		player_name += " (You)"
	name_label.text = player_name
	name_label.add_theme_color_override("font_color", COLOR_DEFAULT)
	panel.add_child(name_label)

	var voice_label := Label.new()
	voice_label.name = "VoiceLabel"
	voice_label.text = " [Mic]"
	voice_label.custom_minimum_size = Vector2(50, 0)
	voice_label.add_theme_color_override("font_color", COLOR_SPEAKING)
	voice_label.visible = false
	panel.add_child(voice_label)

	if not is_local and not _is_singleplayer:
		var saved_multiplier: float = VoiceManager.get_player_volume(peer_id)
		var saved_value: float = saved_multiplier * 100.0

		var volume_slider := HSlider.new()
		volume_slider.name = "VolumeSlider"
		volume_slider.min_value = 0.0
		volume_slider.max_value = 200.0
		volume_slider.value = saved_value
		volume_slider.step = 1.0
		volume_slider.custom_minimum_size = Vector2(100, 0)
		volume_slider.value_changed.connect(_on_player_volume_changed.bind(peer_id))
		volume_slider.tooltip_text = "Volume: %d%%" % int(saved_value)
		panel.add_child(volume_slider)

		var volume_label := Label.new()
		volume_label.name = "VolumeLabel"
		volume_label.text = "%d%%" % int(saved_value)
		volume_label.custom_minimum_size = Vector2(40, 0)
		panel.add_child(volume_label)

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


func _on_player_volume_changed(value: float, peer_id: int) -> void:
	"""Called when a player's volume slider changes"""
	var multiplier: float = value / 100.0

	VoiceManager.set_player_volume(peer_id, multiplier)

	if _player_panels.has(peer_id):
		var panel: HBoxContainer = _player_panels[peer_id]
		if is_instance_valid(panel):
			var volume_label: Label = panel.get_node_or_null("VolumeLabel")
			var volume_slider: HSlider = panel.get_node_or_null("VolumeSlider")

			if volume_label:
				volume_label.text = "%d%%" % int(value)

			if volume_slider:
				volume_slider.tooltip_text = "Volume: %d%%" % int(value)


# ==========================================
# EGG COUNTER UI
# ==========================================

func setup_egg_counter(total: int) -> void:
	if _egg_counter:
		_egg_counter.text = "Eggs: 0 / %d" % total
		_egg_counter.visible = true


func update_egg_counter(delivered: int, total: int) -> void:
	if _egg_counter:
		_egg_counter.text = "Eggs: %d / %d" % [delivered, total]
		if delivered >= total:
			_egg_counter.add_theme_color_override("font_color", Color.GREEN)


func show_car_ready() -> void:
	if _car_message:
		_car_message.text = "All eggs collected! Go to the car!"
		_car_message.visible = true


func show_mission_complete() -> void:
	if _car_message:
		_car_message.text = "MISSION COMPLETE!"
		_car_message.add_theme_color_override("font_color", Color.GOLD)
		_car_message.visible = true


func _find_local_player() -> void:
	var players := get_tree().get_nodes_in_group("players")
	if players.is_empty():
		players = get_tree().get_nodes_in_group("player")

	for player in players:
		if not multiplayer.has_multiplayer_peer():
			_local_player = player
			_connect_to_player_health()
			return
		if player.is_multiplayer_authority():
			_local_player = player
			_connect_to_player_health()
			return


func _update_stamina_bar() -> void:
	if not is_instance_valid(_local_player):
		_find_local_player()

	if is_instance_valid(_local_player) and not _player_health_connection_made:
		_connect_to_player_health()

	if not _stamina_bar or not is_instance_valid(_local_player):
		return

	if _local_player and _local_player.has_method("get_stamina_percent"):
		var stamina_percent: float = _local_player.get_stamina_percent()
		_stamina_bar.value = stamina_percent * 100.0

		if stamina_percent < 0.2:
			_stamina_bar.modulate = Color.RED
		elif stamina_percent < 0.5:
			_stamina_bar.modulate = Color.ORANGE
		else:
			_stamina_bar.modulate = Color.WHITE


func _connect_to_player_health() -> void:
	if not is_instance_valid(_local_player) or _player_health_connection_made:
		return

	if _local_player.has_signal("health_changed"):
		_local_player.health_changed.connect(_on_player_health_changed)
		_player_health_connection_made = true

		if _local_player.has_method("get_health"):
			_on_player_health_changed(_local_player.get_health(), _local_player.MAX_HEALTH)


func _on_player_health_changed(current_health: float, max_health: float) -> void:
	if not _health_bar:
		return

	var health_percent: float = current_health / max_health if max_health > 0 else 0.0
	_health_bar.value = health_percent * 100.0

	if health_percent < 0.2:
		_health_bar.modulate = Color.RED
	elif health_percent < 0.5:
		_health_bar.modulate = Color.ORANGE
	else:
		_health_bar.modulate = Color.GREEN


func _exit_tree() -> void:
	if VoiceManager.player_speaking_changed.is_connected(_on_player_speaking_changed):
		VoiceManager.player_speaking_changed.disconnect(_on_player_speaking_changed)
	if MultiplayerManager.player_connected.is_connected(_on_player_connected):
		MultiplayerManager.player_connected.disconnect(_on_player_connected)
	if MultiplayerManager.player_disconnected.is_connected(_on_player_disconnected):
		MultiplayerManager.player_disconnected.disconnect(_on_player_disconnected)


# ==========================================
# CURRENCY DISPLAY
# ==========================================

func _on_currency_changed(new_amount: int, delta: int) -> void:
	_update_currency_display()

	if delta != 0:
		_show_currency_change(delta)


func _update_currency_display() -> void:
	if not _currency_label:
		return

	var amount = ProgressionManager.group_currency
	_currency_label.text = "Currency: %d" % amount

	if amount < 0:
		_currency_label.add_theme_color_override("font_color", Color.RED)
	else:
		_currency_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2, 1))


func _show_currency_change(_delta: int) -> void:
	# TODO: Implement floating text animation
	pass
