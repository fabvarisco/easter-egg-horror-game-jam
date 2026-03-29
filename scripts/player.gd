class_name Player 
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

# Sound radius constants
const SOUND_RADIUS_IDLE: float = 2.0
const SOUND_RADIUS_WALK_SLOW: float = 4.0
const SOUND_RADIUS_WALK: float = 5.0
const SOUND_RADIUS_SPRINT: float = 10.0
const SOUND_RADIUS_VOICE: float = 4.0
const SOUND_RADIUS_LERP_SPEED: float = 5.0
const SOUND_RADIUS_DECAY: float = 3.0

# Animation names
const ANIM_PREFIX := "CharacterArmature|CharacterArmature|CharacterArmature|"
const ANIM_IDLE := ANIM_PREFIX + "Idle"
const ANIM_WALK := ANIM_PREFIX + "Walk"
const ANIM_RUN := ANIM_PREFIX + "Run"
const ANIM_JUMP := ANIM_PREFIX + "Jump"
const ANIM_IDLE_HOLDING := ANIM_PREFIX + "Idle_Holding"
const ANIM_WALK_HOLDING := ANIM_PREFIX + "Walk_Holding"
const ANIM_RUN_HOLDING := ANIM_PREFIX + "Run_Holding"

@onready var flashlight: SpotLight3D = $SpotLight3D
@onready var vision_light: SpotLight3D = $VisionLight
@onready var model: Node3D = $model
@onready var anim_player: AnimationPlayer = $model/AnimationPlayer
@onready var sound_area_3d: Area3D = $SoundArea3D


var _texture: Texture2D = preload("res://assets/models/PlayerGenericModel_Sushi_Atlas.png")

var _sync_timer: float = 0.0

var _target_rotation: float = 0.0
var _flashlight_on: bool = false
var _current_speed: float = 0.0
var _stamina: float = MAX_STAMINA
var _is_sprinting: bool = false
var _is_walking: bool = false
var _is_speaking: bool = false
var _sound_radius_current: float = SOUND_RADIUS_IDLE
var _sound_radius_target: float = SOUND_RADIUS_IDLE
var _move_direction: Vector3 = Vector3.ZERO 
var _carried_egg: Node3D = null
var _nearby_egg: Node3D = null
var _nearby_pedestal: Area3D = null
var _nearby_car: Area3D = null
var _is_dead: bool = false
var _is_on_floor_synced: bool = true
var _movement_enabled: bool = true  

signal player_died

func _ready() -> void:
	if not _has_authority():
		set_process_input(false)

	flashlight.visible = false
	vision_light.visible = true
	_flashlight_on = false

	_apply_texture_to_model()

	if not visible:
		set_physics_process(false)
		set_process_input(false)

	# Conectar detecção de voz para aumentar raio de som quando fala
	if _has_authority():
		_connect_voice_detection()

func _input(event: InputEvent) -> void:
	if not _has_authority():
		return

	# Bloquear inputs se movimento desabilitado
	if not _movement_enabled:
		return

	if event.is_action_pressed("toggle_flashlight") and not is_carrying_egg():
		_flashlight_on = not _flashlight_on
		flashlight.visible = _flashlight_on
		vision_light.visible = not _flashlight_on

	if event.is_action_pressed("interact"):
		if _nearby_pedestal:
			_interact_with_pedestal()
		elif _nearby_car:
			_interact_with_car()
		elif is_carrying_egg():
			_drop_egg()
		elif _nearby_egg:
			_pickup_egg(_nearby_egg)

func _physics_process(_delta: float) -> void:
	if not is_inside_tree():
		return

	if not _has_authority():
		_update_animation()
		_update_carried_egg()  # Atualizar ovo mesmo em players remotos
		return

	# Se movimento desabilitado, parar completamente
	if not _movement_enabled:
		velocity = Vector3.ZERO
		_current_speed = 0.0
		_move_direction = Vector3.ZERO
		_update_animation()
		return

	# Gravity
	if not is_on_floor():
		velocity += get_gravity() * _delta

	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# WASD movement relative to camera
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction := _get_camera_relative_direction(input_dir)

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

	_detect_nearby_eggs()
	_detect_nearby_pedestals()
	_detect_nearby_car()
	_update_carried_egg()

	_sync_timer += _delta
	if _sync_timer >= SYNC_INTERVAL:
		_sync_timer = 0.0
		_send_position_sync()

	# Update sound radius based on movement and voice
	_controll_sound_value(_delta)


func _get_camera_relative_direction(input_dir: Vector2) -> Vector3:
	if input_dir.length() < 0.01:
		return Vector3.ZERO

	var camera_manager := get_node_or_null("/root/CameraManager")
	if not camera_manager:
		return Vector3(input_dir.x, 0, input_dir.y).normalized()

	var camera = camera_manager.get_active_camera()
	if not is_instance_valid(camera):
		return Vector3(input_dir.x, 0, input_dir.y).normalized()

	# Get camera's forward and right vectors projected onto XZ plane
	var cam_basis: Basis = camera.global_transform.basis
	var cam_forward: Vector3 = -cam_basis.z
	var cam_right: Vector3 = cam_basis.x

	# Project onto horizontal plane and normalize
	cam_forward.y = 0
	cam_right.y = 0
	cam_forward = cam_forward.normalized()
	cam_right = cam_right.normalized()

	# Calculate direction relative to camera
	var direction: Vector3 = (cam_forward * -input_dir.y + cam_right * input_dir.x).normalized()
	return direction


func _rotate_to_mouse(_delta: float) -> void:
	var camera_manager := get_node_or_null("/root/CameraManager")
	if not camera_manager:
		return

	var camera = camera_manager.get_active_camera()
	if not is_instance_valid(camera):
		return

	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_direction: Vector3 = camera.project_ray_normal(mouse_pos)

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
	_sync_position.rpc(global_position, rotation.y, _current_speed, _is_sprinting, is_on_floor())


