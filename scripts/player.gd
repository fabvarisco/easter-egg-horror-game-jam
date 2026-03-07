extends CharacterBody3D

const SPEED = 1.0
const ROTATION_SPEED = 8.0
#const SYNC_INTERVAL = 0.05  # 20 updates per second

@onready var camera: Camera3D = $Camera3D
@onready var flashlight: SpotLight3D = $SpotLight3D
@onready var vision_light: SpotLight3D = $VisionLight
#@onready var multiplayer_manager: Node = get_node("/root/MultiplayerManager")

#var _peer_id: int = 0
#var _is_local: bool = false
#var _sync_timer: float = 0.0

var _target_rotation: float = 0.0
var _camera_offset: Vector3
var _flashlight_on: bool = false

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
	# Salva offset inicial da câmera e remove ela como filha
	_camera_offset = camera.position
	camera.top_level = true  # Câmera não herda transform do pai

	# Começa com visão base ligada, lanterna desligada
	flashlight.visible = false
	vision_light.visible = true
	_flashlight_on = false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_flashlight"):
		_flashlight_on = not _flashlight_on
		flashlight.visible = _flashlight_on
		vision_light.visible = not _flashlight_on

func _physics_process(delta: float) -> void:
	# TODO: Multiplayer - descomentar quando implementar
	#if not _is_local:
	#	return

	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * delta

	# WASD movement (world-space for isometric)
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := Vector3(input_dir.x, 0, input_dir.y).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()

	# Rotate player to face mouse position
	_rotate_to_mouse(delta)

	# Smooth rotation interpolation
	rotation.y = lerp_angle(rotation.y, _target_rotation, ROTATION_SPEED * delta)

	# Update camera position (follows player but doesn't rotate)
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

	# Raycast to ground plane (y = player height)
	var plane := Plane(Vector3.UP, global_position.y)
	var intersection: Variant = plane.intersects_ray(ray_origin, ray_direction)

	if intersection:
		var look_pos: Vector3 = intersection
		var direction_to_mouse := look_pos - global_position

		# Only update target if mouse is far enough from player
		if direction_to_mouse.length() > 0.5:
			_target_rotation = atan2(direction_to_mouse.x, direction_to_mouse.z)

#func _send_position_sync() -> void:
#	multiplayer_manager.send_game_data({
#		"action": "sync_position",
#		"x": global_position.x,
#		"y": global_position.y,
#		"z": global_position.z,
#		"rot_y": rotation.y
#	})
