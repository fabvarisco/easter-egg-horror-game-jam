extends Node3D

const HEADLAMP_COST: int = 25
const STAMINA_COST: int = 10
const HEALTH_COST: int = 10

const COLOR_AFFORDABLE := Color(0.3, 0.8, 0.3)  # Green
const COLOR_UNAFFORDABLE := Color(0.8, 0.3, 0.3)  # Red
const COLOR_OWNED := Color(0.5, 0.5, 0.5)  # Gray

@onready var shop_layer: CanvasLayer = $ShopLayer
@onready var headlamp_button: Button = $ShopLayer/HeadLamp
@onready var stamina_button: Button = $ShopLayer/Stamina
@onready var health_button: Button = $ShopLayer/Health

var _local_player: Player = null


func _ready() -> void:
	shop_layer.visible = false


func _process(_delta: float) -> void:
	if _local_player and shop_layer.visible:
		_update_button_states()


func _is_local_player(body: Node3D) -> bool:
	if not body is Player:
		return false
	var player := body as Player
	# Check if this is the local player (has multiplayer authority)
	if not multiplayer.has_multiplayer_peer():
		return true
	return player.is_multiplayer_authority()


func _update_button_states() -> void:
	if not _local_player:
		return

	var currency: int = ProgressionManager.group_currency

	if _local_player.has_headlamp() or ProgressionManager.player_has_headlamp:
		headlamp_button.text = "Head Lamp (Owned)"
		headlamp_button.disabled = true
		headlamp_button.modulate = COLOR_OWNED
	elif currency < HEADLAMP_COST:
		headlamp_button.text = "Head Lamp %d" % HEADLAMP_COST
		headlamp_button.disabled = true
		headlamp_button.modulate = COLOR_UNAFFORDABLE
	else:
		headlamp_button.text = "Head Lamp %d" % HEADLAMP_COST
		headlamp_button.disabled = false
		headlamp_button.modulate = COLOR_AFFORDABLE

	# Stamina button
	if currency < STAMINA_COST:
		stamina_button.text = "Max Stamina +10"
		stamina_button.disabled = true
		stamina_button.modulate = COLOR_UNAFFORDABLE
	else:
		stamina_button.text = "Max Stamina +10"
		stamina_button.disabled = false
		stamina_button.modulate = COLOR_AFFORDABLE

	# Health button
	if currency < HEALTH_COST:
		health_button.text = "Max Health +10"
		health_button.disabled = true
		health_button.modulate = COLOR_UNAFFORDABLE
	else:
		health_button.text = "Max Health +10"
		health_button.disabled = false
		health_button.modulate = COLOR_AFFORDABLE


func _on_area_3d_body_entered(body: Node3D) -> void:
	if _is_local_player(body):
		_local_player = body as Player
		shop_layer.visible = true
		_update_button_states()


func _on_area_3d_body_exited(body: Node3D) -> void:
	if body == _local_player:
		_local_player = null
		shop_layer.visible = false


func _on_head_lamp_pressed() -> void:
	if not _local_player:
		return
	if _local_player.has_headlamp() or ProgressionManager.player_has_headlamp:
		return
	if ProgressionManager.group_currency < HEADLAMP_COST:
		return

	ProgressionManager.remove_currency(HEADLAMP_COST, "shop_headlamp")
	_local_player.activate_headlamp()
	_update_button_states()


func _on_stamina_pressed() -> void:
	if not _local_player:
		return
	if ProgressionManager.group_currency < STAMINA_COST:
		return

	ProgressionManager.remove_currency(STAMINA_COST, "shop_stamina")
	_local_player.add_max_stamina(10)
	_update_button_states()


func _on_health_pressed() -> void:
	if not _local_player:
		return
	if ProgressionManager.group_currency < HEALTH_COST:
		return

	ProgressionManager.remove_currency(HEALTH_COST, "shop_health")
	_local_player.add_max_health(10)
	_update_button_states()
