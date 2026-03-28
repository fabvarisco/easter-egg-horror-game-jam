class_name MapTypeDefinition extends Resource
## Define um tipo de mapa completo com todas as variantes de chunks
##
## Este resource armazena todas as PackedScenes de chunks para um bioma específico
## (cemitério, floresta, etc.) organizadas por tipo de posição no grid.

@export var map_name: String = "cemetery"
@export var display_name: String = "Cemitério"

# Chunk inicial onde os players spawnam (obrigatório)
@export var chunk_start: PackedScene

# Variantes de chunks para o centro do mapa
@export var chunks_center: Array[PackedScene] = []

# Variantes de chunks para as bordas
@export var chunks_edge_top: Array[PackedScene] = []
@export var chunks_edge_bottom: Array[PackedScene] = []
@export var chunks_edge_left: Array[PackedScene] = []
@export var chunks_edge_right: Array[PackedScene] = []

# Variantes de chunks para os cantos
@export var chunks_corner_top_left: Array[PackedScene] = []
@export var chunks_corner_top_right: Array[PackedScene] = []
@export var chunks_corner_bottom_left: Array[PackedScene] = []
@export var chunks_corner_bottom_right: Array[PackedScene] = []


func validate() -> bool:
	"""Valida se o mapa tem os chunks necessários"""
	if chunk_start == null:
		push_error("[MapTypeDefinition] chunk_start é obrigatório para o mapa '%s'" % map_name)
		return false

	if chunks_center.is_empty():
		push_warning("[MapTypeDefinition] Mapa '%s' não tem chunks de centro, usando chunk_start como fallback" % map_name)

	return true


func get_chunk_for_type(chunk_type: String, rng: RandomNumberGenerator) -> PackedScene:
	"""Retorna uma variante aleatória do tipo de chunk especificado"""
	var chunks_array: Array[PackedScene] = []

	match chunk_type:
		"START":
			return chunk_start
		"CENTER":
			chunks_array = chunks_center
		"EDGE_TOP":
			chunks_array = chunks_edge_top
		"EDGE_BOTTOM":
			chunks_array = chunks_edge_bottom
		"EDGE_LEFT":
			chunks_array = chunks_edge_left
		"EDGE_RIGHT":
			chunks_array = chunks_edge_right
		"CORNER_TOP_LEFT":
			chunks_array = chunks_corner_top_left
		"CORNER_TOP_RIGHT":
			chunks_array = chunks_corner_top_right
		"CORNER_BOTTOM_LEFT":
			chunks_array = chunks_corner_bottom_left
		"CORNER_BOTTOM_RIGHT":
			chunks_array = chunks_corner_bottom_right

	# Se não tem variantes, usa chunk_start como fallback
	if chunks_array.is_empty():
		push_warning("[MapTypeDefinition] Tipo '%s' não tem variantes, usando chunk_start como fallback" % chunk_type)
		return chunk_start

	# Seleciona variante aleatória
	var index := rng.randi_range(0, chunks_array.size() - 1)
	return chunks_array[index]
