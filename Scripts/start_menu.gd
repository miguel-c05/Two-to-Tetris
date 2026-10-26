extends CanvasLayer
# Start screen. The players pick the level the game starts at, then press Start.
# Left/right (or A/D) change the level, Enter or Space starts. The mouse works too.

const MIN_LEVEL := 1
const MAX_LEVEL := 15

@onready var game: Game = get_parent()
@onready var level_label: Label = %LevelValue

var level := MIN_LEVEL


func _ready() -> void:
	%LevelDown.pressed.connect(_change_level.bind(-1))
	%LevelUp.pressed.connect(_change_level.bind(1))
	%StartButton.pressed.connect(_start)
	game.started.connect(hide)
	game.menu_opened.connect(show)
	_update_label()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_left") or event.is_action_pressed("p2_move_left"):
		_change_level(-1)
	elif event.is_action_pressed("ui_right") or event.is_action_pressed("p2_move_right"):
		_change_level(1)
	elif event.is_action_pressed("ui_accept") and not event.is_echo():
		_start()
	else:
		return
	get_viewport().set_input_as_handled()


func _change_level(step: int) -> void:
	level = clampi(level + step, MIN_LEVEL, MAX_LEVEL)
	_update_label()


func _update_label() -> void:
	level_label.text = str(level)


func _start() -> void:
	game.start(level)
