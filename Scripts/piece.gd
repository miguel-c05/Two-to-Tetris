class_name Piece
extends RefCounted
## Peça ativa: tipo, rotação e posição (canto superior esquerdo da caixa).

var type: int
var rotation: int = 0
var position: Vector2i


func _init(t: int, spawn_pos: Vector2i) -> void:
	type = t
	position = spawn_pos


## Células ocupadas no tabuleiro para uma rotação/posição (por omissão, as atuais).
func get_cells(rot: int = -1, pos: Vector2i = Vector2i(-9999, -9999)) -> Array[Vector2i]:
	if rot < 0:
		rot = rotation
	if pos == Vector2i(-9999, -9999):
		pos = position
	var out: Array[Vector2i] = []
	for c in PieceData.get_cells(type, rot):
		out.append(c + pos)
	return out
