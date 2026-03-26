extends Node3D
@onready var mesh_instance: MeshInstance3D = $Mesh
@onready var description := $CanvasLayer/Info

var _is_static: bool = true
var descriptionValue: String = ""
var _is_dragging: bool = false
var _last_mouse_position: Vector2 = Vector2.ZERO
var _rotation_sensitivity: float = 0.005

func _process(_delta: float) -> void:
	pass


func _input(event: InputEvent) -> void:
	if not _is_static:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_is_dragging = event.pressed
			if _is_dragging:
				_last_mouse_position = event.position

	elif event is InputEventMouseMotion and _is_dragging:
		var mouse_delta = event.position - _last_mouse_position
		_last_mouse_position = event.position

		mesh_instance.rotate_y(-mouse_delta.x * _rotation_sensitivity)
		mesh_instance.rotate_x(-mouse_delta.y * _rotation_sensitivity)


func _physics_process(_delta: float) -> void:
	if _is_static: return
	mesh_instance.rotate_y(0.33 * _delta)
	mesh_instance.rotate_z(0.33 * _delta)
	mesh_instance.rotate_x(0.33 * _delta)


func _on_button_pressed() -> void:
	# Reativar movimento do player
	if has_meta("player_reference"):
		var player = get_meta("player_reference")
		if is_instance_valid(player) and player.has_method("set_movement_enabled"):
			player.set_movement_enabled(true)

	queue_free()


func set_description_value(_value:String) -> void:
	descriptionValue = _value
	description.text = descriptionValue

func set_mesh(_value: MeshInstance3D) -> void:
	pass

func set_static(_value:bool) ->void:
	_is_static = _value


func set_custom_font(font_path: String) -> void:
	"""Aplica fonte customizada ao RichTextLabel"""
	var font_file := load(font_path) as FontFile
	if font_file and description:
		description.add_theme_font_override("normal_font", font_file)
		description.add_theme_font_override("bold_font", font_file)


func hide_description_label() -> void:
	"""Esconde o RichTextLabel (usado quando texto está renderizado no mesh)"""
	if description:
		description.visible = false