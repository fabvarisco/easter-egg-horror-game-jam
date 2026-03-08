extends Node3D

signal finished

const DISPLAY_TIME := 5.0

@onready var camera: Camera3D = $Camera3D

var _timer: float = 0.0
var _is_active: bool = false


func _ready() -> void:
	visible = false
	if camera:
		camera.current = false


func show_game_over() -> void:
	_timer = DISPLAY_TIME
	_is_active = true
	visible = true

	if camera:
		camera.current = true


func _process(_delta: float) -> void:
	if not _is_active:
		return

	_timer -= _delta

	if _timer <= 0:
		_is_active = false
		visible = false
		if camera:
			camera.current = false
		finished.emit()
