extends Node

signal currency_changed(new_amount: int, delta: int)
signal runs_completed_changed(new_count: int)

var group_currency: int = 0
var runs_completed: int = 0


func add_currency(amount: int, _reason: String = "") -> void:
	group_currency += amount
	currency_changed.emit(group_currency, amount)

func remove_currency(amount: int, _reason: String = "") -> void:
	add_currency(-amount, _reason)

func complete_run() -> void:
	runs_completed += 1
	runs_completed_changed.emit(runs_completed)

func get_current_grid_size() -> Vector2i:
	var base_chunks = 16  
	var total_chunks = base_chunks + (runs_completed * 2)


	var width = 4
	var height = 4

	while width * height < total_chunks:
		if height == width:
			height += 1
		else:
			width += 1

	return Vector2i(width, height)

func reset_progression() -> void:
	group_currency = 0
	runs_completed = 0
	currency_changed.emit(0, 0)
	runs_completed_changed.emit(0)
