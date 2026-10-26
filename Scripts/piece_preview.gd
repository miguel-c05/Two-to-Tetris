@tool
extends Control
# Draws a single piece centred in the control. Used for the Hold box and the Next queue.

const BLOCKS := preload("res://Assets/blocks.png")
const TEX_CELL := 32

@export var cell_size: int = 20:
	set(v):
		cell_size = v
		queue_redraw()
@export var type: int = -1:  # -1 = empty
	set(v):
		type = v
		queue_redraw()


func _draw() -> void:
	if type < 0 or type >= PieceData.COUNT:
		return
	var shape := PieceData.get_cells(type, 0)
	var min_c := Vector2i(99, 99)
	var max_c := Vector2i(-99, -99)
	for c in shape:
		min_c = Vector2i(mini(min_c.x, c.x), mini(min_c.y, c.y))
		max_c = Vector2i(maxi(max_c.x, c.x), maxi(max_c.y, c.y))
	var piece_size := Vector2(max_c - min_c + Vector2i.ONE) * cell_size
	var offset := (size - piece_size) / 2.0
	var src := Rect2(type * TEX_CELL, 0, TEX_CELL, TEX_CELL)
	for c in shape:
		var pos := offset + Vector2(c - min_c) * cell_size
		draw_texture_rect_region(BLOCKS, Rect2(pos, Vector2(cell_size, cell_size)), src)
