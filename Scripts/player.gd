class_name Player
extends Node2D
# One player. Owns their falling piece and handles their own keys, movement timing
# (DAS/ARR), soft drop and lock delay. Anything both players share (board, queue,
# hold, score, collisions between pieces) is handled by game.gd.

const DAS := 0.167            # how long to hold left/right before it starts repeating
const ARR := 0.033            # time between repeated moves after that
const SOFT_DROP_FACTOR := 20.0
const LOCK_DELAY := 0.5
const MAX_LOCK_RESETS := 15   # stops a piece from being stalled on the floor forever

@export var player_name := "P1"
@export var action_prefix := "p1_"  # input actions are named p1_move_left, p2_hold, ...
@export var spawn_center := 12      # column this player's pieces spawn around
@export var tag_color := Color(1.0, 0.65, 0.25)

var game: Game
var board: Board
var current: Piece = null
# Piece we were given but couldn't place yet because the partner is in the spawn area.
var waiting_type := -1

# Needed for T-spin detection.
var last_move_was_rotation := false
var last_kick_index := 0

var _lock_timer := 0.0
var _lock_resets := 0
var _lowest_y := 0
var _das_dir := 0
var _das_timer := 0.0
var _arr_timer := 0.0
var _soft_drop_timer := 0.0


func setup(owner_game: Game, the_board: Board) -> void:
	game = owner_game
	board = the_board
	z_index = 10


func reset() -> void:
	current = null
	waiting_type = -1
	_das_dir = 0
	_soft_drop_timer = 0.0
	queue_redraw()


# SPAWN_X is written for a 10-wide board (centre on column 5), so shift it to our side.
func spawn_position(type: int) -> Vector2i:
	return Vector2i(spawn_center - 5 + PieceData.SPAWN_X[type], 0)


func spawn(type: int) -> void:
	current = null
	waiting_type = type
	try_spawn_waiting()


func try_spawn_waiting() -> bool:
	if waiting_type < 0:
		return false
	var piece := Piece.new(waiting_type, spawn_position(waiting_type))
	if not board.is_valid(piece.get_cells()):
		game.on_block_out()
		return false
	if not game.can_occupy(self, piece.get_cells()):
		return false  # partner is on our spawn, try again next frame

	current = piece
	waiting_type = -1
	_lock_timer = 0.0
	_lock_resets = 0
	_soft_drop_timer = 0.0
	last_move_was_rotation = false
	# Guideline: the piece drops one row straight away if it can.
	var below := current.position + Vector2i.DOWN
	if game.can_occupy(self, current.cells_at(below)):
		current.position = below
	_lowest_y = current.position.y
	return true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or game == null or not game.is_playing() or current == null:
		return
	if _just_pressed(event, "hard_drop"):
		game.hard_drop(self)
	elif _just_pressed(event, "rotate_cw"):
		try_rotate(1)
	elif _just_pressed(event, "hold"):
		game.hold(self)


# Called by the game every frame (the game decides the order between players).
func tick(delta: float) -> void:
	position = board.position  # follow the board when it shakes
	if current == null:
		try_spawn_waiting()
	if current == null:
		queue_redraw()
		return
	_handle_left_right(delta)
	if current == null or not game.is_playing():
		return
	_handle_soft_drop(delta)
	if current == null or not game.is_playing():
		return
	_update_lock(delta)
	queue_redraw()


func is_soft_dropping() -> bool:
	return _held("soft_drop")


func try_move(offset: Vector2i, by_player: bool = true) -> bool:
	var was_grounded := is_grounded()
	var target := current.position + offset
	if not game.can_occupy(self, current.cells_at(target)):
		return false
	current.position = target
	last_move_was_rotation = false
	_after_move(was_grounded, by_player)
	return true


# Moves down one row without checking anything. The game already checked the
# whole group of pieces before pushing them.
func shift_down() -> void:
	var was_grounded := is_grounded()
	current.position += Vector2i.DOWN
	last_move_was_rotation = false
	_after_move(was_grounded, false)


# Used by hard drop to teleport the piece to where it lands.
func drop_to(target: Vector2i) -> void:
	if target != current.position:
		current.position = target
		last_move_was_rotation = false


# dir 1 = clockwise, -1 = counter-clockwise. Tries every SRS kick in order.
func try_rotate(dir: int) -> bool:
	if current == null or current.type == PieceData.Type.O:
		return false
	var was_grounded := is_grounded()
	var from := current.rotation
	var to := posmod(from + dir, 4)
	var kicks := PieceData.get_kicks(current.type, from, to)
	for i in kicks.size():
		var target: Vector2i = current.position + kicks[i]
		if game.can_occupy(self, current.cells_at(target, to)):
			current.rotation = to
			current.position = target
			last_move_was_rotation = true
			last_kick_index = i
			_after_move(was_grounded, true)
			return true
	return false


