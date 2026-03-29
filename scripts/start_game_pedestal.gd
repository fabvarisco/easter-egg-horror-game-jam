extends Area3D
## Start Game Pedestal - Interactive pedestal for ready confirmation

signal player_interacted(peer_id: int)

const INDICATOR_COLOR_READY := Color(0.2, 0.8, 0.2)  # Green
const INDICATOR_COLOR_NOT_READY := Color(0.8, 0.2, 0.2)  # Red
const INDICATOR_COLOR_EMPTY := Color(0.3, 0.3, 0.3)  # Gray

@onready var indicators_container: Node3D = $ReadyIndicators

var _indicators: Array[MeshInstance3D] = []
var _indicator_materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	add_to_group("start_game_pedestal")
	_setup_indicators()


func _setup_indicators() -> void:
	# Create 4 ready indicator lights around the pedestal
	for i in range(4):
		var indicator := MeshInstance3D.new()
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = 0.15
		sphere_mesh.height = 0.3
		indicator.mesh = sphere_mesh

		var material := StandardMaterial3D.new()
		material.albedo_color = INDICATOR_COLOR_EMPTY
		material.emission_enabled = true
		material.emission = INDICATOR_COLOR_EMPTY
		material.emission_energy_multiplier = 0.5
		indicator.material_override = material

		# Position indicators around the pedestal
		var angle := (TAU / 4.0) * i
		var radius := 0.8
		indicator.position = Vector3(cos(angle) * radius, 0.8, sin(angle) * radius)

		indicators_container.add_child(indicator)
		_indicators.append(indicator)
		_indicator_materials.append(material)


func on_interact(peer_id: int) -> void:
	player_interacted.emit(peer_id)


func update_ready_indicators(ready_states: Dictionary, connected_peers: Array[int]) -> void:
	# Update indicator colors based on ready states
	for i in range(4):
		var material := _indicator_materials[i]

		if i < connected_peers.size():
			var peer_id := connected_peers[i]
			var is_ready: bool = ready_states.get(peer_id, false)

			if is_ready:
				material.albedo_color = INDICATOR_COLOR_READY
				material.emission = INDICATOR_COLOR_READY
				material.emission_energy_multiplier = 2.0
			else:
				material.albedo_color = INDICATOR_COLOR_NOT_READY
				material.emission = INDICATOR_COLOR_NOT_READY
				material.emission_energy_multiplier = 1.0
		else:
			# No player in this slot
			material.albedo_color = INDICATOR_COLOR_EMPTY
			material.emission = INDICATOR_COLOR_EMPTY
			material.emission_energy_multiplier = 0.5
