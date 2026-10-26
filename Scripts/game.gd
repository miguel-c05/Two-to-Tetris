class_name Game
extends Node2D
# The co-op game. Holds everything the two players share: the board, the piece
# queue, the hold slot, gravity, scoring, and the rules for when two falling
# pieces touch (collisions and pushing). Each Player handles its own input.

signal stats_changed(score: int, level: int, lines: int)
signal hold_changed(type: int, can_hold: bool)
signal next_changed(types: Array[int])
signal line_clear(text: String)
signal game_over(final_score: int)
signal paused_changed(paused: bool)

enum State { PLAYING, PAUSED, GAME_OVER }

const NEXT_COUNT := 5

@export var start_level: int = 1

@onready var board: Board = $Board

var players: Array[Player] = []
var state := State.PLAYING
var bag := BagRandomizer.new()
var scoring := Scoring.new()
var hold_type := -1
var can_hold := true  # one cooldown for both players, see hold()

var _gravity_timer := 0.0

var score: int:
	get: return scoring.score
var level: int:
	get: return scoring.level
var lines: int:
	get: return scoring.lines


# Result of simulating a hard drop (see _simulate_drop).
class DropResult:
	var positions := {}                 # Player -> where its piece ends up
	var involved: Array[Player] = []    # the dropping player plus anyone pushed
	var distance := 0                   # rows the dropping piece fell


func _ready() -> void:
	for child in get_children():
		if child is Player:
			players.append(child)
			child.setup(self, board)
	new_game()


func new_game() -> void:
	board.reset()
	bag.reset()
	scoring.reset(start_level)
	hold_type = -1
	can_hold = true
	_gravity_timer = 0.0
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
	if event.is_action_pressed("restart"):
		new_game()
	elif event.is_action_pressed("pause"):
		toggle_pause()


func _process(delta: float) -> void:
	if not is_playing():
		return
	_apply_gravity(delta)
	for p in players:
		if not is_playing():
			return
		p.tick(delta)
	if is_playing():
		_render()


func toggle_pause() -> void:
	if state == State.PLAYING:
		state = State.PAUSED
		paused_changed.emit(true)
	elif state == State.PAUSED:
		state = State.PLAYING
		paused_changed.emit(false)


# --- collisions -------------------------------------------------------------

# Free on the board and not overlapping anyone else's falling piece.
func can_occupy(who: Player, cells: Array[Vector2i]) -> bool:
	if not board.is_valid(cells):
		return false
	for other in players:
		if other != who and other.current != null and _overlaps(cells, other.current.get_cells()):
			return false
	return true


# Is p's piece resting on something solid? That's either the stack, or another
# falling piece that is itself resting on something.
func is_supported(p: Player, visited: Array = []) -> bool:
	var below := p.current.cells_at(p.current.position + Vector2i.DOWN)
	if not board.is_valid(below):
		return true
	visited.append(p)
	for other in players:
		if other == p or other.current == null or other in visited:
			continue
		if _overlaps(below, other.current.get_cells()) and is_supported(other, visited):
			return true
	return false


func _overlaps(a: Array[Vector2i], b: Array[Vector2i]) -> bool:
	for c in a:
		if c in b:
			return true
	return false


# --- pushing ----------------------------------------------------------------
# These work on a copy of the positions (Player -> Vector2i) so we can try a
# drop without moving anything.

func _current_positions() -> Dictionary:
	var positions := {}
	for p in players:
		if p.current != null:
			positions[p] = p.current.position
	return positions


func _cells_in(p: Player, positions: Dictionary, dy: int = 0) -> Array[Vector2i]:
	return p.current.cells_at(positions[p] + Vector2i(0, dy))


# If p moves down, which pieces have to move with it? p itself, whatever is right
# under it, whatever is under that, and so on.
func _push_group(p: Player, positions: Dictionary) -> Array[Player]:
	var group: Array[Player] = [p]
	var grew := true
	while grew:
		grew = false
		for member in group.duplicate():
			var below := _cells_in(member, positions, 1)
			for other: Player in positions.keys():
				if other not in group and _overlaps(below, _cells_in(other, positions)):
					group.append(other)
					grew = true
	return group


func _group_can_fall(group: Array[Player], positions: Dictionary) -> bool:
	for p in group:
		if not board.is_valid(_cells_in(p, positions, 1)):
			return false
	return true


func _simulate_drop(p: Player) -> DropResult:
	var result := DropResult.new()
	result.positions = _current_positions()
	result.involved = [p]
	while true:
		var group := _push_group(p, result.positions)
		for member in group:
			if member not in result.involved:
				result.involved.append(member)
		if not _group_can_fall(group, result.positions):
			break
		for member in group:
			result.positions[member] += Vector2i.DOWN
		result.distance += 1
	return result


