extends Node
## CameraManager - Gerencia câmera ativa e efeitos

signal camera_changed(new_camera: Camera3D)

var _active_camera: Camera3D = null
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_timer: float = 0.0
var _original_transform: Transform3D

# VHS Effect
var _vhs_overlay: CanvasLayer = null
var _vhs_material: ShaderMaterial = null
var _vhs_enabled: bool = true

func _ready() -> void:
	_setup_vhs_overlay()

func _process(delta: float) -> void:
	# Check if camera was freed (scene change)
	if _active_camera and not is_instance_valid(_active_camera):
		_active_camera = null

	if _active_camera and _shake_timer < _shake_duration:
		_apply_camera_shake(delta)


# ==========================================
# VHS EFFECT
# ==========================================

func _setup_vhs_overlay() -> void:
	var vhs_scene := preload("res://scenes/ui/vhs_overlay.tscn")
	_vhs_overlay = vhs_scene.instantiate()
	add_child(_vhs_overlay)

	var color_rect := _vhs_overlay.get_node("ColorRect") as ColorRect
	if color_rect:
		_vhs_material = color_rect.material as ShaderMaterial

func set_vhs_enabled(enabled: bool) -> void:
	_vhs_enabled = enabled
	if _vhs_overlay:
		_vhs_overlay.visible = enabled

func is_vhs_enabled() -> bool:
	return _vhs_enabled

func set_vhs_intensity(intensity: float) -> void:
	if not _vhs_material:
		return
	# Scale all effects based on intensity (0.0 - 1.0)
	_vhs_material.set_shader_parameter("scanline_intensity", 0.25 * intensity)
	_vhs_material.set_shader_parameter("noise_intensity", 0.1 * intensity)
	_vhs_material.set_shader_parameter("chromatic_aberration", 1.5 * intensity)
	_vhs_material.set_shader_parameter("vignette_intensity", 0.35 * intensity)
	_vhs_material.set_shader_parameter("flicker_intensity", 0.02 * intensity)
	_vhs_material.set_shader_parameter("vertical_jitter", 0.001 * intensity)

func set_vhs_parameter(param: String, value: float) -> void:
	if _vhs_material:
		_vhs_material.set_shader_parameter(param, value)

func get_active_camera() -> Camera3D:
	if _active_camera and not is_instance_valid(_active_camera):
		_active_camera = null
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
