@tool
extends Node2D
# Grid and border of the board. It's a tool script so you can see it in the editor too.

@export var cols: int = 10:
	set(v):
		cols = v
		queue_redraw()
@export var rows: int = 20:
	set(v):
		rows = v
		queue_redraw()
@export var cell: int = 32
@export var line_color := Color(1, 1, 1, 0.06)
@export var border_color := Color(1, 1, 1, 0.5)


func _draw() -> void:
	var w := cols * cell
	var h := rows * cell
	for x in range(1, cols):
		draw_line(Vector2(x * cell, 0), Vector2(x * cell, h), line_color)
	for y in range(1, rows):
		draw_line(Vector2(0, y * cell), Vector2(w, y * cell), line_color)
	draw_rect(Rect2(-2, -2, w + 4, h + 4), border_color, false, 2.0)
