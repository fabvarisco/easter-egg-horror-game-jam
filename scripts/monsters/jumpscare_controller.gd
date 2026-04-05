extends Node3D

@onready var jumpscare_camera: Camera3D = $Camera3D

var _previous_camera: Camera3D = null

func show_jumpscare(duration: float) -> void:
	"""Mostra o jumpscare por uma duração específica"""
	var camera_manager = get_node_or_null("/root/CameraManager")
	if not camera_manager:
		queue_free()
		return

	_previous_camera = camera_manager.get_active_camera()

	camera_manager.set_active_camera(jumpscare_camera)

	await get_tree().create_timer(duration).timeout

	if _previous_camera and is_instance_valid(_previous_camera):
		camera_manager.set_active_camera(_previous_camera)

	queue_free()
