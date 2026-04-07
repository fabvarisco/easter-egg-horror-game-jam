extends Egg

@export var min_blink_interval: float = 3.0
@export var max_blink_interval: float = 8.0
@export var blink_duration: float = 0.15
@export var double_blink_chance: float = 0.3
@export var tracking_duration: float = 1.2
@export var tracking_speed: float = 5.0

@onready var _left_eye_mesh: MeshInstance3D = $EggModel/LeftEyeMesh
@onready var _right_eye_mesh: MeshInstance3D = $EggModel/RightEyeMesh
@onready var _detection_area: Area3D = $DetectionArea

var _blink_timer: float = 0.0
var _next_blink_time: float = 0.0
var _is_blinking: bool = false
var _is_tracking: bool = false
var _tracking_timer: float = 0.0

var _eyes_visible: bool = false
var _synced_rotation_y: float = 0.0
const SYNC_INTERVAL: float = 0.05
var _sync_timer: float = 0.0


func _ready() -> void:
	super._ready()
	is_monster = true
	_next_blink_time = randf_range(min_blink_interval, max_blink_interval)


func _process(delta: float) -> void:
	super._process(delta)

	if _was_picked_up:
		return

	# Em multiplayer, apenas o servidor controla a lógica
	if _is_multiplayer_active():
		if multiplayer.is_server():
			_process_server_logic(delta)
		else:
			_apply_synced_state(delta)
		return

	# Modo singleplayer - lógica normal
	_blink_timer += delta

	if _blink_timer >= _next_blink_time and not _is_blinking:
		_start_tracking()

	if _is_tracking:
		_track_player(delta)


func _process_server_logic(delta: float) -> void:
	_blink_timer += delta

	if _blink_timer >= _next_blink_time and not _is_blinking:
		_start_tracking()
		_sync_eye_state.rpc(true)

	if _is_tracking:
		_track_player(delta)
		_sync_timer += delta
		if _sync_timer >= SYNC_INTERVAL:
			_sync_timer = 0.0
			var rot_y: float = egg_model.rotation.y if egg_model else 0.0
			_sync_rotation.rpc(rot_y)


func _apply_synced_state(_delta: float) -> void:
	if egg_model and _is_tracking:
		egg_model.rotation.y = lerp_angle(egg_model.rotation.y, _synced_rotation_y, 0.3)


func _start_tracking() -> void:
	_is_blinking = true
	_is_tracking = true
	_tracking_timer = 0.0
	_set_eyes_on(true)


func _track_player(delta: float) -> void:
	_tracking_timer += delta
	_look_at_nearby_player_smooth(delta)

	if _tracking_timer >= tracking_duration:
		_end_tracking()


func _end_tracking() -> void:
	_is_tracking = false
	_set_eyes_on(false)

	if _is_multiplayer_active() and multiplayer.is_server():
		_sync_eye_state.rpc(false)

	if randf() < double_blink_chance:
		_do_double_blink()
	else:
		_reset_blink_timer()


func _do_double_blink() -> void:
	await get_tree().create_timer(blink_duration * 0.5).timeout
	_set_eyes_on(true)
	if _is_multiplayer_active() and multiplayer.is_server():
		_sync_eye_state.rpc(true)
	await get_tree().create_timer(blink_duration).timeout
	_set_eyes_on(false)
	if _is_multiplayer_active() and multiplayer.is_server():
		_sync_eye_state.rpc(false)
	_reset_blink_timer()


func _reset_blink_timer() -> void:
	_blink_timer = 0.0
	_next_blink_time = randf_range(min_blink_interval, max_blink_interval)
	_is_blinking = false


func _get_closest_player() -> Node3D:
	if not _detection_area:
		return null

	var bodies := _detection_area.get_overlapping_bodies()
	var closest_player: Node3D = null
	var closest_distance := INF

	for body in bodies:
		if body is CharacterBody3D:
			var distance := global_position.distance_to(body.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_player = body

	return closest_player


func _look_at_nearby_player_smooth(delta: float) -> void:
	var closest_player := _get_closest_player()
	if not closest_player:
		return

	var direction := closest_player.global_position - global_position
	direction.y = 0
	if direction.length_squared() > 0.001:
		var target_rotation := atan2(direction.x, direction.z)
		# Rotate the egg_model instead of root so eyes follow along
		if egg_model:
			egg_model.rotation.y = lerp_angle(egg_model.rotation.y, target_rotation, tracking_speed * delta)


func _set_eyes_on(on: bool) -> void:
	_eyes_visible = on
	if _left_eye_mesh:
		_left_eye_mesh.visible = on
	if _right_eye_mesh:
		_right_eye_mesh.visible = on


# ==========================================
# MULTIPLAYER SYNC
# ==========================================

@rpc("authority", "call_remote", "reliable")
func _sync_eye_state(eyes_on: bool) -> void:
	_eyes_visible = eyes_on
	_is_tracking = eyes_on
	_set_eyes_on(eyes_on)


@rpc("authority", "call_remote", "unreliable")
func _sync_rotation(rot_y: float) -> void:
	_synced_rotation_y = rot_y
