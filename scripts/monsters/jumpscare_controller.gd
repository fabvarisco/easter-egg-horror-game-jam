extends Node3D

@onready var jumpscare_camera: Camera3D = $Camera3D

var _previous_camera: Camera3D = null

func show_jumpscare(duration: float) -> void:
	"""Mostra o jumpscare por uma duração específica"""
	var camera_manager = get_node_or_null("/root/CameraManager")
	if not camera_manager:
		print("[JUMPSCARE] CameraManager não encontrado")
		queue_free()
		return

	# Guarda câmera anterior antes de ativar o jumpscare
	_previous_camera = camera_manager.get_active_camera()

	# Ativa câmera do jumpscare
	camera_manager.set_active_camera(jumpscare_camera)
	print("[JUMPSCARE] Câmera do jumpscare ativada por %.2f segundos" % duration)

	# Aguarda duração
	await get_tree().create_timer(duration).timeout

	# Restaura câmera anterior antes de se destruir
	if _previous_camera and is_instance_valid(_previous_camera):
		camera_manager.set_active_camera(_previous_camera)
		print("[JUMPSCARE] Câmera anterior restaurada")
	else:
		print("[JUMPSCARE] AVISO: Câmera anterior não encontrada")

	# Se auto-destrói
	print("[JUMPSCARE] Finalizando jumpscare")
	queue_free()
