class_name Piece
extends RefCounted
# A falling piece: its shape, how it's rotated and where its box sits on the board.

var type: int
var rotation := 0
var position: Vector2i


func _init(piece_type: int, spawn_at: Vector2i) -> void:
	type = piece_type
	position = spawn_at


func get_cells() -> Array[Vector2i]:
	return cells_at(position, rotation)


# Same as get_cells() but for a position/rotation we want to try before committing to it.
func cells_at(pos: Vector2i, rot: int = rotation) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in PieceData.get_cells(type, rot):
		out.append(c + pos)
	return out
