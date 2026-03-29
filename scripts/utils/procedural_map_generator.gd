class_name ProceduralMapGenerator extends RefCounted

const CHUNK_SIZE := 20.0 
const MIN_GRID_SIZE := 2  


func generate_map(map_def: MapTypeDefinition, grid_size: Vector2i, seed_value: int) -> Array[Node3D]:
	"""
	Gera um mapa completo baseado na definição e parâmetros

	@param map_def: Definição do tipo de mapa (cemitério, floresta, etc.)
	@param grid_size: Tamanho do grid (x, y) - mínimo 2x2
	@param seed_value: Seed para geração determinística
	@return: Array de chunks instanciados e posicionados
	"""
	# Validar mapa
	if not map_def.validate():
		push_error("[ProceduralMapGenerator] MapTypeDefinition inválida, não pode gerar mapa")
		return []

	var validated_grid := _validate_grid_size(grid_size)

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	rng.seed = seed_value

	var chunks: Array[Node3D] = []
	var total_chunks := validated_grid.x * validated_grid.y

	for y in range(validated_grid.y):
		for x in range(validated_grid.x):
			var grid_pos := Vector2i(x, y)
			var chunk := _generate_chunk_at(map_def, grid_pos, validated_grid, rng)

			if chunk != null:
				chunks.append(chunk)
			else:
				push_warning("[ProceduralMapGenerator] Falha ao gerar chunk em (%d, %d)" % [x, y])

	return chunks


func _validate_grid_size(grid_size: Vector2i) -> Vector2i:
	"""Valida e ajusta o tamanho do grid para valores seguros"""
	var validated := grid_size

	if validated.x < MIN_GRID_SIZE:
		push_warning("[ProceduralMapGenerator] Grid X muito pequeno (%d), ajustando para %d" % [validated.x, MIN_GRID_SIZE])
		validated.x = MIN_GRID_SIZE

	if validated.y < MIN_GRID_SIZE:
		push_warning("[ProceduralMapGenerator] Grid Y muito pequeno (%d), ajustando para %d" % [validated.y, MIN_GRID_SIZE])
		validated.y = MIN_GRID_SIZE

	return validated


func _generate_chunk_at(map_def: MapTypeDefinition, grid_pos: Vector2i, grid_size: Vector2i, rng: RandomNumberGenerator) -> Node3D:
	"""Gera um único chunk na posição especificada do grid"""
	# Determinar tipo de chunk baseado na posição
	var chunk_type := _get_chunk_type(grid_pos, grid_size)

	# Selecionar variante apropriada
	var chunk_scene := map_def.get_chunk_for_type(chunk_type, rng)
	if chunk_scene == null:
		push_error("[ProceduralMapGenerator] Não conseguiu obter chunk do tipo '%s' em (%d, %d)" %
			[chunk_type, grid_pos.x, grid_pos.y])
		return null

	# Instanciar chunk
	var chunk := chunk_scene.instantiate() as Node3D
	if chunk == null:
		push_error("[ProceduralMapGenerator] Falha ao instanciar chunk em (%d, %d)" % [grid_pos.x, grid_pos.y])
		return null

	# Calcular e definir posição 3D
	chunk.position = _calculate_chunk_position(grid_pos)

	# Definir nome descritivo
	chunk.name = "%s_%d_%d" % [chunk_type, grid_pos.x, grid_pos.y]

	return chunk


func _get_chunk_type(grid_pos: Vector2i, grid_size: Vector2i) -> String:
	"""
	Determina o tipo de chunk baseado na posição no grid

	Grid coordinates:
	(0,0) = top-left corner
	(grid_size.x-1, grid_size.y-1) = bottom-right corner
	"""
	var x := grid_pos.x
	var y := grid_pos.y
	var max_x := grid_size.x - 1
	var max_y := grid_size.y - 1

	if x == 0 and y == 0:
		return "START"

	# Detectar cantos
	if x == 0 and y == 0:
		return "CORNER_TOP_LEFT"
	elif x == max_x and y == 0:
		return "CORNER_TOP_RIGHT"
	elif x == 0 and y == max_y:
		return "CORNER_BOTTOM_LEFT"
	elif x == max_x and y == max_y:
		return "CORNER_BOTTOM_RIGHT"

	# Detectar bordas
	elif y == 0:
		return "EDGE_TOP"
	elif y == max_y:
		return "EDGE_BOTTOM"
	elif x == 0:
		return "EDGE_LEFT"
	elif x == max_x:
		return "EDGE_RIGHT"

	# Centro
	else:
		return "CENTER"


func _calculate_chunk_position(grid_pos: Vector2i) -> Vector3:
	"""Calcula a posição 3D do chunk baseado na posição no grid"""
	return Vector3(
		grid_pos.x * CHUNK_SIZE,
		0,
		grid_pos.y * CHUNK_SIZE
	)
