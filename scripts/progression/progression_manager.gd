extends Node

signal currency_changed(new_amount: int, delta: int)
signal runs_completed_changed(new_count: int)

var group_currency: int = 0
var runs_completed: int = 0

var player_has_headlamp: bool = false
var player_max_stamina_bonus: float = 0.0
var player_max_health_bonus: float = 0.0


func add_currency(amount: int, _reason: String = "") -> void:
	group_currency += amount
	currency_changed.emit(group_currency, amount)

func remove_currency(amount: int, _reason: String = "") -> void:
	add_currency(-amount, _reason)

func complete_run() -> void:
	runs_completed += 1
	runs_completed_changed.emit(runs_completed)

func get_current_grid_size(is_singleplayer: bool = false) -> Vector2i:
	var base_chunks: int
	var increment: int

	if is_singleplayer:
		base_chunks = 4  
		increment = 1     
	else:
		base_chunks = 16  
		increment = 2   

	var total_chunks = base_chunks + (runs_completed * increment)

	var width: int = 2 if is_singleplayer else 4
	var height: int = 2 if is_singleplayer else 4

	while width * height < total_chunks:
		if height == width:
			height += 1
		else:
			width += 1

	return Vector2i(width, height)

func reset_progression() -> void:
	group_currency = 0
	runs_completed = 0
	player_has_headlamp = false
	player_max_stamina_bonus = 0.0
	player_max_health_bonus = 0.0
	currency_changed.emit(0, 0)
	runs_completed_changed.emit(0)
