extends Node
## CameraManager - Gerencia câmera ativa e efeitos

signal camera_changed(new_camera: Camera3D)

var _active_camera: Camera3D = null
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_timer: float = 0.0
var _original_transform: Transform3D

func _process(delta: float) -> void:
	if _active_camera and _shake_timer < _shake_duration:
		_apply_camera_shake(delta)

func get_active_camera() -> Camera3D:
	return _active_camera

func set_active_camera(camera: Camera3D) -> void:
	if _active_camera == camera:
		return

	# Restaurar transform da câmera anterior se estava tremendo
	if _active_camera and is_instance_valid(_active_camera) and _shake_timer < _shake_duration:
		_active_camera.transform = _original_transform

	_active_camera = camera
	if _active_camera:
		_active_camera.current = true
		_original_transform = _active_camera.transform

	camera_changed.emit(_active_camera)

func shake_camera(intensity: float, duration: float) -> void:
	if not _active_camera or not is_instance_valid(_active_camera):
		return
	_shake_intensity = intensity
	_shake_duration = duration
	_shake_timer = 0.0
	_original_transform = _active_camera.transform

func _apply_camera_shake(delta: float) -> void:
	_shake_timer += delta
	var shake_progress := _shake_timer / _shake_duration
	var current_intensity := _shake_intensity * (1.0 - shake_progress)

	var shake_offset := Vector3(
		randf_range(-current_intensity, current_intensity),
		randf_range(-current_intensity, current_intensity),
		randf_range(-current_intensity, current_intensity)
	)

	_active_camera.transform = _original_transform
	_active_camera.global_position += shake_offset

	if _shake_timer >= _shake_duration:
		_active_camera.transform = _original_transform
