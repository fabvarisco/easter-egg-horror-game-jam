extends Node

signal currency_changed(new_amount: int, delta: int)
signal runs_completed_changed(new_count: int)

var group_currency: int = 0
var runs_completed: int = 0

func _ready() -> void:
	print("ProgressionManager initialized")

func add_currency(amount: int, reason: String = "") -> void:
	var old = group_currency
	group_currency += amount
	currency_changed.emit(group_currency, amount)
	print("Currency: %d → %d (%+d) [%s]" % [old, group_currency, amount, reason])

func remove_currency(amount: int, reason: String = "") -> void:
	add_currency(-amount, reason)

func complete_run() -> void:
	runs_completed += 1
	runs_completed_changed.emit(runs_completed)
	print("Run completed! Total runs: %d" % runs_completed)

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