func _has_authority() -> bool:
	# In singleplayer (no multiplayer peer), we always have authority
	if not multiplayer.has_multiplayer_peer():
		return true
	return is_multiplayer_authority()


func _is_multiplayer_connected() -> bool:
	if not is_inside_tree():
		return false
	if not multiplayer.has_multiplayer_peer():
		return false
	if not is_instance_valid(multiplayer.multiplayer_peer):
		return false
	return multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

@rpc("authority", "call_remote", "unreliable")
func _sync_position(pos: Vector3, rot_y: float, speed: float, sprinting: bool, on_floor: bool = true) -> void:
	global_position = pos
	rotation.y = rot_y
	_current_speed = speed
	_is_sprinting = sprinting
	_is_on_floor_synced = on_floor


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
	var is_holding := is_carrying_egg()

	var on_floor: bool = is_on_floor() if _has_authority() else _is_on_floor_synced

	if not on_floor:
		anim_name = ANIM_JUMP
	elif _current_speed > 0.1:
		if _is_sprinting:
			anim_name = ANIM_RUN_HOLDING if is_holding else ANIM_RUN
		else:
			anim_name = ANIM_WALK_HOLDING if is_holding else ANIM_WALK
	else:
		anim_name = ANIM_IDLE_HOLDING if is_holding else ANIM_IDLE

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


func _detect_nearby_car() -> void:
	_nearby_car = null
	var cars := get_tree().get_nodes_in_group("car_delivery")
	for car in cars:
		if global_position.distance_to(car.global_position) < INTERACT_DISTANCE + 1.5:
			_nearby_car = car
			break


func _interact_with_car() -> void:
	var game_ctrl := get_tree().current_scene
	if not game_ctrl:
		return

	var peer_id: int = get_meta("peer_id", 1)

	if is_carrying_egg():
		# Deliver egg
		if game_ctrl.has_method("deliver_egg"):
			game_ctrl.deliver_egg(self)
	else:
		# Try to enter car
		if game_ctrl.has_method("player_enter_car"):
			game_ctrl.player_enter_car(peer_id)


func _clear_carried_egg() -> void:
	# Remove egg without dropping in world (for delivery)
	if _carried_egg:
		remove_child(_carried_egg)
		_carried_egg = null

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

	if is_inside_tree() and get_parent():
		var spawn_pos := global_position
		spawn_pos.y = 0.5
		var egg_scene := preload("res://scenes/egg.tscn")
		var egg := egg_scene.instantiate()
		egg.is_monster = false
		get_parent().add_child(egg)
		egg.global_position = spawn_pos

	remove_from_group("players")
	remove_from_group("player")

func is_dead() -> bool:
	return _is_dead

func shake_camera(intensity: float, duration: float) -> void:
	var camera_manager := get_node_or_null("/root/CameraManager")
	if camera_manager:
		camera_manager.shake_camera(intensity, duration)

func add_item_to_inventory() -> void:
	pass

func set_movement_enabled(enabled: bool) -> void:
	_movement_enabled = enabled
	if not enabled:
		velocity = Vector3.ZERO
		_current_speed = 0.0
		_move_direction = Vector3.ZERO


func _connect_voice_detection() -> void:
	"""Conecta com VoiceManager para detectar quando jogador está falando"""
	var voice_manager := get_node_or_null("/root/VoiceManager")
	if not voice_manager:
		return

	if voice_manager.has_signal("player_speaking_changed"):
		voice_manager.player_speaking_changed.connect(_on_player_speaking_changed)


func _on_player_speaking_changed(peer_id: int, is_speaking: bool) -> void:
	"""Callback quando detecção de fala muda (qualquer jogador)"""
	var my_peer_id: int = get_meta("peer_id", 1)

	if peer_id == my_peer_id:
		_is_speaking = is_speaking


func get_sound_radius() -> float:
	"""Retorna o raio de som atual (útil para inimigos e outras mecânicas)"""
	return _sound_radius_current


func is_making_noise() -> bool:
	"""Verifica se está fazendo barulho significativo (correndo ou falando)"""
	return _is_sprinting or _is_speaking or _current_speed > WALK_SPEED


func _controll_sound_value(_delta: float) -> void:
	"""
	Controla o raio de som do jogador baseado em suas ações.
	O raio aumenta quando: corre, anda, fala no mic.
	O raio diminui naturalmente até o valor mínimo (idle).
	"""
	var base_radius: float = SOUND_RADIUS_IDLE

	if _current_speed > 0.1:
		if _is_sprinting:
			base_radius = SOUND_RADIUS_SPRINT
		elif _is_walking:
			base_radius = SOUND_RADIUS_WALK_SLOW
		else:
			base_radius = SOUND_RADIUS_WALK

	var voice_bonus: float = SOUND_RADIUS_VOICE if _is_speaking else 0.0
	_sound_radius_target = base_radius + voice_bonus

	_sound_radius_current = lerp(_sound_radius_current, _sound_radius_target, SOUND_RADIUS_LERP_SPEED * _delta)

	if _sound_radius_current > _sound_radius_target:
		_sound_radius_current = move_toward(_sound_radius_current, _sound_radius_target, SOUND_RADIUS_DECAY * _delta)

	sound_area_3d.scale = Vector3.ONE * _sound_radius_current

	if _has_authority() and Engine.get_frames_drawn() % 60 == 0:  # A cada 60 frames
		_debug_print_sound_radius()


func _debug_print_sound_radius() -> void:
	"""Debug: mostra raio atual no console"""
	pass
