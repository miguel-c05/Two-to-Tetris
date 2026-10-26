extends CanvasLayer
# HUD: hold and next previews, score, line clear messages, pause and game over.
# It only listens to the game's signals, it never changes the game state itself.

@onready var game: Game = get_parent()
@onready var hold_preview: Control = %HoldPreview
@onready var next_previews: Array[Control] = [%Next0, %Next1, %Next2, %Next3, %Next4]
@onready var score_label: Label = %ScoreValue
@onready var level_label: Label = %LevelValue
@onready var lines_label: Label = %LinesValue
@onready var clear_label: Label = %ClearLabel
@onready var pause_panel: Control = %PausePanel
@onready var game_over_panel: Control = %GameOverPanel
@onready var final_score_label: Label = %FinalScore
@onready var restart_button: Button = %RestartButton
@onready var menu_button: Button = %MenuButton

var _clear_tween: Tween


func _ready() -> void:
	game.stats_changed.connect(_on_stats_changed)
	game.hold_changed.connect(_on_hold_changed)
	game.next_changed.connect(_on_next_changed)
	game.line_clear.connect(_on_line_clear)
	game.game_over.connect(_on_game_over)
	game.paused_changed.connect(_on_paused_changed)
	game.started.connect(_hide_overlays)
	game.menu_opened.connect(_hide_overlays)
	restart_button.pressed.connect(game.new_game)
	menu_button.pressed.connect(game.open_menu)
	clear_label.modulate.a = 0.0
	# The game is set up before the HUD is ready, so catch up with its current state.
	_on_stats_changed(game.score, game.level, game.lines)
	_on_hold_changed(game.hold_type, game.can_hold)
	_on_next_changed(game.bag.peek(next_previews.size()))


func _on_stats_changed(score: int, level: int, lines: int) -> void:
	score_label.text = str(score)
	level_label.text = str(level)
	lines_label.text = str(lines)


func _on_hold_changed(type: int, can_hold: bool) -> void:
	hold_preview.type = type
	hold_preview.modulate = Color.WHITE if can_hold else Color(1, 1, 1, 0.35)


func _on_next_changed(types: Array[int]) -> void:
	for i in next_previews.size():
		next_previews[i].type = types[i] if i < types.size() else -1


func _on_line_clear(text: String) -> void:
	clear_label.text = text
	if _clear_tween and _clear_tween.is_valid():
		_clear_tween.kill()
	clear_label.modulate.a = 1.0
	clear_label.scale = Vector2(1.15, 1.15)
	_clear_tween = create_tween().set_parallel()
	_clear_tween.tween_property(clear_label, "scale", Vector2.ONE, 0.15)
	_clear_tween.tween_property(clear_label, "modulate:a", 0.0, 0.6).set_delay(0.6)


func _on_game_over(final_score: int) -> void:
	final_score_label.text = "Score: %d" % final_score
	game_over_panel.visible = true
	restart_button.grab_focus()


func _on_paused_changed(paused: bool) -> void:
	pause_panel.visible = paused


func _hide_overlays() -> void:
	pause_panel.visible = false
	game_over_panel.visible = false
	clear_label.modulate.a = 0.0
