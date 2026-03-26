extends Egg


@export var min_blink_interval: float = 3.0  
@export var max_blink_interval: float = 8.0  
@export var blink_duration: float = 0.15   
@export var double_blink_chance: float = 0.3 
@export var eye_color: Color = Color(1.0, 0.1, 0.1, 1.0) 
@export var eye_intensity: float = 3.0

var _left_eye: OmniLight3D = null
var _right_eye: OmniLight3D = null
var _blink_timer: float = 0.0
var _next_blink_time: float = 0.0
var _is_blinking: bool = false

func _ready() -> void:
	super._ready()

	is_monster = true

	_create_eyes()

	_next_blink_time = randf_range(min_blink_interval, max_blink_interval)


func _create_eyes() -> void:
	var left_eye_pos := Vector3(-0.08, 0.15, 0.12)
	var right_eye_pos := Vector3(0.08, 0.15, 0.12)

	_left_eye = OmniLight3D.new()
	_left_eye.name = "LeftEye"
	_left_eye.position = left_eye_pos
	_left_eye.light_color = eye_color
	_left_eye.light_energy = 0.0  
	_left_eye.omni_range = 0.5
	_left_eye.omni_attenuation = 1.0
	add_child(_left_eye)

	_right_eye = OmniLight3D.new()
	_right_eye.name = "RightEye"
	_right_eye.position = right_eye_pos
	_right_eye.light_color = eye_color
	_right_eye.light_energy = 0.0  
	_right_eye.omni_range = 0.5
	_right_eye.omni_attenuation = 1.0
	add_child(_right_eye)


func _process(delta: float) -> void:
	if _was_picked_up:
		return

	_blink_timer += delta

	if _blink_timer >= _next_blink_time and not _is_blinking:
		_do_blink()


func _do_blink() -> void:
	_is_blinking = true

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


func _set_eyes_on(_on: bool) -> void:
	var target_energy := eye_intensity if _on else 0.0

	if _left_eye:
		_left_eye.light_energy = target_energy
	if _right_eye:
		_right_eye.light_energy = target_energy
