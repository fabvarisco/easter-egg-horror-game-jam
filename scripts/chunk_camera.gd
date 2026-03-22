extends Node3D
## ChunkCamera - Ativa câmera quando jogador local entra

@onready var camera: Camera3D = $Camera3D

var _detection_area: Area3D = null
var _players_in_chunk: int = 0

func _ready() -> void:
	_create_detection_area()
	# Check for players already inside after physics processes
	call_deferred("_check_initial_players")
	# Desativar outlines inicialmente
	_set_chunk_outlines_active(false)

func _create_detection_area() -> void:
	_detection_area = Area3D.new()
	_detection_area.name = "CameraDetectionArea"
	_detection_area.collision_layer = 0
	_detection_area.collision_mask = 1  # Detecta players na layer 1
	_detection_area.monitoring = true

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 10.0, 20.0)  # Tamanho do chunk
	shape.shape = box
	shape.position = Vector3(0, 5, 0)

	_detection_area.add_child(shape)
	add_child(_detection_area)

	_detection_area.body_entered.connect(_on_body_entered)
	_detection_area.body_exited.connect(_on_body_exited)

func _check_initial_players() -> void:
	# Wait a frame for physics to update
	await get_tree().physics_frame

	if not _detection_area:
		return

	# Check for bodies already overlapping
	var bodies := _detection_area.get_overlapping_bodies()
	print("[ChunkCamera] ", name, " checking initial players, found: ", bodies.size())
	for body in bodies:
		_on_body_entered(body)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("players"):
		return

	_players_in_chunk += 1
	print("[ChunkCamera] Player entered, total in chunk: ", _players_in_chunk)

	# Ativar outlines quando primeiro player entra
	if _players_in_chunk == 1:
		print("[ChunkCamera] Activating outlines for chunk: ", get_parent().name if get_parent() else "no parent")
		_set_chunk_outlines_active(true)

	# Só ativar câmera para jogador local
	if not _is_local_player(body):
		return

	print("[ChunkCamera] Player entered chunk: ", name)
	var camera_manager := get_node_or_null("/root/CameraManager")
	if camera_manager:
		camera_manager.set_active_camera(camera)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("players"):
		return

	_players_in_chunk -= 1

	# Desativar outlines quando último player sai
	if _players_in_chunk <= 0:
		_players_in_chunk = 0
		_set_chunk_outlines_active(false)


func _set_chunk_outlines_active(active: bool) -> void:
	var chunk_parent = get_parent()
	print("[ChunkCamera] Setting outlines active: ", active, " for chunk: ", chunk_parent.name if chunk_parent else "no parent")

	# Encontrar todos os itens filhos do chunk
	if not chunk_parent:
		print("[ChunkCamera] WARNING: No chunk parent found!")
		return

	var items_count = 0
	var eggs_count = 0

	# Buscar itens interativos dentro do chunk
	for child in chunk_parent.get_children():
		if child.is_in_group("interactable_items") and child.has_method("set_outline_active"):
			child.set_outline_active(active)
			items_count += 1
			print("[ChunkCamera] Set outline for item: ", child.name)
		elif child.is_in_group("eggs") and child.has_method("set_outline_active"):
			child.set_outline_active(active)
			eggs_count += 1
			print("[ChunkCamera] Set outline for egg: ", child.name)

		# Buscar recursivamente em filhos
		_set_outlines_recursive(child, active)

	print("[ChunkCamera] Total items found: ", items_count, ", eggs found: ", eggs_count)


func _set_outlines_recursive(node: Node, active: bool) -> void:
	for child in node.get_children():
		if child.is_in_group("interactable_items") and child.has_method("set_outline_active"):
			child.set_outline_active(active)
			print("[ChunkCamera] Set outline for item (recursive): ", child.name)
		elif child.is_in_group("eggs") and child.has_method("set_outline_active"):
			child.set_outline_active(active)
			print("[ChunkCamera] Set outline for egg (recursive): ", child.name)

		# Continuar buscando recursivamente
		_set_outlines_recursive(child, active)


func _is_local_player(player: Node3D) -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return player.is_multiplayer_authority()
