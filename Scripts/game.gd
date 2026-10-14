extends Node2D
## Controlador do jogo: input, gravidade, lock delay, hold, SRS, pontuação.
## Fica no nó Main. O Board só guarda dados e desenha.

signal stats_changed(score: int, level: int, lines: int)
signal hold_changed(type: int, can_hold: bool)
signal next_changed(types: Array[int])
signal line_clear(text: String)
signal game_over(final_score: int)
signal paused_changed(paused: bool)

enum State { PLAYING, PAUSED, GAME_OVER }
enum Spin { NONE, MINI, FULL }

const DAS := 0.167
const ARR := 0.033
const SOFT_DROP_FACTOR := 20.0
const LOCK_DELAY := 0.5
const MAX_LOCK_RESETS := 15
const NEXT_COUNT := 5
const LINES_PER_LEVEL := 10

## Pontos base (× nível) por nº de linhas.
const LINE_SCORES: Array[int] = [0, 100, 300, 500, 800]
const TSPIN_SCORES: Array[int] = [400, 800, 1200, 1600]
const TSPIN_MINI_SCORES: Array[int] = [100, 200, 400]

@export var start_level: int = 1
## Prefixo das ações de input deste jogador ("p1_", "p2_", ...).
## As ações globais (pause, restart) não usam prefixo.
@export var action_prefix: String = "p1_"

@onready var board: Board = $Board

var state: State = State.PLAYING
var bag := BagRandomizer.new()
var current: Piece
var hold_type: int = -1
var can_hold: bool = true

var score: int = 0
var level: int = 1
var lines: int = 0
var combo: int = -1
var back_to_back: bool = false

var _gravity_t := 0.0
var _lock_t := 0.0
var _lock_resets := 0
var _lowest_y := 0
var _das_dir := 0
var _das_t := 0.0
var _arr_t := 0.0
var _last_move_was_rotation := false
var _last_kick_index := 0


func _ready() -> void:
	new_game()


# ---------------------------------------------------------------- ciclo de jogo

func new_game() -> void:
	board.reset()
	bag.reset()
	hold_type = -1
	can_hold = true
	score = 0
	level = start_level
	lines = 0
	combo = -1
	back_to_back = false
	_das_dir = 0
	state = State.PLAYING
	stats_changed.emit(score, level, lines)
	hold_changed.emit(hold_type, can_hold)
	paused_changed.emit(false)
	spawn_next()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if _pressed_global(event, "restart"):
		new_game()
		return
	if _pressed_global(event, "pause"):
		toggle_pause()
		return
	if state != State.PLAYING:
		return
	if _pressed(event, "hard_drop"):
		hard_drop()
	elif _pressed(event, "rotate_cw"):
		try_rotate(1)
	elif _pressed(event, "rotate_ccw"):
		try_rotate(-1)
	elif _pressed(event, "rotate_180"):
		try_rotate(2)
	elif _pressed(event, "hold"):
		hold_piece()


func _process(delta: float) -> void:
	if state != State.PLAYING or current == null:
		return
	_handle_horizontal(delta)
	if state != State.PLAYING:
		return
	_apply_gravity(delta)
	if state != State.PLAYING:
		return
	_update_lock(delta)
	if state == State.PLAYING:
		_render()


# ---------------------------------------------------------------- peças

func spawn_piece(type: int) -> void:
	current = Piece.new(type, Vector2i(PieceData.SPAWN_X[type], 0))
	_gravity_t = 0.0
	_lock_t = 0.0
	_lock_resets = 0
	_last_move_was_rotation = false
	if not board.is_valid(current.get_cells()):
		_game_over()  # block out
		return
	# Guideline: a peça desce uma linha logo após aparecer, se puder.
	var below := current.position + Vector2i.DOWN
	if board.is_valid(current.get_cells(current.rotation, below)):
		current.position = below
	_lowest_y = current.position.y
	_render()


func spawn_next() -> void:
	spawn_piece(bag.next())
	next_changed.emit(bag.peek(NEXT_COUNT))


func try_move(d: Vector2i, by_player: bool = true) -> bool:
	var was_grounded := is_grounded()
	var p := current.position + d
	if not board.is_valid(current.get_cells(current.rotation, p)):
		return false
	current.position = p
	_last_move_was_rotation = false
	_after_manipulation(was_grounded, by_player)
	return true


## dir: 1 = horário, -1 = anti-horário, 2 = 180º
func try_rotate(dir: int) -> bool:
	if current.type == PieceData.Type.O:
		return false
	var was_grounded := is_grounded()
	var from := current.rotation
	var to := posmod(from + dir, 4)
	var kicks := PieceData.get_kicks(current.type, from, to)
	for i in kicks.size():
		var p: Vector2i = current.position + kicks[i]
		if board.is_valid(current.get_cells(to, p)):
			current.rotation = to
			current.position = p
			_last_move_was_rotation = true
			_last_kick_index = i
			_after_manipulation(was_grounded, true)
			return true
	return false


func hard_drop() -> void:
	var dist := 0
	while board.is_valid(current.get_cells(current.rotation, current.position + Vector2i.DOWN)):
		current.position += Vector2i.DOWN
		dist += 1
	if dist > 0:
		_last_move_was_rotation = false
	score += dist * 2
	board.shake()
	lock_piece()


func hold_piece() -> void:
	if not can_hold:
		return
	var old := hold_type
	hold_type = current.type
	can_hold = false
	if old == -1:
		spawn_next()
	else:
		spawn_piece(old)
	hold_changed.emit(hold_type, can_hold)


