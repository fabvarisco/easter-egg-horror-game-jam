extends CharacterBody3D

const SLOW_WALK_SPEED: float = 1.5
const WALK_SPEED: float = 3.0
const SPRINT_SPEED: float = 6.5
const ACCELERATION: float = 8.0
const DECELERATION: float = 10.0
const ROTATION_SPEED: float = 4.0
const STEERING_WALK: float = 50.0
const STEERING_SPRINT: float = 8.0
const JUMP_VELOCITY: float = 4.5
const INTERACT_DISTANCE: float = 2.0
const SYNC_INTERVAL: float = 0.05

# Stamina
const MAX_STAMINA: float = 100.0
const STAMINA_DRAIN_RATE: float = 25.0
const STAMINA_REGEN_RATE: float = 8.0  # Slower default recovery
const STAMINA_REGEN_RATE_WALKING: float = 20.0  # Faster recovery while walking
const MIN_STAMINA_TO_SPRINT: float = 10.0  

@onready var camera: Camera3D = $Camera3D
@onready var flashlight: SpotLight3D = $SpotLight3D
@onready var vision_light: SpotLight3D = $VisionLight
@onready var model: Node3D = $model
@onready var anim_player: AnimationPlayer = $model/AnimationPlayer

var _texture: Texture2D = preload("res://assets/godot_plush_albedo.png")

var _sync_timer: float = 0.0

var _target_rotation: float = 0.0
var _camera_offset: Vector3
var _flashlight_on: bool = false
var _current_speed: float = 0.0
var _stamina: float = MAX_STAMINA
var _is_sprinting: bool = false
var _is_walking: bool = false
var _move_direction: Vector3 = Vector3.ZERO 
var _carried_egg: Node3D = null
var _nearby_egg: Node3D = null
var _nearby_pedestal: Area3D = null
var _is_dead: bool = false
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_timer: float = 0.0

signal player_died

func _ready() -> void:
	_camera_offset = camera.position
	camera.top_level = true

	if not _has_authority():
		camera.current = false
		set_process_input(false)
	else:
		camera.current = true

	flashlight.visible = false
	vision_light.visible = true
	_flashlight_on = false

	_apply_texture_to_model()

	if not visible:
		set_physics_process(false)
		set_process_input(false)

func _input(event: InputEvent) -> void:
	if not _has_authority():
		return

	if event.is_action_pressed("toggle_flashlight") and not is_carrying_egg():
		_flashlight_on = not _flashlight_on
		flashlight.visible = _flashlight_on
		vision_light.visible = not _flashlight_on

	if event.is_action_pressed("interact"):
		if _nearby_pedestal:
			_interact_with_pedestal()
		elif is_carrying_egg():
			_drop_egg()
		elif _nearby_egg:
			_pickup_egg(_nearby_egg)

func _physics_process(_delta: float) -> void:
	if not is_inside_tree():
		return

	if not _has_authority():
		_update_animation()
		return

	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * _delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# WASD movement
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := Vector3(input_dir.x, 0, input_dir.y).normalized()

	var wants_to_sprint := Input.is_action_pressed("sprint") and direction.length() > 0 and not is_carrying_egg()
	var wants_to_walk := Input.is_action_pressed("walk") and direction.length() > 0

	# Walking (CTRL) takes priority - can't sprint while walking
	if wants_to_walk:
		_is_walking = true
		_is_sprinting = false
	else:
		_is_walking = false
		if wants_to_sprint and _stamina > MIN_STAMINA_TO_SPRINT:
			_is_sprinting = true
		elif _stamina <= 0 or not wants_to_sprint:
			_is_sprinting = false

	# Stamina management
	if _is_sprinting:
		_stamina = max(0, _stamina - STAMINA_DRAIN_RATE * _delta)
		if _stamina <= 0:
			_is_sprinting = false
	elif _is_walking:
		# Faster stamina recovery while walking
		_stamina = min(MAX_STAMINA, _stamina + STAMINA_REGEN_RATE_WALKING * _delta)
	else:
		# Normal (slower) stamina recovery
		_stamina = min(MAX_STAMINA, _stamina + STAMINA_REGEN_RATE * _delta)

	# Determine target speed
	var target_speed: float
	if _is_sprinting:
		target_speed = SPRINT_SPEED
	elif _is_walking:
		target_speed = SLOW_WALK_SPEED
	else:
		target_speed = WALK_SPEED

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

	_update_camera(_delta)

	_detect_nearby_eggs()
	_detect_nearby_pedestals()
	_update_carried_egg()

	_sync_timer += _delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer = 0.0
		_send_position_sync()

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

func _send_position_sync() -> void:
	if not _is_multiplayer_connected():
		return
	_sync_position.rpc(global_position, rotation.y, _current_speed, _is_sprinting)


func _has_authority() -> bool:
	# In singleplayer (no multiplayer peer), we always have authority
	if not multiplayer.has_multiplayer_peer():
		return true
	return is_multiplayer_authority()


