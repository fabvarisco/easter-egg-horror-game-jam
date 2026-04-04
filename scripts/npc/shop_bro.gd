extends Node3D


@onready var animation: AnimationPlayer = $AnimationPlayer


func _ready() -> void:
	var idle_anim := animation.get_animation("CharacterArmature|Idle")
	if idle_anim:
		idle_anim.loop_mode = Animation.LOOP_LINEAR
	animation.play("CharacterArmature|Idle")
	
