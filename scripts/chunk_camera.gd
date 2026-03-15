extends Node3D
## ChunkCamera - Ativa câmera quando jogador local entra

@onready var camera: Camera3D = $Camera3D

var _detection_area: Area3D = null

func _ready() -> void:
	_create_detection_area()
	# Check for players already inside after physics processes
	call_deferred("_check_initial_players")

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

	# Só ativar para jogador local
	if not _is_local_player(body):
		return

	print("[ChunkCamera] Player entered chunk: ", name)
	var camera_manager := get_node_or_null("/root/CameraManager")
	if camera_manager:
		camera_manager.set_active_camera(camera)

func _is_local_player(player: Node3D) -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return player.is_multiplayer_authority()