func _is_multiplayer_connected() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return false
	if not is_instance_valid(multiplayer.multiplayer_peer):
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

@rpc("authority", "call_remote", "unreliable")
func _sync_position(pos: Vector3, rot_y: float, speed: float, sprinting: bool) -> void:
	global_position = pos
	rotation.y = rot_y
	_current_speed = speed
	_is_sprinting = sprinting


func _sync_pickup_egg(egg_name: String) -> void:
	if not _is_multiplayer_connected():
		return

	var host_manager := get_node_or_null("/root/HostManager")
	if host_manager:
		var player_id := int(name)
		host_manager.pickup_egg(egg_name, player_id)


func _sync_drop_egg(egg_name: String, drop_pos: Vector3) -> void:
	if not _is_multiplayer_connected():
		return

	var host_manager := get_node_or_null("/root/HostManager")
	if host_manager:
		var player_id := int(name)
		host_manager.drop_egg(egg_name, player_id, drop_pos)


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


func is_walking() -> bool:
	return _is_walking

func is_carrying_egg() -> bool:
	return _carried_egg != null

func get_carried_egg() -> Node3D:
	return _carried_egg

func _detect_nearby_eggs() -> void:
	_nearby_egg = null

	var eggs := get_tree().get_nodes_in_group("eggs")
	var closest_distance := INTERACT_DISTANCE

	for egg in eggs:
		if egg == _carried_egg:
			continue

		var distance := global_position.distance_to(egg.global_position)
		if distance < closest_distance:
			closest_distance = distance
			_nearby_egg = egg


func _detect_nearby_pedestals() -> void:
	_nearby_pedestal = null

	var pedestals := get_tree().get_nodes_in_group("start_game_pedestal")
	var closest_distance := INTERACT_DISTANCE + 1.0  # Slightly larger range for pedestal

	for pedestal in pedestals:
		var distance := global_position.distance_to(pedestal.global_position)
		if distance < closest_distance:
			closest_distance = distance
			_nearby_pedestal = pedestal


func _interact_with_pedestal() -> void:
	if not _nearby_pedestal:
		return

	var peer_id: int = get_meta("peer_id", 1)
	_nearby_pedestal.on_interact(peer_id)

func _pickup_egg(egg: Node3D) -> void:
	if _carried_egg:
		return

	_carried_egg = egg

	if egg.has_method("on_picked_up"):
		egg.on_picked_up()

	if _flashlight_on:
		_flashlight_on = false
		flashlight.visible = false
		vision_light.visible = true

	var egg_parent := egg.get_parent()
	if egg_parent:
		egg_parent.remove_child(egg)
	add_child(egg)

	# Sincronizar em multiplayer
	_sync_pickup_egg(egg.name)

func _drop_egg() -> void:
	if not _carried_egg:
		return

	var egg := _carried_egg
	var egg_name := egg.name
	_carried_egg = null

	remove_child(egg)
	get_parent().add_child(egg)

	var drop_offset := -global_transform.basis.z * 1.0
	egg.global_position = global_position + drop_offset
	egg.global_position.y = 0.5

	# Sincronizar em multiplayer
	_sync_drop_egg(egg_name, egg.global_position)

func _update_carried_egg() -> void:
	if not _carried_egg:
		return

	_carried_egg.position = Vector3(0, 0.8, -0.5)
	_carried_egg.rotation = Vector3.ZERO
	_carried_egg.scale = Vector3(1, 1, 1)

func die() -> void:
	if _is_dead:
		return

	_is_dead = true

	set_physics_process(false)
	set_process_input(false)

	if _carried_egg:
		_drop_egg()

	_turn_into_egg()
	player_died.emit()

func _turn_into_egg() -> void:
	if model:
		model.visible = false
	if flashlight:
		flashlight.visible = false
	if vision_light:
		vision_light.visible = false

	if is_inside_tree():
		var egg_scene := preload("res://scenes/egg.tscn")
		var egg := egg_scene.instantiate()
		egg.is_monster = false
		egg.global_position = global_position
		egg.global_position.y = 0.5
		get_parent().add_child(egg)

	remove_from_group("players")
	remove_from_group("player")

func is_dead() -> bool:
	return _is_dead

func shake_camera(intensity: float, duration: float) -> void:
	_shake_intensity = intensity
	_shake_duration = duration
	_shake_timer = 0.0

func _update_camera(_delta: float) -> void:
	var shake_offset := Vector3.ZERO

	if _shake_timer < _shake_duration:
		_shake_timer += _delta
		var shake_progress := _shake_timer / _shake_duration
		var current_intensity := _shake_intensity * (1.0 - shake_progress)

		shake_offset = Vector3(
			randf_range(-current_intensity, current_intensity),
			randf_range(-current_intensity, current_intensity),
			randf_range(-current_intensity, current_intensity)
		)

	camera.global_position = global_position + _camera_offset + shake_offset  
