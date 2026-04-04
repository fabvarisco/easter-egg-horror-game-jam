extends Node3D

signal dialogue_finished

@onready var text_label: Label = $CanvasLayer/Panel/text
@onready var skip_button: Button = $CanvasLayer/Skip
@onready var next_button: Button = $CanvasLayer/Next

var _dialogues: Array[String] = []
var _current_index: int = 0
var _is_typing: bool = false
var _current_text: String = ""
var _char_index: int = 0
var _typing_timer: float = 0.0
var _auto_advance_timer: float = 0.0
var _waiting_for_advance: bool = false

const TYPING_SPEED: float = 0.03     
const AUTO_ADVANCE_DELAY: float = 3.0 


func _ready() -> void:
	skip_button.pressed.connect(_on_skip_pressed)
	next_button.pressed.connect(_on_next_pressed)
	text_label.text = ""


func start_dialogue(dialogues: Array[String]) -> void:
	_dialogues = dialogues
	_current_index = 0
	_show_current_dialogue()


func _show_current_dialogue() -> void:
	if _current_index >= _dialogues.size():
		dialogue_finished.emit()
		return

	_current_text = _dialogues[_current_index]
	_char_index = 0
	_is_typing = true
	_waiting_for_advance = false
	_typing_timer = 0.0
	_auto_advance_timer = 0.0
	text_label.text = ""


func _process(delta: float) -> void:
	if _is_typing:
		_typing_timer += delta
		if _typing_timer >= TYPING_SPEED:
			_typing_timer = 0.0
			_char_index += 1
			text_label.text = _current_text.substr(0, _char_index)

			if _char_index >= _current_text.length():
				_is_typing = false
				_waiting_for_advance = true
				_auto_advance_timer = 0.0

	elif _waiting_for_advance:
		_auto_advance_timer += delta
		if _auto_advance_timer >= AUTO_ADVANCE_DELAY:
			_waiting_for_advance = false
			_advance_dialogue()


func _on_next_pressed() -> void:
	if _is_typing:
		_is_typing = false
		_char_index = _current_text.length()
		text_label.text = _current_text
		_waiting_for_advance = true
		_auto_advance_timer = 0.0
	else:
		_waiting_for_advance = false
		_advance_dialogue()


func _on_skip_pressed() -> void:
	_is_typing = false
	_waiting_for_advance = false
	dialogue_finished.emit()


func _advance_dialogue() -> void:
	_current_index += 1
	_show_current_dialogue()
