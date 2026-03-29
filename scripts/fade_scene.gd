extends CanvasLayer
class_name FadeScene

signal fade_out_completed
signal fade_in_completed

@onready var _animation_player: AnimationPlayer = $AnimationPlayer
@onready var _color_rect: ColorRect = $ColorRect

var _next_scene_path: String = ""
var _callback: Callable


func _ready() -> void:
	_animation_player.animation_finished.connect(_on_animation_finished)
	# Start invisible
	_color_rect.color.a = 0.0


func play_car_audio() -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_car()


func play_game_over() -> void:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager:
		audio_manager.play_game_over()


func fade_out_car(callback: Callable = Callable()) -> void:
	_callback = callback
	_animation_player.play("fade_out_car")


func fade_out_game_over(callback: Callable = Callable()) -> void:
	_callback = callback
	_animation_player.play("fade_out_game_over")


func fade_in(callback: Callable = Callable()) -> void:
	_callback = callback
	_color_rect.color.a = 1.0
	_animation_player.play("fade_in")


func fade_out_car_and_change_scene(scene_path: String) -> void:
	_next_scene_path = scene_path
	_animation_player.play("fade_out_car")


func fade_out_game_over_and_callback(callback: Callable) -> void:
	_callback = callback
	_animation_player.play("fade_out_game_over")


func _on_animation_finished(anim_name: String) -> void:
	if anim_name == "fade_out_car" or anim_name == "fade_out_game_over":
		fade_out_completed.emit()

		if _next_scene_path != "":
			get_tree().change_scene_to_file(_next_scene_path)
			_next_scene_path = ""
		elif _callback.is_valid():
			_callback.call()
			_callback = Callable()

	elif anim_name == "fade_in":
		fade_in_completed.emit()
		if _callback.is_valid():
			_callback.call()
			_callback = Callable()
