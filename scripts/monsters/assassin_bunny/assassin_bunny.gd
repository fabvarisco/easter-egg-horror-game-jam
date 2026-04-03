extends bunny_entity

@onready var raycasts: Array[RayCast3D] = [$RayCast3D, $RayCast3D2, $RayCast3D3]
@onready var anim_player: AnimationPlayer = $model/AnimationPlayer

const BLINK_INTERVAL: float = 2.0
const BLINK_DURATION: float = 0.15

const SOUND_CHECK_INTERVAL: float = 0.2  
const FLASHLIGHT_CHECK_INTERVAL: float = 0.1  
const TURN_SPEED: float = 0.6
const SEARCH_DURATION: float = 10.0
const BUNNY_ATTACK_DAMAGE: int = 34  

var _sound_check_timer: float = 0.0
var _flashlight_check_timer: float = 0.0
var _search_timer: float = 0.0
var _is_turning: bool = false
var _turn_start_rotation: float = 0.0
var _turn_target_rotation: float = 0.0
var _turn_lerp_progress: float = 0.0

const ANIM_SPAWN: String = "Spawn"
const ANIM_SEARCH: String = "Search"
const ANIM_LEAVE: String = "Leave"
const ANIM_DETECT: String = "Detect" 
const ANIM_KILL: String = "Kill" 

func _ready() -> void:
	visible = false
	set_physics_process(false)
	_set_raycasts_enabled(false)

	if model:
		model.visible = false

func _set_raycasts_enabled(enabled: bool) -> void:
	"""Ativa/desativa todos os raycasts"""
	for rc in raycasts:
		if rc:
			rc.enabled = enabled


func _sync_visibility_to_clients(_is_visible: bool, model_visible: bool) -> void:
	"""Sincroniza visibilidade com clientes"""
	if _is_multiplayer_active() and multiplayer.is_server():
		_sync_visibility.rpc(_is_visible, model_visible)

func _check_raycasts_for_player() -> Node3D:
	"""Verifica se algum dos raycasts está colidindo com um player"""
	for rc in raycasts:
		if rc and rc.enabled and rc.is_colliding():
			var collider := rc.get_collider()
			if collider is CharacterBody3D:
				return collider
	return null

func activate() -> void:
	if _state != State.DORMANT:
		return

	_find_target_player()
	if _target_player:
		_spawn_at_distance(SPAWN_DISTANCE)
		_start_spawn_sequence()

func _start_spawn_sequence() -> void:
	"""Inicia sequência: SPAWN -> SEARCHING"""
	_state = State.SPAWNING
	visible = true
	_set_raycasts_enabled(false)

	_sync_visibility_to_clients(true, false)

	_play_animation(ANIM_SPAWN)
	await anim_player.animation_finished

	if model:
		model.visible = true

	_sync_visibility_to_clients(true, true)

	set_physics_process(true)
	_start_search()

func _start_search() -> void:
	"""Inicia estado SEARCHING - ativa raycasts e detecção"""
	_state = State.SEARCHING
	_search_timer = 0.0
	_set_raycasts_enabled(true)  

	_play_animation(ANIM_SEARCH)

func _start_leave() -> void:
	"""Inicia estado LEAVING - desativa raycasts e sai"""
	_state = State.LEAVING
	_set_raycasts_enabled(false)

	_play_animation(ANIM_LEAVE)
	await anim_player.animation_finished

	visible = false
	if model:
		model.visible = false
	_sync_visibility_to_clients(false, false)

	_find_target_player()
	_spawn_at_distance(SPAWN_DISTANCE)

	_start_spawn_sequence()

func _play_animation(anim_name: String) -> void:
	"""Toca animação se existir, senão faz fallback. Sincroniza com clientes."""
	var final_anim := anim_name

	if not anim_player.has_animation(anim_name):
		match anim_name:
			ANIM_SPAWN:
				if anim_player.has_animation("Spawn"):
					final_anim = "Spawn"
			ANIM_DETECT:
				if anim_player.has_animation("Kill"):
					final_anim = "Kill"
			_:
				return

	anim_player.play(final_anim)

	if _is_multiplayer_active() and multiplayer.is_server():
		_sync_animation.rpc(final_anim)


