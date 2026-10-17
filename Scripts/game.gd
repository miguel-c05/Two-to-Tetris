extends Node2D
## Jogo cooperativo: tudo o que é partilhado entre jogadores.
## - tabuleiro, fila de peças (7-bag), hold (slot e cooldown partilhados), pontuação, nível
## - gravidade (um relógio comum, aplicada de baixo para cima)
## - colisões entre peças ativas e empurrões (hard drop / soft drop)
## Cada jogador (player.gd) trata do seu input, DAS, soft drop e lock delay.

signal stats_changed(score: int, level: int, lines: int)
signal hold_changed(type: int, can_hold: bool)
signal next_changed(types: Array[int])
signal line_clear(text: String)
signal game_over(final_score: int)
signal paused_changed(paused: bool)

enum State { PLAYING, PAUSED, GAME_OVER }
enum Spin { NONE, MINI, FULL }

const NEXT_COUNT := 5
const LINES_PER_LEVEL := 10

## Pontos base (× nível) por nº de linhas.
const LINE_SCORES: Array[int] = [0, 100, 300, 500, 800]
const TSPIN_SCORES: Array[int] = [400, 800, 1200, 1600]
const TSPIN_MINI_SCORES: Array[int] = [100, 200, 400]

@export var start_level: int = 1

@onready var board: Board = $Board

var players: Array[Player] = []
var state: State = State.PLAYING
var bag := BagRandomizer.new()
var hold_type: int = -1
var can_hold: bool = true

var score: int = 0
var level: int = 1
var lines: int = 0
var combo: int = -1
var back_to_back: bool = false

var _gravity_t := 0.0


func _ready() -> void:
	for c in get_children():
		if c is Player:
			players.append(c)
			c.setup(self, board)
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
	_gravity_t = 0.0
	state = State.PLAYING
	for p in players:
		p.reset()
	for p in players:
		p.spawn(bag.next())
	stats_changed.emit(score, level, lines)
	hold_changed.emit(hold_type, can_hold)
	next_changed.emit(bag.peek(NEXT_COUNT))
	paused_changed.emit(false)
	_render()


func is_playing() -> bool:
	return state == State.PLAYING


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if _pressed_global(event, "restart"):
		new_game()
	elif _pressed_global(event, "pause"):
		toggle_pause()


func _process(delta: float) -> void:
	if state != State.PLAYING:
		return
	_apply_gravity(delta)
	for p in players:
		if state != State.PLAYING:
			return
		p.tick(delta)
	if state == State.PLAYING:
		_render()


# ---------------------------------------------------------------- colisões

## As células estão livres no tabuleiro e não tocam na peça de outro jogador?
func can_occupy(who: Player, cells: Array[Vector2i]) -> bool:
	if not board.is_valid(cells):
		return false
	for q in players:
		if q != who and q.current != null and _overlaps(cells, q.current.get_cells()):
			return false
	return true


