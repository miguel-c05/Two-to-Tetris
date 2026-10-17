class_name Player
extends Node2D
## Um jogador: a sua peça ativa, input (com prefixo próprio), DAS/ARR, soft drop e lock delay.
## Tudo o que é partilhado (tabuleiro, fila, hold, pontuação, colisões entre peças) fica no Game.

const DAS := 0.167
const ARR := 0.033
const SOFT_DROP_FACTOR := 20.0
const LOCK_DELAY := 0.5
const MAX_LOCK_RESETS := 15

@export var player_name: String = "P1"
## Prefixo das ações no Input Map ("p1_", "p2_").
@export var action_prefix: String = "p1_"
## Coluna central onde as peças deste jogador nascem.
@export var spawn_center: int = 12
@export var tag_color: Color = Color(1.0, 0.65, 0.25)

var game: Node       ## Main (game.gd)
var board: Board
var current: Piece = null
var waiting_type: int = -1   ## peça à espera que o spawn fique livre

var last_move_was_rotation := false
var last_kick_index := 0

var _lock_t := 0.0
var _lock_resets := 0
var _lowest_y := 0
var _das_dir := 0
var _das_t := 0.0
var _arr_t := 0.0
var _soft_t := 0.0


func setup(g: Node, b: Board) -> void:
	game = g
	board = b
	z_index = 10


func reset() -> void:
	current = null
	waiting_type = -1
	_das_dir = 0
	_soft_t = 0.0
	queue_redraw()


# ---------------------------------------------------------------- spawn

func spawn_position(type: int) -> Vector2i:
	# SPAWN_X está pensado para um tabuleiro de 10 colunas (centro na coluna 5).
	return Vector2i(spawn_center - 5 + PieceData.SPAWN_X[type], 0)


## Recebe uma peça nova. Se o companheiro estiver em cima do spawn, espera.
func spawn(type: int) -> void:
	current = null
	waiting_type = type
	try_spawn_waiting()


func try_spawn_waiting() -> bool:
	if waiting_type < 0:
		return false
	var p := Piece.new(waiting_type, spawn_position(waiting_type))
	if not board.is_valid(p.get_cells()):
		game.on_block_out()
		return false
	if not game.can_occupy(self, p.get_cells()):
		return false  # o companheiro está no spawn: tenta outra vez no próximo frame
	current = p
	waiting_type = -1
	_lock_t = 0.0
	_lock_resets = 0
	_soft_t = 0.0
	last_move_was_rotation = false
	# Guideline: desce uma linha logo após aparecer, se puder.
	var below := current.position + Vector2i.DOWN
	if game.can_occupy(self, current.get_cells(current.rotation, below)):
		current.position = below
	_lowest_y = current.position.y
	return true


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or game == null or not game.is_playing() or current == null:
		return
	if _pressed(event, "hard_drop"):
		game.hard_drop(self)
	elif _pressed(event, "rotate_cw"):
		try_rotate(1)
	elif _pressed(event, "rotate_ccw"):
		try_rotate(-1)
	elif _pressed(event, "rotate_180"):
		try_rotate(2)
	elif _pressed(event, "hold"):
		game.hold(self)


## Chamado pelo Game a cada frame (a ordem entre jogadores é controlada lá).
func tick(delta: float) -> void:
	position = board.position  # acompanha o abanão do tabuleiro
	if current == null:
		try_spawn_waiting()
	if current == null:
		queue_redraw()
		return
	_handle_horizontal(delta)
	if current == null or not game.is_playing():
		return
	_handle_soft_drop(delta)
	if current == null or not game.is_playing():
		return
	_update_lock(delta)
	queue_redraw()


func is_soft_dropping() -> bool:
	return _held("soft_drop")


# ---------------------------------------------------------------- movimento

func try_move(d: Vector2i, by_player: bool = true) -> bool:
	var was_grounded := is_grounded()
	var p := current.position + d
	if not game.can_occupy(self, current.get_cells(current.rotation, p)):
		return false
	current.position = p
	last_move_was_rotation = false
	_after_manipulation(was_grounded, by_player)
	return true


