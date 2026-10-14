@tool
class_name PieceData
extends RefCounted
## Dados estáticos das 7 peças: formas, cores, posições de spawn e kicks SRS.
## Coordenadas em células, com y a crescer para baixo (convenção do Godot).

enum Type { I, O, T, S, Z, J, L }

const COUNT := 7
const GARBAGE := 7  ## índice do tile cinzento no atlas (lixo / game over)

## Estado de spawn (rotação 0) de cada peça, dentro da sua caixa.
const SHAPES: Array = [
	[Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)],  # I
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],  # O
	[Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],  # T
	[Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],  # S
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],  # Z
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],  # J
	[Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],  # L
]

## Lado da caixa de rotação de cada peça.
const BOX_SIZE: Array[int] = [4, 2, 3, 3, 3, 3, 3]

## Coluna do canto esquerdo da caixa no spawn (tabuleiro de 10 colunas).
const SPAWN_X: Array[int] = [3, 4, 3, 3, 3, 3, 3]

const COLORS: Array[Color] = [
	Color(0.0, 0.94, 0.94),  # I ciano
	Color(0.94, 0.94, 0.0),  # O amarelo
	Color(0.63, 0.0, 0.94),  # T roxo
	Color(0.0, 0.94, 0.0),   # S verde
	Color(0.94, 0.0, 0.0),   # Z vermelho
	Color(0.0, 0.31, 0.94),  # J azul
	Color(0.94, 0.63, 0.0),  # L laranja
]

const NAMES: Array[String] = ["I", "O", "T", "S", "Z", "J", "L"]

## Kicks SRS para rotação horária (from -> from+1), já com y para baixo.
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
## Rotação 180: não há tabela oficial; testes simples.
const KICKS_180: Array = [Vector2i(0, 0), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]

## _rotations[type][rot] -> Array[Vector2i]
static var _rotations: Array = []


static func _static_init() -> void:
	for t in COUNT:
		var base: Array[Vector2i] = []
		base.assign(SHAPES[t])
		var states: Array = [base]
		for r in 3:
			states.append(rotate_cw(states[-1], BOX_SIZE[t]))
		_rotations.append(states)


## Rotação de 90º horária numa caixa n×n: (x, y) -> (n-1-y, x)
static func rotate_cw(cells: Array[Vector2i], n: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in cells:
		out.append(Vector2i(n - 1 - c.y, c.x))
	return out


static func get_cells(type: int, rot: int) -> Array[Vector2i]:
	return _rotations[type][rot]


## Lista de offsets a testar ao rodar de `from` para `to`.
static func get_kicks(type: int, from: int, to: int) -> Array:
	if type == Type.O:
		return [Vector2i.ZERO]
	if posmod(to - from, 4) == 2:
		return KICKS_180
	var table: Array = KICKS_I if type == Type.I else KICKS_JLSTZ
	if to == posmod(from + 1, 4):
		return table[from]
	# Anti-horário a->b = horário b->a com o sinal trocado.
	return table[to].map(func(k: Vector2i) -> Vector2i: return -k)