func lock_piece() -> void:
	var piece_cells := current.get_cells()
	var spin := _detect_tspin()
	var lock_out := board.lock(piece_cells, current.type)
	var cleared := board.clear_full_lines().size()
	board.render_board()
	_add_score(cleared, spin)
	if lock_out:
		_game_over()
		return
	can_hold = true
	hold_changed.emit(hold_type, can_hold)
	spawn_next()


# ---------------------------------------------------------------- consultas

func is_grounded() -> bool:
	return not board.is_valid(current.get_cells(current.rotation, current.position + Vector2i.DOWN))


func get_ghost_cells() -> Array[Vector2i]:
	var p := current.position
	while board.is_valid(current.get_cells(current.rotation, p + Vector2i.DOWN)):
		p += Vector2i.DOWN
	return current.get_cells(current.rotation, p)


## Segundos por linha (fórmula Guideline).
func gravity_interval() -> float:
	var l := float(level - 1)
	return maxf(pow(0.8 - l * 0.007, l), 0.0005)


# ---------------------------------------------------------------- internos

func _pressed(event: InputEvent, action: String) -> bool:
	var a := action_prefix + action
	return InputMap.has_action(a) and event.is_action_pressed(a)


func _pressed_global(event: InputEvent, action: String) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action)


func _held(action: String) -> bool:
	var a := action_prefix + action
	return InputMap.has_action(a) and Input.is_action_pressed(a)


func _handle_horizontal(delta: float) -> void:
	var dir := int(_held("move_right")) - int(_held("move_left"))
	if dir != _das_dir:
		_das_dir = dir
		_das_t = 0.0
		_arr_t = 0.0
		if dir != 0:
			try_move(Vector2i(dir, 0))
		return
	if dir == 0:
		return
	_das_t += delta
	if _das_t < DAS:
		return
	_arr_t += delta
	while _arr_t >= ARR:
		_arr_t -= ARR
		if not try_move(Vector2i(dir, 0)):
			_arr_t = 0.0
			break


func _apply_gravity(delta: float) -> void:
	var soft := _held("soft_drop")
	var interval := gravity_interval() / (SOFT_DROP_FACTOR if soft else 1.0)
	_gravity_t += delta
	while _gravity_t >= interval:
		_gravity_t -= interval
		if try_move(Vector2i.DOWN, false):
			if soft:
				score += 1
				stats_changed.emit(score, level, lines)
		else:
			_gravity_t = 0.0
			break


func _update_lock(delta: float) -> void:
	if not is_grounded():
		_lock_t = 0.0
		return
	_lock_t += delta
	if _lock_t >= LOCK_DELAY or _lock_resets >= MAX_LOCK_RESETS:
		lock_piece()


## Regras de reset do lock delay (Extended Placement).
func _after_manipulation(was_grounded: bool, by_player: bool) -> void:
	if current.position.y > _lowest_y:
		_lowest_y = current.position.y
		_lock_resets = 0
		_lock_t = 0.0
	elif by_player and was_grounded:
		_lock_t = 0.0
		_lock_resets += 1


## Regra dos 3 cantos.
func _detect_tspin() -> Spin:
	if current.type != PieceData.Type.T or not _last_move_was_rotation:
		return Spin.NONE
	var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0), Vector2i(2, 2), Vector2i(0, 2)]
	# Cantos "da frente" (para onde aponta o T) por rotação: 0 cima, 1 dir, 2 baixo, 3 esq.
	var front_idx: Array = [[0, 1], [1, 2], [2, 3], [3, 0]]
	var filled := 0
	var front := 0
	for i in 4:
		if not board.is_free(current.position + corners[i]):
			filled += 1
			if i in front_idx[current.rotation]:
				front += 1
	if filled < 3:
		return Spin.NONE
	if front == 2 or _last_kick_index == 4:
		return Spin.FULL
	return Spin.MINI


func _add_score(cleared: int, spin: Spin) -> void:
	var points := 0
	var combo_bonus := 0
	var label := ""
	match spin:
		Spin.FULL:
			points = TSPIN_SCORES[mini(cleared, 3)]
			label = "T-SPIN " + ["", "SINGLE", "DOUBLE", "TRIPLE"][mini(cleared, 3)]
		Spin.MINI:
			points = TSPIN_MINI_SCORES[mini(cleared, 2)]
			label = "T-SPIN MINI " + ["", "SINGLE", "DOUBLE"][mini(cleared, 2)]
		_:
			points = LINE_SCORES[cleared]
			label = ["", "SINGLE", "DOUBLE", "TRIPLE", "TETRIS"][cleared]

	if cleared > 0:
		var difficult := cleared == 4 or spin != Spin.NONE
		if difficult:
			if back_to_back:
				points = int(points * 1.5)
				label = "B2B " + label
			back_to_back = true
		else:
			back_to_back = false
		combo += 1
		if combo > 0:
			combo_bonus = 50 * combo * level
			label += "\nCOMBO x%d" % combo
	else:
		combo = -1

	score += points * level + combo_bonus
	lines += cleared
	level = start_level + lines / LINES_PER_LEVEL
	stats_changed.emit(score, level, lines)
	label = label.strip_edges()
	if label != "":
		line_clear.emit(label)


func toggle_pause() -> void:
	if state == State.PLAYING:
		state = State.PAUSED
		paused_changed.emit(true)
	elif state == State.PAUSED:
		state = State.PLAYING
		paused_changed.emit(false)


func _game_over() -> void:
	state = State.GAME_OVER
	board.clear_active()
	board.gray_out()
	game_over.emit(score)


func _render() -> void:
	board.render_active(current.get_cells(), get_ghost_cells(), current.type)