## Desce uma linha sem testar colisões (usado pelo Game quando empurra um grupo de peças).
func shift_down() -> void:
	var was_grounded := is_grounded()
	current.position += Vector2i.DOWN
	last_move_was_rotation = false
	_after_manipulation(was_grounded, false)


## dir: 1 = horário, -1 = anti-horário, 2 = 180º
func try_rotate(dir: int) -> bool:
	if current == null or current.type == PieceData.Type.O:
		return false
	var was_grounded := is_grounded()
	var from := current.rotation
	var to := posmod(from + dir, 4)
	var kicks := PieceData.get_kicks(current.type, from, to)
	for i in kicks.size():
		var p: Vector2i = current.position + kicks[i]
		if game.can_occupy(self, current.get_cells(to, p)):
			current.rotation = to
			current.position = p
			last_move_was_rotation = true
			last_kick_index = i
			_after_manipulation(was_grounded, true)
			return true
	return false


## Apoiado = assente no tabuleiro, ou em cima da peça do companheiro que, por sua vez,
## está apoiada. Uma peça em cima de outra que ainda está a cair NÃO conta, por isso
## nunca fica bloqueada a flutuar.
func is_grounded() -> bool:
	return game.is_supported(self, [])


func get_cells() -> Array[Vector2i]:
	return current.get_cells() if current else ([] as Array[Vector2i])


# ---------------------------------------------------------------- internos

func _pressed(event: InputEvent, action: String) -> bool:
	var a := action_prefix + action
	return InputMap.has_action(a) and event.is_action_pressed(a)


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


## Soft drop: desce à velocidade de soft drop e, se a peça do companheiro estiver
## por baixo, empurra-a também (o Game trata do grupo).
func _handle_soft_drop(delta: float) -> void:
	if not is_soft_dropping():
		_soft_t = 0.0
		return
	var interval: float = game.gravity_interval() / SOFT_DROP_FACTOR
	_soft_t += delta
	while _soft_t >= interval and current != null:
		_soft_t -= interval
		if game.push_down(self):
			game.add_drop_points(1)
		else:
			_soft_t = 0.0
			break


func _update_lock(delta: float) -> void:
	if not is_grounded():
		_lock_t = 0.0
		return
	_lock_t += delta
	if _lock_t >= LOCK_DELAY or _lock_resets >= MAX_LOCK_RESETS:
		game.lock_pieces([self])


## Regras de reset do lock delay (Extended Placement).
func _after_manipulation(was_grounded: bool, by_player: bool) -> void:
	if current.position.y > _lowest_y:
		_lowest_y = current.position.y
		_lock_resets = 0
		_lock_t = 0.0
	elif by_player and was_grounded:
		_lock_t = 0.0
		_lock_resets += 1


# ---------------------------------------------------------------- desenho

## Contorno colorido nas células da peça + etiqueta com o nome do jogador.
func _draw() -> void:
	if current == null or game == null or not game.is_playing():
		return
	var cells := current.get_cells()
	var top := Vector2i(999, 999)
	var min_x := 999
	var max_x := -999
	for c in cells:
		var r := Rect2(Vector2(c.x, c.y - Board.HIDDEN) * Board.CELL, Vector2(Board.CELL, Board.CELL))
		draw_rect(r.grow(-1), tag_color, false, 2.0)
		if c.y < top.y:
			top = c
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
	var font := ThemeDB.fallback_font
	var fs := 14
	var text_w := font.get_string_size(player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var cx := (min_x + max_x + 1) * 0.5 * Board.CELL
	var y := (top.y - Board.HIDDEN) * Board.CELL - 5
	draw_string_outline(font, Vector2(cx - text_w / 2.0, y), player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
	draw_string(font, Vector2(cx - text_w / 2.0, y), player_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tag_color)