# Resting on the floor/stack, or on the partner's piece if that one is resting too.
# Sitting on a piece that is still falling doesn't count, otherwise you'd lock in mid-air.
func is_grounded() -> bool:
	return game.is_supported(self, [])


func get_cells() -> Array[Vector2i]:
	return current.get_cells() if current else ([] as Array[Vector2i])


# Three-corner rule. Only the locked stack counts as filled, not the other player's piece.
func detect_tspin() -> Scoring.Spin:
	if current.type != PieceData.Type.T or not last_move_was_rotation:
		return Scoring.Spin.NONE
	var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0), Vector2i(2, 2), Vector2i(0, 2)]
	# The two corners on the side the T points to, for each rotation (up, right, down, left).
	var front_corners: Array = [[0, 1], [1, 2], [2, 3], [3, 0]]
	var filled := 0
	var front := 0
	for i in 4:
		if not board.is_free(current.position + corners[i]):
			filled += 1
			if i in front_corners[current.rotation]:
				front += 1
	if filled < 3:
		return Scoring.Spin.NONE
	if front == 2 or last_kick_index == 4:
		return Scoring.Spin.FULL
	return Scoring.Spin.MINI


func _just_pressed(event: InputEvent, action: String) -> bool:
	var full_name := action_prefix + action
	return InputMap.has_action(full_name) and event.is_action_pressed(full_name)


func _held(action: String) -> bool:
	var full_name := action_prefix + action
	return InputMap.has_action(full_name) and Input.is_action_pressed(full_name)


func _handle_left_right(delta: float) -> void:
	var dir := int(_held("move_right")) - int(_held("move_left"))
	if dir != _das_dir:
		# Direction changed: move once now, then wait DAS before repeating.
		_das_dir = dir
		_das_timer = 0.0
		_arr_timer = 0.0
		if dir != 0:
			try_move(Vector2i(dir, 0))
		return
	if dir == 0:
		return
	_das_timer += delta
	if _das_timer < DAS:
		return
	_arr_timer += delta
	while _arr_timer >= ARR:
		_arr_timer -= ARR
		if not try_move(Vector2i(dir, 0)):
			_arr_timer = 0.0
			break


# Soft drop goes through the game so it can push the partner's piece along.
func _handle_soft_drop(delta: float) -> void:
	if not is_soft_dropping():
		_soft_drop_timer = 0.0
		return
	var interval: float = game.gravity_interval() / SOFT_DROP_FACTOR
	_soft_drop_timer += delta
	while _soft_drop_timer >= interval and current != null:
		_soft_drop_timer -= interval
		if game.push_down(self):
			game.add_drop_points(1)
		else:
			_soft_drop_timer = 0.0
			break


func _update_lock(delta: float) -> void:
	if not is_grounded():
		_lock_timer = 0.0
		return
	_lock_timer += delta
	if _lock_timer >= LOCK_DELAY or _lock_resets >= MAX_LOCK_RESETS:
		game.lock_pieces([self])


# Lock delay resets: reaching a new lowest row gives a full reset, moving or rotating
# while on the ground resets the timer but uses up one of the 15 resets.
func _after_move(was_grounded: bool, by_player: bool) -> void:
	if current.position.y > _lowest_y:
		_lowest_y = current.position.y
		_lock_resets = 0
		_lock_timer = 0.0
	elif by_player and was_grounded:
		_lock_timer = 0.0
		_lock_resets += 1


# Coloured outline on the piece plus a small P1/P2 tag above it.
func _draw() -> void:
	if current == null or game == null or not game.is_playing():
		return
	var cells := current.get_cells()
	var top_y := 999
	var min_x := 999
	var max_x := -999
	for c in cells:
		var rect := Rect2(Vector2(c.x, c.y - Board.HIDDEN) * Board.CELL, Vector2(Board.CELL, Board.CELL))
		draw_rect(rect.grow(-1), tag_color, false, 2.0)
		top_y = mini(top_y, c.y)
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
	var font := ThemeDB.fallback_font
	var font_size := 14
	var text_w := font.get_string_size(player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var x := (min_x + max_x + 1) * 0.5 * Board.CELL - text_w / 2.0
	var y := (top_y - Board.HIDDEN) * Board.CELL - 5
	draw_string_outline(font, Vector2(x, y), player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color.BLACK)
	draw_string(font, Vector2(x, y), player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tag_color)
