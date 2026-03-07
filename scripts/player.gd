extends CharacterBody3D

const WALK_SPEED: float = 3.0
const SPRINT_SPEED: float = 6.5
const ACCELERATION: float = 8.0
const DECELERATION: float = 10.0
const ROTATION_SPEED: float = 4.0
const STEERING_WALK: float = 50.0  # Rapidez para mudar direcao andando
const STEERING_SPRINT: float = 8.0  # Mais lento para mudar direcao correndo
const JUMP_VELOCITY: float = 4.5
#const SYNC_INTERVAL = 0.05  # 20 updates per second

# Stamina
const MAX_STAMINA:float = 100.0
const STAMINA_DRAIN_RATE:float = 25.0  # Por segundo enquanto corre
const STAMINA_REGEN_RATE:float = 15.0  # Por segundo enquanto nao corre
const MIN_STAMINA_TO_SPRINT:float = 10.0  # Minimo para comecar a correr

@onready var camera: Camera3D = $Camera3D
@onready var flashlight: SpotLight3D = $SpotLight3D
@onready var vision_light: SpotLight3D = $VisionLight
@onready var model: Node3D = $model
@onready var anim_player: AnimationPlayer = $model/AnimationPlayer
#@onready var multiplayer_manager: Node = get_node("/root/MultiplayerManager")

var _texture: Texture2D = preload("res://assets/godot_plush_albedo.png")

#var _peer_id: int = 0
#var _is_local: bool = false
#var _sync_timer: float = 0.0

var _target_rotation: float = 0.0
var _camera_offset: Vector3
var _flashlight_on: bool = false
var _current_speed: float = 0.0
var _stamina: float = MAX_STAMINA
var _is_sprinting: bool = false
var _move_direction: Vector3 = Vector3.ZERO  # Direcao atual do movimento

func _ready() -> void:
	# TODO: Multiplayer - descomentar quando implementar
	#_peer_id = get_meta("peer_id", 0)
	#_is_local = multiplayer_manager.is_local_player(_peer_id)
	#if not _is_local:
	#	camera.current = false
	#	set_process_input(false)
	#else:
	#	camera.current = true

	camera.current = true
	_camera_offset = camera.position
	camera.top_level = true

	flashlight.visible = false
	vision_light.visible = true
	_flashlight_on = false

	_apply_texture_to_model()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_flashlight"):
		_flashlight_on = not _flashlight_on
		flashlight.visible = _flashlight_on
		vision_light.visible = not _flashlight_on

func _physics_process(_delta: float) -> void:
	# TODO: Multiplayer - descomentar quando implementar
	#if not _is_local:
	#	return

	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * _delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# WASD movement
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := Vector3(input_dir.x, 0, input_dir.y).normalized()

	var wants_to_sprint := Input.is_action_pressed("sprint") and direction.length() > 0

	if wants_to_sprint and _stamina > MIN_STAMINA_TO_SPRINT:
		_is_sprinting = true
	elif _stamina <= 0 or not wants_to_sprint:
		_is_sprinting = false

	if _is_sprinting:
		_stamina = max(0, _stamina - STAMINA_DRAIN_RATE * _delta)
		if _stamina <= 0:
			_is_sprinting = false
	else:
		_stamina = min(MAX_STAMINA, _stamina + STAMINA_REGEN_RATE * _delta)

	var target_speed := SPRINT_SPEED if _is_sprinting else WALK_SPEED
	var steering := STEERING_SPRINT if _is_sprinting else STEERING_WALK

	if direction:

		_move_direction = _move_direction.lerp(direction, steering * _delta)
		_move_direction = _move_direction.normalized() if _move_direction.length() > 0.01 else Vector3.ZERO

		_current_speed = move_toward(_current_speed, target_speed, ACCELERATION * _delta)
		velocity.x = _move_direction.x * _current_speed
		velocity.z = _move_direction.z * _current_speed
	else:
		_current_speed = move_toward(_current_speed, 0, DECELERATION * _delta)
		velocity.x = move_toward(velocity.x, 0, DECELERATION * _delta)
		velocity.z = move_toward(velocity.z, 0, DECELERATION * _delta)
		if _current_speed < 0.1:
			_move_direction = Vector3.ZERO

	var horizontal_velocity := Vector2(velocity.x, velocity.z)
	if horizontal_velocity.length() > target_speed:
		horizontal_velocity = horizontal_velocity.normalized() * target_speed
		velocity.x = horizontal_velocity.x
		velocity.z = horizontal_velocity.y

	move_and_slide()

	_update_animation()

	_rotate_to_mouse(_delta)

	rotation.y = lerp_angle(rotation.y, _target_rotation, ROTATION_SPEED * _delta)

	camera.global_position = global_position + _camera_offset

	# TODO: Multiplayer - descomentar quando implementar
	#_sync_timer += delta
	#if _sync_timer >= SYNC_INTERVAL:
	#	_sync_timer = 0.0
	#	_send_position_sync()

func _rotate_to_mouse(_delta: float) -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_direction := camera.project_ray_normal(mouse_pos)

	var plane := Plane(Vector3.UP, global_position.y)
	var intersection: Variant = plane.intersects_ray(ray_origin, ray_direction)

	if intersection:
		var look_pos: Vector3 = intersection
		var direction_to_mouse := look_pos - global_position

		if direction_to_mouse.length() > 0.5:
			_target_rotation = atan2(direction_to_mouse.x, direction_to_mouse.z) + PI

#func _send_position_sync() -> void:
#	multiplayer_manager.send_game_data({
#		"action": "sync_position",
#		"x": global_position.x,
#		"y": global_position.y,
#		"z": global_position.z,
#		"rot_y": rotation.y
#	})

func _apply_texture_to_model() -> void:
	if not model or not _texture:
		return

	var material := StandardMaterial3D.new()
	material.albedo_texture = _texture

	for child in model.get_children():
		_apply_material_recursive(child, material)

func _apply_material_recursive(node: Node, material: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		var mesh_instance: MeshInstance3D = node
		for i in mesh_instance.get_surface_override_material_count():
			mesh_instance.set_surface_override_material(i, material)

	for child in node.get_children():
		_apply_material_recursive(child, material)

func _update_animation() -> void:
	if not anim_player:
		return

	var anim_name: String

	if not is_on_floor():
		anim_name = "jump"
	elif _current_speed > 0.1:
		if _is_sprinting:
			anim_name = "run"
		else:
			anim_name = "walk"
	else:
		anim_name = "idle"

	if anim_player.has_animation(anim_name) and anim_player.current_animation != anim_name:
		anim_player.play(anim_name)

func get_stamina() -> float:
	return _stamina

func get_stamina_percent() -> float:
	return _stamina / MAX_STAMINA

func is_sprinting() -> bool:
	return _is_sprinting
