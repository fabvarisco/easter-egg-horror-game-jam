extends bunny_entity

@onready var raycast: RayCast3D = $RayCast3D
@onready var left_eye_mesh: MeshInstance3D = $LeftEyeMesh
@onready var right_eye_mesh: MeshInstance3D = $RightEyeMesh
@onready var anim_player: AnimationPlayer = $model/AnimationPlayer

const BLINK_INTERVAL: float = 2.0 
const BLINK_DURATION: float = 0.15 

func _ready() -> void:
	visible = false
	set_physics_process(false)

	if model:
		model.visible = false

func activate() -> void:
	if _state != State.DORMANT:
		return

	_state = State.WATCHING
	visible = true
	anim_player.play("Spawn")
	await anim_player.animation_finished 
	if model:
		model.visible = true
	set_physics_process(true)

	_find_target_player()
	if _target_player:
		_spawn_at_distance(SPAWN_DISTANCE)

func _physics_process(_delta: float) -> void:
	# Clientes só atualizam visual, não processam IA
	if _is_multiplayer_active() and not multiplayer.is_server():
		_update_eyes(_delta)
		return

	match _state:
		State.WATCHING:
			_process_watching(_delta)
		State.APPROACHING:
			_process_approaching(_delta)
		State.KILLING:
			_process_killing(_delta)

	_update_eyes(_delta)
	_maintain_fixed_rotation()


func _is_multiplayer_active() -> bool:
	var single_player := get_tree().get_first_node_in_group("player")
	if single_player:
		return false  # Singleplayer mode

	return multiplayer.has_multiplayer_peer() and \
		   multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _is_local_player(player: Node3D) -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return player.is_multiplayer_authority()

func set_synced_state(state: int, approach_count: int) -> void:
	_state = state as State
	_approach_count = approach_count

func _process_watching(_delta: float) -> void:
	_find_target_player()

	if not _target_player:
		return

	var close_player := _get_player_in_attack_range()
	if close_player:
		_target_player = close_player
		_attack_close_player()
		return

	_idle_timer += _delta
	if _idle_timer >= IDLE_TIMEOUT:
		_relocate()
		return

	if raycast.is_colliding():
		var collider := raycast.get_collider()
		if collider is CharacterBody3D:
			# Detectou um player!
			_target_player = collider
			_start_approach()

func _process_approaching(_delta: float) -> void:
	pass

func _process_killing(_delta: float) -> void:
	pass

func _start_approach() -> void:
	anim_player.play("Detected")
	await anim_player.animation_finished 
	_approach_count += 1

	if _approach_count >= 3:
		_kill_player()
		return

	_state = State.APPROACHING

	visible = false
	if model:
		model.visible = false

	_play_detection_effects()

	await get_tree().create_timer(RESPAWN_DELAY).timeout

	_spawn_at_distance(SPAWN_DISTANCE)
	visible = true
	if model:
		model.visible = true

	_state = State.WATCHING

func _play_detection_effects() -> void:
	if not _target_player:
		return

	# Só aplica shake se for o jogador local
	if _is_local_player(_target_player):
		var camera_manager := get_node_or_null("/root/CameraManager")
		if camera_manager:
			camera_manager.shake_camera(SHAKE_INTENSITY, SHAKE_DURATION)

	# Play roar sound via AudioManager
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_roar()

	var audio_player := AudioStreamPlayer.new()
	audio_player.stream = bunny_wake_up_sound
	audio_player.volume_db = 3.0
	_target_player.add_child(audio_player)
	audio_player.play()
	audio_player.finished.connect(audio_player.queue_free)


func _find_target_player() -> void:
	var alive_players := _get_alive_players()

	if alive_players.is_empty():
		_target_player = null
		return

	var closest_distance := INF
	for player in alive_players:
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

	_fixed_rotation = randf() * TAU
	rotation.y = _fixed_rotation

	_idle_timer = 0.0

func _relocate() -> void:
	anim_player.play_backwards("Spawn")
	await anim_player.animation_finished 
	visible = false
	if model:
		model.visible = false
	_find_target_player()
	_spawn_at_distance(SPAWN_DISTANCE)
	visible = true
	if model:
		model.visible = true

func _get_player_in_attack_range() -> Node3D:
	var alive_players := _get_alive_players()

	for player in alive_players:
		var distance := global_position.distance_to(player.global_position)
		if distance <= ATTACK_RANGE:
			return player

	return null

func _attack_close_player() -> void:
	if not _target_player:
		return

	var dir_to_player := (_target_player.global_position - global_position).normalized()
	rotation.y = atan2(dir_to_player.x, dir_to_player.z)

	_start_approach()

func _maintain_fixed_rotation() -> void:
	rotation.y = _fixed_rotation

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
	if left_eye_mesh:
		left_eye_mesh.visible = eyes_visible
	if right_eye_mesh:
		right_eye_mesh.visible = eyes_visible

func get_state() -> State:
	return _state

func get_approach_count() -> int:
	return _approach_count