# One row of soft drop. Pushes the partner down too if they're underneath.
# Returns false when nothing could move.
func push_down(p: Player) -> bool:
	var positions := _current_positions()
	var group := _push_group(p, positions)
	if not _group_can_fall(group, positions):
		return false
	for member in group:
		member.shift_down()
	return true


# Drops straight down. If the partner's piece is in the way it gets pushed
# down too, and both pieces lock immediately.
func hard_drop(p: Player) -> void:
	if p.current == null:
		return
	var drop := _simulate_drop(p)
	for member in drop.involved:
		member.drop_to(drop.positions[member])
	scoring.score += drop.distance * 2
	board.shake()
	lock_pieces(drop.involved)


func get_ghost_cells(p: Player) -> Array[Vector2i]:
	var drop := _simulate_drop(p)
	return p.current.cells_at(drop.positions[p])


func add_drop_points(points: int) -> void:
	scoring.score += points
	stats_changed.emit(score, level, lines)


# --- hold -------------------------------------------------------------------

# One slot for both players. Once anyone uses it, it stays locked until
# someone (either player) locks a piece.
func hold(p: Player) -> void:
	if not can_hold or p.current == null:
		return
	var type := p.current.type
	can_hold = false
	if hold_type == -1:
		hold_type = type
		p.spawn(bag.next())
		next_changed.emit(bag.peek(NEXT_COUNT))
	else:
		var swapped := hold_type
		hold_type = type
		p.spawn(swapped)
	hold_changed.emit(hold_type, can_hold)


# --- locking ----------------------------------------------------------------

# Locks one piece, or several when a hard drop pushed the partner along.
# Lines are only checked after all of them are in, which is how you get
# more than four lines from one drop.
func lock_pieces(who: Array) -> void:
	var spin := Scoring.Spin.NONE
	var lock_out := false
	var locked: Array[Player] = []
	for p: Player in who:
		if p.current == null:
			continue
		spin = maxi(spin, p.detect_tspin()) as Scoring.Spin
		lock_out = board.lock(p.current.get_cells(), p.current.type) or lock_out
		p.current = null
		locked.append(p)
	if locked.is_empty():
		return

	var cleared := board.clear_full_lines()
	board.render_board()
	_lift_pieces_out_of_stack()
	var text := scoring.add_clear(cleared, spin)
	stats_changed.emit(score, level, lines)
	if text != "":
		line_clear.emit(text)
	if lock_out:
		_end_game()
		return

	can_hold = true
	hold_changed.emit(hold_type, can_hold)
	for p in locked:
		if not is_playing():
			return
		p.spawn(bag.next())
	next_changed.emit(bag.peek(NEXT_COUNT))
	_render()


# When rows are cleared the stack moves down, and it can end up inside a piece
# that is still falling (e.g. one tucked under an overhang). Push it back up.
func _lift_pieces_out_of_stack() -> void:
	for p in players:
		if p.current == null:
			continue
		var steps := 0
		while not board.is_valid(p.current.get_cells()) and steps < Board.ROWS:
			p.current.position += Vector2i.UP
			steps += 1


func on_block_out() -> void:
	if is_playing():
		_end_game()


func _end_game() -> void:
	state = State.GAME_OVER
	board.clear_active()
	board.gray_out()
	for p in players:
		p.queue_redraw()
	game_over.emit(score)


# --- gravity ----------------------------------------------------------------

# Seconds per row, from the Guideline formula.
func gravity_interval() -> float:
	var l := float(level - 1)
	return maxf(pow(0.8 - l * 0.007, l), 0.0005)


# Same clock for everyone. Lower pieces fall first, so a piece sitting on top of
# the other one follows it down instead of being left behind for a frame.
# Whoever is soft dropping is skipped, they move at their own speed.
func _apply_gravity(delta: float) -> void:
	_gravity_timer += delta
	var interval := gravity_interval()
	while _gravity_timer >= interval:
		_gravity_timer -= interval
		var falling: Array = players.filter(
			func(p: Player) -> bool: return p.current != null and not p.is_soft_dropping())
		falling.sort_custom(func(a: Player, b: Player) -> bool: return _lowest_row(a) > _lowest_row(b))
		var anyone_moved := false
		for p in falling:
			if p.try_move(Vector2i.DOWN, false):
				anyone_moved = true
		if not anyone_moved:
			_gravity_timer = minf(_gravity_timer, interval)
			break


func _lowest_row(p: Player) -> int:
	var lowest := -999
	for c in p.current.get_cells():
		lowest = maxi(lowest, c.y)
	return lowest


func _render() -> void:
	var pieces: Array = []
	for p in players:
		if p.current != null:
			pieces.append({"cells": p.current.get_cells(), "ghost": get_ghost_cells(p), "type": p.current.type})
	board.render_active(pieces)
