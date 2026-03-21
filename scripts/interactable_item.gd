extends Node3D

var _nearby_players: Array = []
var _is_showing_item: bool = false
@export var model: Mesh
@export var descriptionValue: String = ""
@export var is_static: bool = false

var showing_item_scene = preload("res://scenes/showing_item.tscn")

func _ready() -> void:
	pass # Replace with function body.


func _process(_delta: float) -> void:
	pass


func _input(_event: InputEvent) -> void:
	if _event.is_action_pressed("interact") and _is_local_player_nearby() and not _is_showing_item:
		show_item()

func _on_area_3d_body_entered(_body: Node3D) -> void:
	if _body.is_in_group("players") and not _nearby_players.has(_body):
		_nearby_players.append(_body)


func _on_area_3d_body_exited(_body: Node3D) -> void:
	if _body.is_in_group("players"):
		_nearby_players.erase(_body)


func _is_local_player_nearby() -> bool:
	var local_player := _get_local_player()
	if not local_player:
		return false
	return _nearby_players.has(local_player)


func show_item() -> void:
	var camera_manager := get_node_or_null("/root/CameraManager")
	if not camera_manager:
		return

	var active_camera: Camera3D = camera_manager.get_active_camera()
	if not active_camera:
		return

	_is_showing_item = true

	# Bloquear movimento do player
	var player := _get_local_player()
	if player and player.has_method("set_movement_enabled"):
		player.set_movement_enabled(false)

	var showing_item_instance = showing_item_scene.instantiate()
	active_camera.add_child(showing_item_instance)

	# Posicionar à frente da câmera
	showing_item_instance.position = Vector3(0, 0, -5)

	showing_item_instance.set_static(is_static)
	showing_item_instance.set_description_value(descriptionValue)

	if model:
		showing_item_instance.mesh_instance.mesh = model

	# Passar referência do player e do interactable_item
	if player:
		showing_item_instance.set_meta("player_reference", player)
	showing_item_instance.set_meta("interactable_item", self)

	# Conectar ao sinal de quando o showing_item for destruído
	showing_item_instance.tree_exiting.connect(_on_showing_item_closed)


func _get_local_player() -> Node:
	var players := get_tree().get_nodes_in_group("players")
	for player in players:
		if not multiplayer.has_multiplayer_peer():
			return player
		if player.is_multiplayer_authority():
			return player
	return null


func _on_showing_item_closed() -> void:
	_is_showing_item = false


func collect(_player: Player) -> void:
	_player.add_item_to_inventory()