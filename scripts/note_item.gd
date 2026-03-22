extends InteractableItem
class_name NoteItem

# Note-specific properties
@export_group("Note Settings")
@export_multiline var note_text: String = ""  # Texto da nota (multiline para facilitar edição)
@export var note_title: String = "???"        # Título da nota
@export var showing_item_scale: float = 3.5   # Escala maior para notas

func _ready() -> void:
	super._ready()  # Chama _ready() do InteractableItem

	# Sobrescrever descriptionValue com note_text formatado
	descriptionValue = _format_note_text()


func _format_note_text() -> String:
	"""Formata o texto da nota com markup BBCode para RichTextLabel"""
	var formatted := "[center]"

	# Título em negrito e maior
	if not note_title.is_empty():
		formatted += "[font_size=24][b]" + note_title + "[/b][/font_size]\n\n"

	# Texto da nota
	formatted += "[font_size=18]" + note_text + "[/font_size]"
	formatted += "[/center]"

	return formatted


# Override do método show_item para usar escala customizada e fonte
func show_item() -> void:
	var camera_manager := get_node_or_null("/root/CameraManager")
	if not camera_manager:
		return

	var active_camera: Camera3D = camera_manager.get_active_camera()
	if not active_camera:
		return

	_is_showing_item = true

	# Bloquear movimento do player
	var player := _get_local_player()
	if player and player.has_method("set_movement_enabled"):
		player.set_movement_enabled(false)

	# Instanciar cena showing_item (reutiliza existente)
	var showing_item_instance = showing_item_scene.instantiate()
	active_camera.add_child(showing_item_instance)

	# Posicionar à frente da câmera
	showing_item_instance.position = Vector3(0, 0, -5)

	# Configurar a nota
	showing_item_instance.set_static(is_static)
	showing_item_instance.set_description_value(descriptionValue)
	showing_item_instance.mesh_instance.mesh = mesh_instance.mesh

	# APLICAR ESCALA MAIOR PARA NOTA
	showing_item_instance.mesh_instance.scale = Vector3(showing_item_scale, showing_item_scale, showing_item_scale)

	# APLICAR FONTE DE TERROR
	showing_item_instance.set_custom_font("res://assets/fonts/HelpMe.ttf")

	# Passar referências
	if player:
		showing_item_instance.set_meta("player_reference", player)
	showing_item_instance.set_meta("interactable_item", self)

	# Conectar sinal de fechamento
	showing_item_instance.tree_exiting.connect(_on_showing_item_closed)
