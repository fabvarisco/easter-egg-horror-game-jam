extends Node3D
class_name InteractableItem

var _nearby_players: Array = []
var _is_showing_item: bool = false
@export var descriptionValue: String = ""
@export var is_static: bool = false

# Animation settings
@export_group("Animation")
@export var enable_rotation: bool = true
@export var rotation_speed: float = 0.1  
@export var enable_floating: bool = true
@export var float_amplitude: float = .5
@export var float_speed: float = 0.3
@export var float_lerp_speed: float = 3.0

const FLASHLIGHT_CHECK_INTERVAL: float = 0.1

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var showing_item_scene = preload("res://scenes/interactable_items/showing_item.tscn")
var _time: float = 0.0
var _initial_y: float = 2.0
var _target_y: float = 0.0
var _flashlight_check_timer: float = 0.0
var _is_illuminated: bool = false

func _ready() -> void:
	add_to_group("interactable_items")
	set_outline_active(false)
	_initial_y = position.y + 1.0

func _process(delta: float) -> void:
	_flashlight_check_timer += delta
	if _flashlight_check_timer >= FLASHLIGHT_CHECK_INTERVAL:
		_flashlight_check_timer = 0.0
		var illuminated := _is_illuminated_by_flashlight()
		if illuminated != _is_illuminated:
			_is_illuminated = illuminated
			set_outline_active(illuminated)


func _physics_process(delta: float) -> void:
	_time += delta

	if enable_rotation:
		rotation.y += delta * rotation_speed * TAU  # TAU = 2π

	if enable_floating:
		var float_offset := sin(_time * float_speed * TAU) * float_amplitude
		_target_y = _initial_y + float_offset
		position.y = lerp(position.y, _target_y, delta * float_lerp_speed)

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

	showing_item_instance.mesh_instance.mesh = mesh_instance.mesh

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


func _is_illuminated_by_flashlight() -> bool:
	var players := get_tree().get_nodes_in_group("players")

	for player in players:
		if not is_instance_valid(player):
			continue

		var flashlight: SpotLight3D = player.get_node_or_null("SpotLight3D")
		if not flashlight or not flashlight.visible:
			continue

		var light_pos: Vector3 = flashlight.global_position
		var light_dir: Vector3 = -flashlight.global_transform.basis.z
		var light_range: float = flashlight.spot_range
		var light_angle: float = deg_to_rad(flashlight.spot_angle)

		var to_obj: Vector3 = global_position - light_pos
		var distance: float = to_obj.length()

		if distance > light_range:
			continue

		var angle_to_obj: float = light_dir.angle_to(to_obj.normalized())
		if angle_to_obj <= light_angle:
			return true

	return false


func set_outline_active(active: bool) -> void:
	if not mesh_instance:
		return

	if active:
		if mesh_instance.material_overlay == null:
			var outline_shader := load("res://shaders/enhanced_outline.gdshader")
			var material := ShaderMaterial.new()
			material.shader = outline_shader
			material.set_shader_parameter("outline_color", Color(0, 1, 0.2, 1))
			material.set_shader_parameter("outline_width", 0.15)
			material.set_shader_parameter("pulse_speed", 2.0)
			material.set_shader_parameter("pulse_amount", 0.3)
			material.set_shader_parameter("glow_intensity", 8.0)
			material.set_shader_parameter("enable_pulse", true)
			material.render_priority = 1
			mesh_instance.material_overlay = material
	else:
		mesh_instance.material_overlay = null


func collect(_player: Player) -> void:
	_player.add_item_to_inventory()
