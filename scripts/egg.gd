extends Node3D
class_name Egg 

@export var is_monster: bool = false

const SHAKE_INTENSITY: float = 0.5
const SHAKE_DURATION: float = 1.0

var _was_picked_up: bool = false
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

signal monster_released

func _ready() -> void:
	set_outline_active(false)

func on_picked_up() -> void:
	is_multiplayer_authority()
	if _was_picked_up:
		return

	_was_picked_up = true

	if is_monster:
		_release_monster()

func _release_monster() -> void:
	monster_released.emit()

	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_scream()

	if _is_multiplayer_active():
		var host_manager := get_node_or_null("/root/HostManager")
		if host_manager and multiplayer.is_server():
			host_manager.release_monster(global_position)
		_break_egg()
		await get_tree().create_timer(0.3).timeout
		queue_free()
		return

	var camera_manager := get_node_or_null("/root/CameraManager")
	if camera_manager:
		camera_manager.shake_camera(SHAKE_INTENSITY, SHAKE_DURATION)

	_break_egg()

	await get_tree().create_timer(0.3).timeout
	_activate_bunny()


func _is_multiplayer_active() -> bool:
	var single_player := get_tree().get_first_node_in_group("player")
	if single_player:
		return false 

	return multiplayer.has_multiplayer_peer() and \
		   multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _break_egg() -> void:
	var mesh := get_node_or_null("MeshInstance3D")
	if mesh:
		var tween := create_tween()
		tween.tween_property(mesh, "scale", Vector3.ZERO, 0.2)
		tween.tween_callback(mesh.queue_free)


func _activate_bunny() -> void:
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


func set_outline_active(active: bool) -> void:
	if not mesh_instance:
		return

	if active:
		if mesh_instance.material_overlay == null:
			var outline_shader := load("res://shaders/enhanced_outline.gdshader")
			var material := ShaderMaterial.new()
			material.shader = outline_shader
			material.set_shader_parameter("outline_color", Color(0, 1, 0.6, 1))
			material.set_shader_parameter("outline_width", 0.07)
			material.set_shader_parameter("pulse_speed", 2.5)
			material.set_shader_parameter("pulse_amount", 0.4)
			material.set_shader_parameter("glow_intensity", 5.0)
			material.set_shader_parameter("enable_pulse", true)
			material.render_priority = 1
			mesh_instance.material_overlay = material
	else:
		mesh_instance.material_overlay = null
