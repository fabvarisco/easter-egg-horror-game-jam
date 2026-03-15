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
	if _was_picked_up:
		return

	_was_picked_up = true

	if is_monster:
		_release_monster()

func _release_monster() -> void:
	monster_released.emit()

	if _is_multiplayer_active():
		var host_manager := get_node_or_null("/root/HostManager")
		if host_manager and multiplayer.is_server():
			host_manager.release_monster(global_position)
		_play_laugh_sound_global()
		_break_egg()
		await get_tree().create_timer(0.3).timeout
		queue_free()
		return

	var camera_manager := get_node_or_null("/root/CameraManager")
	if camera_manager:
		camera_manager.shake_camera(SHAKE_INTENSITY, SHAKE_DURATION)

	_play_laugh_sound_global()

	_break_egg()

	await get_tree().create_timer(0.3).timeout
	_activate_bunny()


func _is_multiplayer_active() -> bool:
	# Check if we're actually in a multiplayer game, not just having EOS plugin loaded
	var single_player := get_tree().get_first_node_in_group("player")
	if single_player:
		return false  # Singleplayer mode

	return multiplayer.has_multiplayer_peer() and \
		   multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _break_egg() -> void:
	var mesh := get_node_or_null("MeshInstance3D")
	if mesh:
		var tween := create_tween()
		tween.tween_property(mesh, "scale", Vector3.ZERO, 0.2)
		tween.tween_callback(mesh.queue_free)

func _play_laugh_sound_global() -> void:
	var audio_player := AudioStreamPlayer.new()
	audio_player.stream = _bunny_laugh
	audio_player.volume_db = 5.0
	audio_player.bus = "Master"
	get_tree().current_scene.add_child(audio_player)
	audio_player.play()

	audio_player.finished.connect(audio_player.queue_free)

func _activate_bunny() -> void:
	var bunny := get_tree().get_first_node_in_group("assassin_bunny")
	if bunny and bunny.has_method("activate"):
		_connect_bunny_to_scene(bunny)
		bunny.activate()
		queue_free()
	else:
		_spawn_assassin_bunny()

func _spawn_assassin_bunny() -> void:
	var bunny_scene := preload("res://scenes/assassin_bunny.tscn")
	var bunny := bunny_scene.instantiate()
	get_tree().current_scene.add_child(bunny)
	bunny.add_to_group("assassin_bunny")
	_connect_bunny_to_scene(bunny)
	bunny.activate()
	queue_free()

func _connect_bunny_to_scene(bunny: Node) -> void:
	var scene_controller := get_tree().current_scene
	if scene_controller and scene_controller.has_method("_on_all_players_dead"):
		if bunny.has_signal("all_players_dead") and not bunny.all_players_dead.is_connected(scene_controller._on_all_players_dead):
			bunny.all_players_dead.connect(scene_controller._on_all_players_dead)
