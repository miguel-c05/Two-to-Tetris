class_name Board
extends Node2D
## Tabuleiro: guarda as células bloqueadas, valida posições e desenha.
## Não conhece jogadores nem input (para o modo cooperativo poder reutilizá-lo).

const CELL := 32
const HIDDEN := 2  ## linhas escondidas acima da área visível
const VISIBLE_ROWS := 20
const ROWS := VISIBLE_ROWS + HIDDEN
const EMPTY := -1
const SOURCE_ID := 0

@export var cols: int = 10

var cells := PackedInt32Array()  ## cells[y * cols + x] = tipo ou EMPTY

@onready var frame: ColorRect = $Frame
@onready var grid_lines: Node2D = $GridLines
@onready var board_layer: TileMapLayer = $BoardLayer
@onready var ghost_layer: TileMapLayer = $GhostLayer
@onready var piece_layer: TileMapLayer = $PieceLayer

var _base_position: Vector2
var _shake_tween: Tween


func _ready() -> void:
	_base_position = position
	frame.size = Vector2(cols * CELL, VISIBLE_ROWS * CELL)
	grid_lines.set("cols", cols)
	grid_lines.set("rows", VISIBLE_ROWS)
	reset()


func reset() -> void:
	cells.resize(cols * ROWS)
	cells.fill(EMPTY)
	render_board()
	piece_layer.clear()
	ghost_layer.clear()


func get_cell(c: Vector2i) -> int:
	return cells[c.y * cols + c.x]


func is_inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < cols and c.y < ROWS


## Livre = dentro das paredes e vazio. Acima do teto (y < 0) conta como livre.
func is_free(c: Vector2i) -> bool:
	if not is_inside(c):
		return false
	if c.y < 0:
		return true
	return get_cell(c) == EMPTY


func is_valid(piece_cells: Array[Vector2i]) -> bool:
	for c in piece_cells:
		if not is_free(c):
			return false
	return true


## Escreve a peça no tabuleiro. Devolve true se ficou toda nas linhas escondidas (lock out).
func lock(piece_cells: Array[Vector2i], type: int) -> bool:
	var all_hidden := true
	for c in piece_cells:
		if c.y >= 0:
			cells[c.y * cols + c.x] = type
		if c.y >= HIDDEN:
			all_hidden = false
	return all_hidden


## Remove as linhas cheias e desce as de cima. Devolve os índices das linhas limpas.
func clear_full_lines() -> Array[int]:
	var full: Array[int] = []
	for y in ROWS:
		var is_full := true
		for x in cols:
			if cells[y * cols + x] == EMPTY:
				is_full = false
				break
		if is_full:
			full.append(y)
	if full.is_empty():
		return full

	var new_cells := PackedInt32Array()
	new_cells.resize(cols * ROWS)
	new_cells.fill(EMPTY)
	var dst := ROWS - 1
	for y in range(ROWS - 1, -1, -1):
		if y in full:
			continue
		for x in cols:
			new_cells[dst * cols + x] = cells[y * cols + x]
		dst -= 1
	cells = new_cells
	return full


## Pinta todas as células ocupadas de cinzento (efeito de game over).
func gray_out() -> void:
	for i in cells.size():
		if cells[i] != EMPTY:
			cells[i] = PieceData.GARBAGE
	render_board()


func render_board() -> void:
	board_layer.clear()
	for y in range(HIDDEN, ROWS):
		for x in cols:
			var t := cells[y * cols + x]
			if t != EMPTY:
				board_layer.set_cell(_to_layer(Vector2i(x, y)), SOURCE_ID, Vector2i(t, 0))


func render_active(piece_cells: Array[Vector2i], ghost_cells: Array[Vector2i], type: int) -> void:
	piece_layer.clear()
	ghost_layer.clear()
	for c in ghost_cells:
		ghost_layer.set_cell(_to_layer(c), SOURCE_ID, Vector2i(type, 0))
	for c in piece_cells:
		piece_layer.set_cell(_to_layer(c), SOURCE_ID, Vector2i(type, 0))


func clear_active() -> void:
	piece_layer.clear()
	ghost_layer.clear()


## Pequeno abanão (hard drop).
func shake(strength: float = 4.0) -> void:
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	position = _base_position + Vector2(0, strength)
	_shake_tween = create_tween()
	_shake_tween.tween_property(self, "position", _base_position, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Coordenadas do tabuleiro -> coordenadas da TileMapLayer (linha visível 0 no topo do Frame).
func _to_layer(c: Vector2i) -> Vector2i:
	return Vector2i(c.x, c.y - HIDDEN)