func _overlaps(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	for c in a:
		if c in b:
			return true
	return false


## A peça de `p` está assente em algo fixo (tabuleiro, ou outra peça ativa que esteja assente)?
func is_supported(p: Player, visited: Array = []) -> bool:
	var below := p.current.get_cells(p.current.rotation, p.current.position + Vector2i.DOWN)
	if not board.is_valid(below):
		return true
	visited.append(p)
	for q in players:
		if q != p and q.current != null and q not in visited and _overlaps(below, q.current.get_cells()):
			if is_supported(q, visited):
				return true
	return false


## Posições atuais das peças ativas (Player -> Vector2i). Usado para simular sem mexer nas peças.
func _positions() -> Dictionary:
	var pos := {}
	for q in players:
		if q.current != null:
			pos[q] = q.current.position
	return pos


func _cells_at(q: Player, pos: Dictionary, dy: int = 0) -> Array[Vector2i]:
	return q.current.get_cells(q.current.rotation, pos[q] + Vector2i(0, dy))


## Grupo de peças que desce junto se `p` descer: `p` e todas as peças ativas
## que estão diretamente por baixo dela (e por baixo dessas, etc.).
func _push_group(p: Player, pos: Dictionary) -> Array[Player]:
	var group: Array[Player] = [p]
	var changed := true
	while changed:
		changed = false
		for q in group.duplicate():
			var below := _cells_at(q, pos, 1)
			for r: Player in pos.keys():
				if r not in group and _overlaps(below, _cells_at(r, pos)):
					group.append(r)
					changed = true
	return group


func _group_can_fall(group: Array[Player], pos: Dictionary) -> bool:
	for q in group:
		if not board.is_valid(_cells_at(q, pos, 1)):
			return false
	return true


## Simula um hard drop de `p`, empurrando as peças que estiverem no caminho.
## Devolve { "pos": posições finais, "involved": jogadores tocados, "dist": linhas descidas por p }.
func _simulate_drop(p: Player) -> Dictionary:
	var pos := _positions()
	var involved: Array[Player] = [p]
	var dist := 0
	while true:
		var group := _push_group(p, pos)
		for q in group:
			if q not in involved:
				involved.append(q)
		if not _group_can_fall(group, pos):
			break
		for q in group:
			pos[q] += Vector2i.DOWN
		dist += 1
	return {"pos": pos, "involved": involved, "dist": dist}


## Soft drop de uma linha: desce `p` e empurra as peças que estejam por baixo.
## Devolve false se o grupo já não pode descer.
func push_down(p: Player) -> bool:
	var pos := _positions()
	var group := _push_group(p, pos)
	if not _group_can_fall(group, pos):
		return false
	for q in group:
		q.shift_down()
	return true


## Hard drop: cai até assentar. Se a peça do companheiro estiver no caminho,
## é empurrada e as DUAS peças são pousadas de imediato.
func hard_drop(p: Player) -> void:
	if p.current == null:
		return
	var sim := _simulate_drop(p)
	var involved: Array[Player] = sim["involved"]
	for q in involved:
		var target: Vector2i = sim["pos"][q]
		if target != q.current.position:
			q.current.position = target
			q.last_move_was_rotation = false
	score += int(sim["dist"]) * 2
	board.shake()
	lock_pieces(involved)


# ---------------------------------------------------------------- hold

## Hold partilhado: um só slot e um só cooldown para os dois jogadores.
## Volta a ficar disponível quando QUALQUER jogador pousa uma peça.
func hold(p: Player) -> void:
	if not can_hold or p.current == null:
		return
	var t := p.current.type
	can_hold = false
	if hold_type == -1:
		hold_type = t
		p.spawn(bag.next())
		next_changed.emit(bag.peek(NEXT_COUNT))
	else:
		var old := hold_type
		hold_type = t
		p.spawn(old)
	hold_changed.emit(hold_type, can_hold)


# ---------------------------------------------------------------- lock e linhas

## Bloqueia uma ou mais peças (várias quando houve empurrão) e dá peças novas a esses jogadores.
func lock_pieces(who: Array) -> void:
	var spin := Spin.NONE
	var lock_out := false
	var locked: Array[Player] = []
	for q: Player in who:
		if q.current == null:
			continue
		spin = maxi(spin, _detect_tspin(q)) as Spin
		lock_out = board.lock(q.current.get_cells(), q.current.type) or lock_out
		q.current = null
		locked.append(q)
	if locked.is_empty():
		return
	var cleared := board.clear_full_lines().size()
	board.render_board()
	_resolve_overlaps()
	_add_score(cleared, spin)
	if lock_out:
		_game_over()
		return
	can_hold = true
	hold_changed.emit(hold_type, can_hold)
	for q in locked:
		if state != State.PLAYING:
			return
		q.spawn(bag.next())
	next_changed.emit(bag.peek(NEXT_COUNT))
	_render()


## Depois de limpar linhas, o tabuleiro desce e pode "entrar" numa peça ainda ativa
## (ex.: peça encaixada debaixo de uma saliência). Nesse caso, sobe-a até ficar livre.
func _resolve_overlaps() -> void:
	for q in players:
		if q.current == null:
			continue
		var guard := 0
		while not board.is_valid(q.current.get_cells()) and guard < Board.ROWS:
			q.current.position += Vector2i.UP
			guard += 1


func on_block_out() -> void:
	if state == State.PLAYING:
		_game_over()


## Segundos por linha (fórmula Guideline).
func gravity_interval() -> float:
	var l := float(level - 1)
	return maxf(pow(0.8 - l * 0.007, l), 0.0005)


func get_ghost_cells(p: Player) -> Array[Vector2i]:
	var sim := _simulate_drop(p)
	return p.current.get_cells(p.current.rotation, sim["pos"][p])


func add_drop_points(n: int) -> void:
	score += n
	stats_changed.emit(score, level, lines)


# ---------------------------------------------------------------- internos

func _pressed_global(event: InputEvent, action: String) -> bool:
	return InputMap.has_action(action) and event.is_action_pressed(action)


## Gravidade comum a todos. As peças mais baixas descem primeiro, para que uma peça
## pousada em cima da outra acompanhe a queda. Quem está em soft drop usa o seu próprio ritmo.
func _apply_gravity(delta: float) -> void:
	_gravity_t += delta
	var interval := gravity_interval()
	while _gravity_t >= interval:
		_gravity_t -= interval
		var order: Array = players.filter(
			func(q: Player) -> bool: return q.current != null and not q.is_soft_dropping())
		order.sort_custom(func(a: Player, b: Player) -> bool: return _bottom(a) > _bottom(b))
		var moved := false
		for q in order:
			if q.try_move(Vector2i.DOWN, false):
				moved = true
		if not moved:
			_gravity_t = minf(_gravity_t, interval)
			break


func _bottom(q: Player) -> int:
	var m := -999
	for c in q.current.get_cells():
		m = maxi(m, c.y)
	return m


## Regra dos 3 cantos (só o tabuleiro conta como "ocupado").
func _detect_tspin(q: Player) -> Spin:
	var piece := q.current
	if piece.type != PieceData.Type.T or not q.last_move_was_rotation:
		return Spin.NONE
	var corners: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0), Vector2i(2, 2), Vector2i(0, 2)]
	# Cantos "da frente" (para onde aponta o T) por rotação: 0 cima, 1 dir, 2 baixo, 3 esq.
	var front_idx: Array = [[0, 1], [1, 2], [2, 3], [3, 0]]
	var filled := 0
	var front := 0
	for i in 4:
		if not board.is_free(piece.position + corners[i]):
			filled += 1
			if i in front_idx[piece.rotation]:
				front += 1
	if filled < 3:
		return Spin.NONE
	if front == 2 or q.last_kick_index == 4:
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
			points = LINE_SCORES[mini(cleared, 4)]
			label = ["", "SINGLE", "DOUBLE", "TRIPLE", "TETRIS"][mini(cleared, 4)]
			if cleared > 4:
				# Com duas peças pousadas ao mesmo tempo é possível limpar mais de 4 linhas.
				points = LINE_SCORES[4] + (cleared - 4) * 400
				label = "%d LINES!" % cleared

	if cleared > 0:
		var difficult := cleared >= 4 or spin != Spin.NONE
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
	for q in players:
		q.queue_redraw()
	game_over.emit(score)


func _render() -> void:
	var pieces: Array = []
	for q in players:
		if q.current != null:
			pieces.append({"cells": q.current.get_cells(), "ghost": get_ghost_cells(q), "type": q.current.type})
	board.render_active(pieces)
