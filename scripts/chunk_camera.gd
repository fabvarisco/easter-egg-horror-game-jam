extends Node3D
## ChunkCamera - Ativa câmera quando jogador local entra

@onready var camera: Camera3D = $Camera3D
@onready var _detection_area: Area3D = $Area3D

var _players_in_chunk: int = 0

func _ready() -> void:
	_setup_detection_area()
	# Check for players already inside after physics processes
	call_deferred("_check_initial_players")

func _setup_detection_area() -> void:
	if not _detection_area:
		push_error("[ChunkCamera] Area3D not found in chunk scene!")
		return

	# Configurar propriedades do Area3D existente
	_detection_area.collision_layer = 0
	_detection_area.collision_mask = 1  # Detecta players na layer 1
	_detection_area.monitoring = true

	# Conectar sinais
	_detection_area.body_entered.connect(_on_body_entered)
	_detection_area.body_exited.connect(_on_body_exited)

func _check_initial_players() -> void:
	# Wait a frame for physics to update
	await get_tree().physics_frame

	if not _detection_area:
		return

	# Check for bodies already overlapping
	var bodies := _detection_area.get_overlapping_bodies()
	for body in bodies:
		_on_body_entered(body)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("players"):
		return

	_players_in_chunk += 1

	# Só ativar câmera para jogador local
	if not _is_local_player(body):
		return

	var camera_manager := get_node_or_null("/root/CameraManager")
	if camera_manager:
		camera_manager.set_active_camera(camera)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("players"):
		return

	_players_in_chunk -= 1
	if _players_in_chunk < 0:
		_players_in_chunk = 0


func _is_local_player(player: Node3D) -> bool:
	if not multiplayer.has_multiplayer_peer():
		return true
	return player.is_multiplayer_authority()
