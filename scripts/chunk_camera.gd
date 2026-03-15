extends Node3D
## ChunkCamera - Ativa câmera quando jogador local entra

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	_create_detection_area()

func _create_detection_area() -> void:
	var area := Area3D.new()
	area.name = "CameraDetectionArea"
	area.collision_layer = 0
	area.collision_mask = 1  # Detecta players na layer 1

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 10.0, 20.0)  # Tamanho do chunk
	shape.shape = box
	shape.position = Vector3(0, 5, 0)

	area.add_child(shape)
	add_child(area)

	area.body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("players"):
		return

	# Só ativar para jogador local
	if not _is_local_player(body):
		return

	var camera_manager := get_node_or_null("/root/CameraManager")
	if camera_manager:
		camera_manager.set_active_camera(camera)

func _is_local_player(player: Node3D) -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return player.is_multiplayer_authority()
