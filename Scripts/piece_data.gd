@tool
class_name PieceData
extends RefCounted
# Static data for the seven tetrominoes: shapes, spawn columns and SRS wall kicks.
# Everything is in cells, with y growing downwards like the rest of Godot.

enum Type { I, O, T, S, Z, J, L }

const COUNT := 7
const GARBAGE := 7  # grey tile in the atlas, used for the game over effect

# Spawn shape (rotation 0) of each piece inside its rotation box.
const SHAPES: Array = [
	[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)],  # I
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],  # O
	[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],  # T
	[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],  # S
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],  # Z
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],  # J
	[Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],  # L
]

const BOX_SIZE: Array[int] = [4, 2, 3, 3, 3, 3, 3]

# Left column of the box at spawn, for a standard 10-wide board.
# Player.spawn_position() shifts this to wherever that player spawns.
const SPAWN_X: Array[int] = [3, 4, 3, 3, 3, 3, 3]

# SRS kick tests for clockwise rotations (from -> from + 1), y already flipped.
const KICKS_JLSTZ: Array = [
	[Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, 2), Vector2i(-1, 2)],   # 0 -> R
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, -2), Vector2i(1, -2)],     # R -> 2
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, 2), Vector2i(1, 2)],      # 2 -> L
	[Vector2i(0, 0), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -2), Vector2i(-1, -2)],  # L -> 0
]
const KICKS_I: Array = [
	[Vector2i(0, 0), Vector2i(-2, 0), Vector2i(1, 0), Vector2i(-2, 1), Vector2i(1, -2)],    # 0 -> R
	[Vector2i(0, 0), Vector2i(-1, 0), Vector2i(2, 0), Vector2i(-1, -2), Vector2i(2, 1)],    # R -> 2
	[Vector2i(0, 0), Vector2i(2, 0), Vector2i(-1, 0), Vector2i(2, -1), Vector2i(-1, 2)],    # 2 -> L
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(-2, 0), Vector2i(1, 2), Vector2i(-2, -1)],    # L -> 0
]

# _rotations[type][rotation] -> the four cells. Built once when the class loads.
static var _rotations: Array = []


static func _static_init() -> void:
	for t in COUNT:
		var shape: Array[Vector2i] = []
		shape.assign(SHAPES[t])
		var states: Array = [shape]
		for i in 3:
			states.append(_rotate_cw(states[-1], BOX_SIZE[t]))
		_rotations.append(states)


# 90 degrees clockwise inside an n x n box: (x, y) -> (n - 1 - y, x)
static func _rotate_cw(cells: Array[Vector2i], n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		out.append(Vector2i(n - 1 - c.y, c.x))
	return out


static func get_cells(type: int, rotation: int) -> Array[Vector2i]:
	return _rotations[type][rotation]


# Offsets to try, in order, when rotating from one state to another.
static func get_kicks(type: int, from: int, to: int) -> Array:
	if type == Type.O:
		return [Vector2i.ZERO]
	var table: Array = KICKS_I if type == Type.I else KICKS_JLSTZ
	if to == posmod(from + 1, 4):
		return table[from]
	# Counter-clockwise a -> b uses the clockwise b -> a tests with the sign flipped.
	return table[to].map(func(k: Vector2i) -> Vector2i: return -k)
