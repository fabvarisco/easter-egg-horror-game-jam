extends Node3D

@export var is_monster: bool = false

const SHAKE_INTENSITY: float = 0.5
const SHAKE_DURATION: float = 1.0

var _was_picked_up: bool = false
var _bunny_laugh: AudioStream = preload("res://assets/sounds/assasin_bunny/assassin_bunny_laugh.wav")

signal monster_released

func _ready() -> void:
	pass

func on_picked_up() -> void:
	"""Chamado quando o jogador pega este egg"""
	if _was_picked_up:
		return

	_was_picked_up = true

	if is_monster:
		_release_monster()

func _release_monster() -> void:
	monster_released.emit()

	# Encontra o jogador que pegou o egg
	var player := get_parent()
	if player and player.has_method("shake_camera"):
		player.shake_camera(SHAKE_INTENSITY, SHAKE_DURATION)

	# Toca som da risada
	_play_laugh_sound()

	# Efeito de quebra do ovo
	_break_egg()

	# Ativa o bunny apos um pequeno delay
	await get_tree().create_timer(0.3).timeout
	_activate_bunny()

func _break_egg() -> void:
	# Esconde o mesh do ovo (simula quebra)
	var mesh := get_node_or_null("MeshInstance3D")
	if mesh:
		# Anima escala diminuindo rapidamente
		var tween := create_tween()
		tween.tween_property(mesh, "scale", Vector3.ZERO, 0.2)
		tween.tween_callback(mesh.queue_free)

func _play_laugh_sound() -> void:
	var audio_player := AudioStreamPlayer.new()
	audio_player.stream = _bunny_laugh
	audio_player.volume_db = 5.0
	add_child(audio_player)
	audio_player.play()

	# Remove o audio player quando terminar
	audio_player.finished.connect(audio_player.queue_free)

func _activate_bunny() -> void:
	# Busca o assassin bunny na cena e ativa
	var bunny := get_tree().get_first_node_in_group("assassin_bunny")
	if bunny and bunny.has_method("activate"):
		bunny.activate()
	else:
		# Se nao encontrar, tenta spawnar um novo
		_spawn_assassin_bunny()

func _spawn_assassin_bunny() -> void:
	var bunny_scene := preload("res://scenes/assassin_bunny.tscn")
	var bunny := bunny_scene.instantiate()
	get_tree().current_scene.add_child(bunny)
	bunny.add_to_group("assassin_bunny")
	bunny.activate()
