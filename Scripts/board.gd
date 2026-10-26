class_name Board
extends Node2D
# The well: stores the locked blocks, checks if cells are free and draws everything.
# It knows nothing about players or input, it just gets told what to draw.

const CELL := 32
const HIDDEN := 2  # rows above the visible area where pieces spawn
const VISIBLE_ROWS := 20
const ROWS := VISIBLE_ROWS + HIDDEN
const EMPTY := -1
const SOURCE_ID := 0

@export var cols: int = 10

var cells := PackedInt32Array()  # cells[y * cols + x] = piece type or EMPTY

@onready var frame: ColorRect = $Frame
@onready var grid_lines := $GridLines
@onready var board_layer: TileMapLayer = $BoardLayer
@onready var ghost_layer: TileMapLayer = $GhostLayer
@onready var piece_layer: TileMapLayer = $PieceLayer

var _rest_position: Vector2
var _shake_tween: Tween


func _ready() -> void:
	_rest_position = position
	frame.size = Vector2(cols * CELL, VISIBLE_ROWS * CELL)
	grid_lines.cols = cols
	grid_lines.rows = VISIBLE_ROWS
	reset()


func reset() -> void:
	cells.resize(cols * ROWS)
	cells.fill(EMPTY)
	render_board()
	clear_active()


func get_cell(c: Vector2i) -> int:
	return cells[c.y * cols + c.x]


# Inside the walls and empty. Anything above the top (y < 0) counts as free.
func is_free(c: Vector2i) -> bool:
	if c.x < 0 or c.x >= cols or c.y >= ROWS:
		return false
	return c.y < 0 or get_cell(c) == EMPTY


func is_valid(piece_cells: Array[Vector2i]) -> bool:
	for c in piece_cells:
		if not is_free(c):
			return false
	return true


# Writes a piece into the grid. Returns true if it locked completely inside the
# hidden rows, which is a "lock out" (game over).
func lock(piece_cells: Array[Vector2i], type: int) -> bool:
	var above_screen := true
	for c in piece_cells:
		if c.y >= 0:
			cells[c.y * cols + c.x] = type
		if c.y >= HIDDEN:
			above_screen = false
	return above_screen


# Removes full rows and drops everything above them. Returns how many were cleared.
func clear_full_lines() -> int:
	var kept := PackedInt32Array()
	kept.resize(cols * ROWS)
	kept.fill(EMPTY)
	var cleared := 0
	var dst := ROWS - 1
	for y in range(ROWS - 1, -1, -1):
		if _row_is_full(y):
			cleared += 1
			continue
		for x in cols:
			kept[dst * cols + x] = cells[y * cols + x]
		dst -= 1
	cells = kept
	return cleared


func _row_is_full(y: int) -> bool:
	for x in cols:
		if cells[y * cols + x] == EMPTY:
			return false
	return true


# Turns every block grey (game over).
func gray_out() -> void:
	for i in cells.size():
		if cells[i] != EMPTY:
			cells[i] = PieceData.GARBAGE
	render_board()


func render_board() -> void:
	board_layer.clear()
	for y in range(HIDDEN, ROWS):
		for x in cols:
			var type := cells[y * cols + x]
			if type != EMPTY:
				board_layer.set_cell(_to_layer(Vector2i(x, y)), SOURCE_ID, Vector2i(type, 0))


# pieces is a list of { "cells", "ghost", "type" }, one per falling piece.
# Ghosts go first so a piece is never hidden behind someone else's ghost.
func render_active(pieces: Array) -> void:
	clear_active()
	for piece in pieces:
		for c in piece.ghost:
			ghost_layer.set_cell(_to_layer(c), SOURCE_ID, Vector2i(piece.type, 0))
	for piece in pieces:
		for c in piece.cells:
			piece_layer.set_cell(_to_layer(c), SOURCE_ID, Vector2i(piece.type, 0))


func clear_active() -> void:
	piece_layer.clear()
	ghost_layer.clear()


# Small bump on hard drop.
func shake(strength: float = 4.0) -> void:
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	position = _rest_position + Vector2(0, strength)
	_shake_tween = create_tween()
	_shake_tween.tween_property(self, "position", _rest_position, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# Board rows include the hidden ones, the tile layers start at the first visible row.
func _to_layer(c: Vector2i) -> Vector2i:
	return Vector2i(c.x, c.y - HIDDEN)
