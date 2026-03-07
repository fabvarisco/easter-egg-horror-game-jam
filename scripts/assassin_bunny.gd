extends Node3D

enum State { DORMANT, WATCHING, APPROACHING, KILLING }

const SPAWN_DISTANCE: float = 25.0  
const WATCH_DISTANCE: float = 20.0  
const APPROACH_DISTANCES: Array[float] = [15.0, 8.0, 3.0]  
const DETECTION_RANGE: float = 30.0  
const APPROACH_SPEED: float = 15.0
const BLINK_INTERVAL: float = 2.0 
const BLINK_DURATION: float = 0.15 

@onready var model: Node3D = $model
@onready var raycast: RayCast3D = $RayCast3D
@onready var left_eye: OmniLight3D = $LeftEye
@onready var right_eye: OmniLight3D = $RightEye

var _state: State = State.DORMANT
var _target_player: Node3D = null
var _approach_count: int = 0 
var _blink_timer: float = 0.0
var _is_blinking: bool = false
var _blink_phase_timer: float = 0.0

signal player_killed(player: Node3D)

func _ready() -> void:
	visible = false
	set_physics_process(false)

	if model:
		model.visible = false

func activate() -> void:
	"""Ativa o assassin bunny - chamado quando egg monster e tocado"""
	if _state != State.DORMANT:
		return

	_state = State.WATCHING
	visible = true
	set_physics_process(true)

	_find_target_player()
	if _target_player:
		_spawn_at_distance(SPAWN_DISTANCE)

func _physics_process(delta: float) -> void:
	match _state:
		State.WATCHING:
			_process_watching(delta)
		State.APPROACHING:
			_process_approaching(delta)
		State.KILLING:
			_process_killing(delta)

	_update_eyes(delta)
	_look_at_player()

func _process_watching(_delta: float) -> void:
	_find_target_player()

	if not _target_player:
		return

	_update_raycast_target()

	if raycast.is_colliding():
		var collider := raycast.get_collider()
		if collider == _target_player or collider.get_parent() == _target_player:
			_start_approach()

func _process_approaching(_delta: float) -> void:
	pass

func _process_killing(_delta: float) -> void:
	pass

func _start_approach() -> void:
	if _approach_count >= 3:
		_kill_player()
		return

	_state = State.APPROACHING

	var target_distance: float = APPROACH_DISTANCES[_approach_count]
	_spawn_at_distance(target_distance)

	_approach_count += 1

	_state = State.WATCHING

	if _approach_count >= 3:
		await get_tree().create_timer(0.5).timeout
		_kill_player()

func _kill_player() -> void:
	_state = State.KILLING

	if _target_player and _target_player.has_method("die"):
		_target_player.die()

	player_killed.emit(_target_player)

	if model:
		model.visible = true

func _find_target_player() -> void:
	var players := get_tree().get_nodes_in_group("players")

	if players.is_empty():
		var player := get_tree().get_first_node_in_group("player")
		if player:
			_target_player = player
		return

	# Encontra jogador mais proximo
	var closest_distance := INF
	for player in players:
		var distance := global_position.distance_to(player.global_position)
		if distance < closest_distance:
			closest_distance = distance
			_target_player = player

func _spawn_at_distance(distance: float) -> void:
	if not _target_player:
		return

	var angle := randf() * TAU
	var offset := Vector3(cos(angle), 0, sin(angle)) * distance

	global_position = _target_player.global_position + offset
	global_position.y = 0  

func _update_raycast_target() -> void:
	if not _target_player:
		return

	var direction := (_target_player.global_position - global_position).normalized()
	raycast.target_position = direction * DETECTION_RANGE

func _look_at_player() -> void:
	if not _target_player:
		return

	var look_target := _target_player.global_position
	look_target.y = global_position.y 
	look_at(look_target, Vector3.UP)

func _update_eyes(delta: float) -> void:
	_blink_timer += delta

	if _is_blinking:
		_blink_phase_timer += delta
		if _blink_phase_timer >= BLINK_DURATION:
			_is_blinking = false
			_blink_phase_timer = 0.0
			_set_eyes_visible(true)
	else:
		if _blink_timer >= BLINK_INTERVAL:
			_blink_timer = 0.0
			_is_blinking = true
			_set_eyes_visible(false)

func _set_eyes_visible(eyes_visible: bool) -> void:
	if left_eye:
		left_eye.visible = eyes_visible
	if right_eye:
		right_eye.visible = eyes_visible

# Funcoes utilitarias
func get_state() -> State:
	return _state

func get_approach_count() -> int:
	return _approach_count