@rpc("authority", "call_remote", "reliable")
func _sync_animation(anim_name: String) -> void:
	"""Recebe animação do servidor"""
	if anim_player and anim_player.has_animation(anim_name):
		anim_player.play(anim_name) 

func _physics_process(_delta: float) -> void:
	if _is_multiplayer_active() and not multiplayer.is_server():
		return

	match _state:
		State.SPAWNING:
			pass  
		State.SEARCHING:
			_process_searching(_delta)
		State.LEAVING:
			pass 
		State.APPROACHING:
			_process_approaching(_delta)
		State.KILLING:
			_process_killing(_delta)

	_maintain_fixed_rotation()


func _is_multiplayer_active() -> bool:
	var single_player := get_tree().get_first_node_in_group("player")
	if single_player:
		return false  

	return multiplayer.has_multiplayer_peer() and \
		   multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _is_local_player(player: Node3D) -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return player.is_multiplayer_authority()

func _process_searching(_delta: float) -> void:
	"""Processa estado SEARCHING - raycast ativo, detectando players"""
	_find_target_player()

	if not _target_player:
		return

	_search_timer += _delta
	if _search_timer >= SEARCH_DURATION:
		print("[BUNNY] Tempo de search esgotado - iniciando Leave")
		_start_leave()
		return

	if _is_turning:
		_process_turning(_delta)
		return

	var detected_player := _check_raycasts_for_player()
	if detected_player:
		print("[BUNNY] Detectado por VISÃO (raycast)")
		_target_player = detected_player
		_start_detect()
		return

	_flashlight_check_timer += _delta
	if _flashlight_check_timer >= FLASHLIGHT_CHECK_INTERVAL:
		_flashlight_check_timer = 0.0
		var illuminating_player := _detect_flashlight_on_bunny()
		if illuminating_player:
			print("[BUNNY] Lanterna detectada - iniciando rotação lenta")
			_start_turning(illuminating_player)
			return

	_sound_check_timer += _delta
	if _sound_check_timer >= SOUND_CHECK_INTERVAL:
		_sound_check_timer = 0.0
		var noisy_player := _detect_player_by_sound()
		if noisy_player:
			print("[BUNNY] Som detectado - iniciando rotação lenta")
			_start_turning(noisy_player)

func _start_detect() -> void:
	"""Inicia sequência de detecção:
	1. Leave (some)
	2. Spawn na posição do player
	3. Paralisa player (após iniciar animação de aparecer)
	4. Kill (causa strike)
	5. Desparalisa player
	"""
	if not _target_player:
		return

	_set_raycasts_enabled(false)
	_state = State.APPROACHING

	# 1. Toca Leave e some
	_play_animation(ANIM_LEAVE)
	await anim_player.animation_finished

	visible = false
	if model:
		model.visible = false
	_sync_visibility_to_clients(false, false)

	_spawn_in_front_of_player()

	await get_tree().create_timer(0.3).timeout

	visible = true
	if model:
		model.visible = true
	_sync_visibility_to_clients(true, true)

	_play_animation(ANIM_SPAWN)

	_set_player_paralyzed(true)

	await anim_player.animation_finished

	_play_animation(ANIM_KILL)

	if _target_player:
		if _is_local_player(_target_player):
			_show_jumpscare_local()

		if _is_multiplayer_active() and multiplayer.is_server() and not _is_local_player(_target_player):
			var peer_id := int(_target_player.name)
			_show_jumpscare_remote.rpc_id(peer_id)

	await anim_player.animation_finished

	if _target_player and _target_player.has_method("take_damage"):
		_target_player.take_damage(BUNNY_ATTACK_DAMAGE)

		if _is_multiplayer_active() and multiplayer.is_server() and not _is_local_player(_target_player):
			var peer_id := int(_target_player.name)
			_sync_player_damage.rpc_id(peer_id, BUNNY_ATTACK_DAMAGE)

		print("[BUNNY] Causou %d de dano" % BUNNY_ATTACK_DAMAGE)

	_play_detection_effects()
	_set_player_paralyzed(false)

	if _target_player.has_method("is_dead") and _target_player.is_dead():
		await get_tree().create_timer(1.0).timeout
		_hunt_next_player()
		return

	await get_tree().create_timer(RESPAWN_DELAY).timeout

	_play_animation(ANIM_LEAVE)
	await anim_player.animation_finished

	visible = false
	if model:
		model.visible = false
	_sync_visibility_to_clients(false, false)

	_find_target_player()
	_spawn_at_distance(SPAWN_DISTANCE)
	_start_spawn_sequence()

