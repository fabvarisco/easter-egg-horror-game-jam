extends Node3D

@onready var shop_layer = $ShopLayer

func _ready() -> void:
	shop_layer.visible = false


func _process(delta: float) -> void:
	pass



func _on_area_3d_body_entered(body: Node3D) -> void:
	shop_layer.visible = true

func _on_area_3d_body_exited(body: Node3D) -> void:
	shop_layer.visible = false


func _on_head_lamp_pressed() -> void:
	pass # Replace with function body.


