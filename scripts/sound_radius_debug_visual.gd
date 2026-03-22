extends MeshInstance3D
## Sound Radius Debug Visual - Mostra visualmente o raio de som do jogador
##
## Anexe este script a um MeshInstance3D filho da SoundArea3D para visualizar o raio.
## Útil para debug e balanceamento.

@export var enabled: bool = true  ## Ativar/desativar visualização
@export var color_idle: Color = Color(0.2, 0.8, 0.2, 0.2)      ## Verde claro (parado)
@export var color_walk: Color = Color(0.8, 0.8, 0.2, 0.3)      ## Amarelo (andando)
@export var color_sprint: Color = Color(0.8, 0.2, 0.2, 0.4)    ## Vermelho (correndo)
@export var color_voice: Color = Color(0.2, 0.2, 0.8, 0.5)     ## Azul (falando)
@export var pulse_enabled: bool = true  ## Animar pulsação
@export var pulse_speed: float = 2.0    ## Velocidade da pulsação

var _player: CharacterBody3D = null
var _material: StandardMaterial3D = null
var _pulse_time: float = 0.0


func _ready() -> void:
	# Encontrar referência do player
	_player = _find_player_parent()
	if not _player:
		push_error("[SoundRadiusDebug] Player not found in parent hierarchy")
		queue_free()
		return

	# Criar mesh cilíndrico para visualização
	_setup_mesh()

	# Configurar material transparente
	_setup_material()

	visible = enabled
	print("[SoundRadiusDebug] Debug visualization ready")


func _process(delta: float) -> void:
	if not enabled or not visible:
		return

	if not _player or not is_instance_valid(_player):
		return

	# Atualizar cor baseada no estado do player
	_update_color()

	# Animar pulsação
	if pulse_enabled:
		_pulse_time += delta * pulse_speed
		var pulse_factor := 0.8 + sin(_pulse_time) * 0.2
		scale = Vector3.ONE * pulse_factor


func _find_player_parent() -> CharacterBody3D:
	"""Busca o node Player na hierarquia pai"""
	var current := get_parent()
	while current:
		if current is CharacterBody3D and current.has_method("get_sound_radius"):
			return current
		current = current.get_parent()
	return null


func _setup_mesh() -> void:
	"""Cria mesh cilíndrico para visualização"""
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 0.2  # Cilindro bem fino, quase um disco
	cylinder.radial_segments = 32
	cylinder.rings = 1

	mesh = cylinder


func _setup_material() -> void:
	"""Configura material transparente e brilhante"""
	_material = StandardMaterial3D.new()
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visível de ambos os lados
	_material.albedo_color = color_idle

	material_override = _material


func _update_color() -> void:
	"""Atualiza cor baseada no estado do jogador"""
	if not _material:
		return

	var target_color: Color = color_idle

	# Determinar cor baseada no estado
	if _player.has_method("is_sprinting") and _player.is_sprinting():
		target_color = color_sprint
	elif _player.has_method("is_walking") and _player.is_walking():
		target_color = color_walk
	elif _player.has_method("get_sound_radius"):
		# Detectar se está falando (raio maior que normal sem movimento)
		var radius: float = _player.get_sound_radius()
		var speed: float = _player._current_speed if "_current_speed" in _player else 0.0

		if radius > 8.0 and speed < 0.5:  # Raio grande mas parado = falando
			target_color = color_voice

	# Interpolar cor suavemente
	_material.albedo_color = _material.albedo_color.lerp(target_color, 0.1)


# ==========================================
# FUNÇÕES PÚBLICAS
# ==========================================


func toggle_visibility() -> void:
	"""Alterna visibilidade da visualização"""
	visible = not visible
	print("[SoundRadiusDebug] Visibility: %s" % visible)


func set_enabled(value: bool) -> void:
	"""Ativa/desativa visualização"""
	enabled = value
	visible = value