func _spawn_in_front_of_player() -> void:
	"""Posiciona o coelho na frente do player, olhando para ele"""
	if not _target_player:
		return

	var player_forward := -_target_player.global_transform.basis.z.normalized()
	player_forward.y = 0

	var spawn_distance := 2.5 
	global_position = _target_player.global_position + player_forward * spawn_distance
	global_position.y = 0

	var dir_to_player := (_target_player.global_position - global_position).normalized()
	dir_to_player.y = 0
	_fixed_rotation = atan2(dir_to_player.x, dir_to_player.z)
	rotation.y = _fixed_rotation

	if _is_multiplayer_active() and multiplayer.is_server():
		_sync_transform.rpc(global_position, _fixed_rotation)

func _set_player_paralyzed(paralyzed: bool) -> void:
	"""Ativa/desativa movimento do player. Sincroniza com todos os clientes."""
	if not _target_player:
		return

	var peer_id := int(_target_player.name)

	if _target_player.has_method("set_movement_enabled"):
		_target_player.set_movement_enabled(not paralyzed)

	if _is_multiplayer_active() and multiplayer.is_server():
		_sync_player_paralyzed.rpc(peer_id, paralyzed)


@rpc("authority", "call_remote", "reliable")
func _sync_player_paralyzed(peer_id: int, paralyzed: bool) -> void:
	"""Recebe paralisia do servidor e aplica ao player correto"""
	var players := get_tree().get_nodes_in_group("players")
	for player in players:
		if player.name == str(peer_id):
			if player.has_method("set_movement_enabled"):
				player.set_movement_enabled(not paralyzed)
			return


@rpc("authority", "call_remote", "unreliable")
func _sync_transform(pos: Vector3, rot: float) -> void:
	"""Recebe posição e rotação do servidor"""
	global_position = pos
	_fixed_rotation = rot
	rotation.y = rot


@rpc("authority", "call_remote", "reliable")
func _sync_visibility(_is_visible: bool, model_visible: bool) -> void:
	"""Recebe visibilidade do servidor"""
	visible = _is_visible
	if model:
		model.visible = model_visible

func _process_approaching(_delta: float) -> void:
	pass

func _process_killing(_delta: float) -> void:
	pass

func _start_approach() -> void:
	"""Legado - agora usa _start_detect() para o fluxo completo"""
	_start_detect()

func _play_detection_effects() -> void:
	if not _target_player:
		return

	var peer_id := int(_target_player.name)

	if _is_local_player(_target_player):
		_apply_local_detection_effects()

	if _is_multiplayer_active() and multiplayer.is_server() and not _is_local_player(_target_player):
		_sync_detection_effects.rpc_id(peer_id)

	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_roar()

	var audio_player := AudioStreamPlayer.new()
	audio_player.stream = bunny_wake_up_sound
	audio_player.volume_db = 3.0
	_target_player.add_child(audio_player)
	audio_player.play()
	audio_player.finished.connect(audio_player.queue_free)


func _apply_local_detection_effects() -> void:
	"""Aplica efeitos locais de detecção"""
	var camera_manager := get_node_or_null("/root/CameraManager")
	if camera_manager:
		camera_manager.shake_camera(SHAKE_INTENSITY, SHAKE_DURATION)


@rpc("authority", "call_remote", "reliable")
func _sync_detection_effects() -> void:
	"""Recebe comando para aplicar efeitos de detecção no cliente"""
	_apply_local_detection_effects()

	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_roar()


