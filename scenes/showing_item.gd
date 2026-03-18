extends Node3D

var _is_static: bool = false
@onready var mesh_instance: MeshInstance3D = $Mesh

func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	pass


func _physics_process(_delta: float) -> void:
	if _is_static: return
	mesh_instance.rotate_y(0.33 * _delta)
	mesh_instance.rotate_z(0.33 * _delta)
	mesh_instance.rotate_x(0.33 * _delta)
