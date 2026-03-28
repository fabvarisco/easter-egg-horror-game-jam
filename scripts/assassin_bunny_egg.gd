extends Egg


@export var min_blink_interval: float = 3.0
@export var max_blink_interval: float = 8.0
@export var blink_duration: float = 0.15
@export var double_blink_chance: float = 0.3

@onready var _left_eye_mesh: MeshInstance3D = $LeftEyeMesh
@onready var _right_eye_mesh: MeshInstance3D = $RightEyeMesh
@onready var _detection_area: Area3D = $DetectionArea

var _blink_timer: float = 0.0
var _next_blink_time: float = 0.0
var _is_blinking: bool = false


func _ready() -> void:
	super._ready()
	is_monster = true
	_next_blink_time = randf_range(min_blink_interval, max_blink_interval)


func _process(delta: float) -> void:
	if _was_picked_up:
		return

	_blink_timer += delta

	if _blink_timer >= _next_blink_time and not _is_blinking:
		_do_blink()


func _do_blink() -> void:
	_is_blinking = true

	_look_at_nearby_player()
	_set_eyes_on(true)

	await get_tree().create_timer(blink_duration).timeout

	_set_eyes_on(false)

	if randf() < double_blink_chance:
		await get_tree().create_timer(blink_duration * 0.5).timeout
		_set_eyes_on(true)
		await get_tree().create_timer(blink_duration).timeout
		_set_eyes_on(false)

	_blink_timer = 0.0
	_next_blink_time = randf_range(min_blink_interval, max_blink_interval)
	_is_blinking = false


func _look_at_nearby_player() -> void:
	if not _detection_area:
		return

	var bodies := _detection_area.get_overlapping_bodies()
	var closest_player: Node3D = null
	var closest_distance := INF

	for body in bodies:
		if body is CharacterBody3D:
			var distance := global_position.distance_to(body.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_player = body

	if closest_player:
		var direction := closest_player.global_position - global_position
		direction.y = 0
		if direction.length_squared() > 0.001:
			rotation.y = atan2(direction.x, direction.z)


func _set_eyes_on(on: bool) -> void:
	if _left_eye_mesh:
		_left_eye_mesh.visible = on
	if _right_eye_mesh:
		_right_eye_mesh.visible = on
