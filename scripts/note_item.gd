extends InteractableItem
class_name NoteItem

@export_group("Note Settings")
@export_multiline var note_text: String = ""  
@export var note_title: String = "???"        
@export var showing_item_scale: float = 6.0  
@export var text_color: Color = Color(0.1, 0.05, 0.05, 1.0)  
@export var background_color: Color = Color(0.9, 0.85, 0.75, 1.0)  

func _ready() -> void:
	super._ready()

	descriptionValue = _format_note_text()


func _format_note_text() -> String:
	"""Formata o texto da nota com markup BBCode para RichTextLabel"""
	var formatted := "[center]"

	if not note_title.is_empty():
		formatted += "[font_size=24][b]" + note_title + "[/b][/font_size]\n\n"

	formatted += "[font_size=18]" + note_text + "[/font_size]"
	formatted += "[/center]"

	return formatted


func _create_text_texture() -> ImageTexture:
	"""Cria uma textura com o texto da nota renderizado"""
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1024, 1024)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

	var background := ColorRect.new()
	background.color = background_color
	background.size = Vector2(1024, 1024)
	viewport.add_child(background)

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.size = Vector2(900, 900)
	label.position = Vector2(62, 62) 

	var font_file := load("res://assets/fonts/HelpMe.ttf") as FontFile
	if font_file:
		label.add_theme_font_override("normal_font", font_file)
		label.add_theme_font_override("bold_font", font_file)

	label.add_theme_color_override("default_color", text_color)

	label.text = _format_note_text()

	viewport.add_child(label)

	add_child(viewport)

	await get_tree().process_frame
	await get_tree().process_frame

	var texture := viewport.get_texture()

	var image := texture.get_image()
	var permanent_texture := ImageTexture.create_from_image(image)

	viewport.queue_free()

	print("[NoteItem] Text texture created and viewport cleaned up")

	return permanent_texture


func show_item() -> void:
	var camera_manager := get_node_or_null("/root/CameraManager")
	if not camera_manager:
		return

	var active_camera: Camera3D = camera_manager.get_active_camera()
	if not active_camera:
		return

	_is_showing_item = true

	var player := _get_local_player()
	if player and player.has_method("set_movement_enabled"):
		player.set_movement_enabled(false)

	var showing_item_instance = showing_item_scene.instantiate()
	active_camera.add_child(showing_item_instance)

	showing_item_instance.position = Vector3(0, 0, -5)

	showing_item_instance.set_static(is_static)
	showing_item_instance.hide_description_label()  # Esconder UI text, usaremos textura no mesh

	showing_item_instance.mesh_instance.mesh = mesh_instance.mesh.duplicate()

	showing_item_instance.mesh_instance.scale = Vector3(showing_item_scale, showing_item_scale, showing_item_scale)

	if player:
		showing_item_instance.set_meta("player_reference", player)
	showing_item_instance.set_meta("interactable_item", self)

	showing_item_instance.tree_exiting.connect(_on_showing_item_closed)

	_apply_text_texture_async(showing_item_instance)


func _apply_text_texture_async(showing_item_instance: Node3D) -> void:
	"""Aplica a textura com texto ao mesh de forma assíncrona"""
	var text_texture := await _create_text_texture()

	if not is_instance_valid(showing_item_instance):
		print("[NoteItem] showing_item was destroyed before texture could be applied")
		return

	var material := StandardMaterial3D.new()
	material.albedo_texture = text_texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # Sem sombras para melhor legibilidade

	showing_item_instance.mesh_instance.material_override = material

	print("[NoteItem] Text texture applied to showing_item mesh")
