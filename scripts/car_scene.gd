extends CanvasLayer


var audio_manager := get_node_or_null("/root/AudioManager")


func play_car_audio() -> void:
	audio_manager.play_car()

func play_game_over() -> void:
	audio_manager.play_game_over()
