extends Egg


@export var min_blink_interval: float = 3.0
@export var max_blink_interval: float = 8.0
@export var blink_duration: float = 0.15
@export var double_blink_chance: float = 0.3
@export var tracking_duration: float = 1.2
@export var tracking_speed: float = 5.0

@onready var _left_eye_mesh: MeshInstance3D = $LeftEyeMesh
@onready var _right_eye_mesh: MeshInstance3D = $RightEyeMesh
@onready var _detection_area: Area3D = $DetectionArea

var _blink_timer: float = 0.0
var _next_blink_time: float = 0.0
var _is_blinking: bool = false
var _is_tracking: bool = false
var _tracking_timer: float = 0.0


func _ready() -> void:
	super._ready()
	is_monster = true
	_next_blink_time = randf_range(min_blink_interval, max_blink_interval)


func _process(delta: float) -> void:
	super._process(delta)

	if _was_picked_up:
		return

	_blink_timer += delta

	if _blink_timer >= _next_blink_time and not _is_blinking:
		_start_tracking()

	if _is_tracking:
		_track_player(delta)


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

	if randf() < double_blink_chance:
		_do_double_blink()
	else:
		_reset_blink_timer()


func _do_double_blink() -> void:
	await get_tree().create_timer(blink_duration * 0.5).timeout
	_set_eyes_on(true)
	await get_tree().create_timer(blink_duration).timeout
	_set_eyes_on(false)
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
		rotation.y = lerp_angle(rotation.y, target_rotation, tracking_speed * delta)


func _set_eyes_on(on: bool) -> void:
	if _left_eye_mesh:
		_left_eye_mesh.visible = on
	if _right_eye_mesh:
		_right_eye_mesh.visible = on