@rpc("authority", "call_remote", "reliable")
func _sync_player_damage(damage: int) -> void:
	var players := get_tree().get_nodes_in_group("players")
	for player in players:
		if player.is_multiplayer_authority():
			if player.has_method("take_damage"):
				player.take_damage(damage)
			return


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

	if _is_multiplayer_active() and multiplayer.is_server():
		_sync_transform.rpc(global_position, _fixed_rotation)

func _relocate() -> void:
	"""Relocação via animação Leave"""
	_start_leave()

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

func _detect_player_by_sound() -> Node3D:
	"""Detecta se algum player está fazendo barulho perto do coelho"""
	var alive_players := _get_alive_players()

	for player in alive_players:
		if not player.has_method("get_sound_radius"):
			continue

		var sound_radius: float = player.get_sound_radius()
		var distance: float = global_position.distance_to(player.global_position)

		if distance <= sound_radius:
			return player

	return null

func _detect_flashlight_on_bunny() -> Node3D:
	"""Detecta se algum player está iluminando o coelho com lanterna"""
	var alive_players := _get_alive_players()

	for player in alive_players:
		var flashlight: SpotLight3D = player.get_node_or_null("SpotLight3D")
		if not flashlight or not flashlight.visible:
			continue

		var light_pos: Vector3 = flashlight.global_position
		var light_dir: Vector3 = -flashlight.global_transform.basis.z
		var light_range: float = flashlight.spot_range
		var light_angle: float = deg_to_rad(flashlight.spot_angle)

		var to_bunny: Vector3 = global_position - light_pos
		var distance: float = to_bunny.length()

		if distance > light_range:
			continue

		var angle_to_bunny: float = light_dir.angle_to(to_bunny.normalized())
		if angle_to_bunny <= light_angle:
			return player

	return null

func _turn_to_player(player: Node3D) -> void:
	"""Vira o coelho na direção do player antes de atacar"""
	var dir_to_player := (player.global_position - global_position).normalized()
	dir_to_player.y = 0
	_fixed_rotation = atan2(dir_to_player.x, dir_to_player.z)
	rotation.y = _fixed_rotation

func _start_turning(player: Node3D) -> void:
	"""Inicia rotação lenta em direção à posição do player"""
	_is_turning = true
	_turn_lerp_progress = 0.0
	_turn_start_rotation = _fixed_rotation

	var dir_to_player := (player.global_position - global_position).normalized()
	dir_to_player.y = 0
	_turn_target_rotation = atan2(dir_to_player.x, dir_to_player.z)

func _process_turning(delta: float) -> void:
	"""Processa a rotação lenta até a posição capturada do jogador"""
	_turn_lerp_progress += TURN_SPEED * delta
	_turn_lerp_progress = clampf(_turn_lerp_progress, 0.0, 1.0)

	_fixed_rotation = lerp_angle(_turn_start_rotation, _turn_target_rotation, _turn_lerp_progress)
	rotation.y = _fixed_rotation

	var detected_player := _check_raycasts_for_player()
	if detected_player:
		print("[BUNNY] Raycast atingiu player durante rotação - DETECTADO!")
		_target_player = detected_player
		_cancel_turning()
		_start_detect()
		return

	if _turn_lerp_progress >= 1.0:
		print("[BUNNY] Rotação completa - nenhum player encontrado")
		_cancel_turning()

func _cancel_turning() -> void:
	"""Cancela a rotação"""
	_is_turning = false
	_turn_lerp_progress = 0.0

func get_state() -> State:
	return _state

func _show_jumpscare_local() -> void:
	"""Mostra jumpscare no cliente local"""
	var jumpscare_scene = load("res://scenes/monsters/jump_scare.tscn")
	if not jumpscare_scene:
		print("[BUNNY] Erro ao carregar cena de jumpscare")
		return

	var jumpscare_instance = jumpscare_scene.instantiate()
	get_tree().root.add_child(jumpscare_instance)

	var anim_duration := anim_player.get_animation(ANIM_KILL).length
	if jumpscare_instance.has_method("show_jumpscare"):
		jumpscare_instance.show_jumpscare(anim_duration)

@rpc("authority", "call_remote", "reliable")
func _show_jumpscare_remote() -> void:
	"""Recebe comando para mostrar jumpscare no cliente remoto"""
	_show_jumpscare_local()
