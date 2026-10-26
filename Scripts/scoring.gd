class_name Scoring
extends RefCounted
# Score, level and lines. All the point values live here so game.gd doesn't
# have to care about them.

enum Spin { NONE, MINI, FULL }

const LINES_PER_LEVEL := 10

# Base points per clear, multiplied by the current level.
const LINE_POINTS: Array[int] = [0, 100, 300, 500, 800]
const TSPIN_POINTS: Array[int] = [400, 800, 1200, 1600]
const TSPIN_MINI_POINTS: Array[int] = [100, 200, 400]
# Two pieces locking at once can clear more than 4 rows (our co-op addition).
const EXTRA_ROW_POINTS := 400

var score := 0
var level := 1
var lines := 0
var combo := -1
var back_to_back := false
var _start_level := 1


func reset(start_level: int) -> void:
	_start_level = start_level
	score = 0
	level = start_level
	lines = 0
	combo = -1
	back_to_back = false


# Called after every lock, even when nothing was cleared (that's what breaks a combo).
# Returns the text to flash on screen, or "" if there's nothing to show.
func add_clear(cleared: int, spin: Spin) -> String:
	var points := 0
	var text := ""
	match spin:
		Spin.FULL:
			points = TSPIN_POINTS[mini(cleared, 3)]
			text = "T-SPIN " + ["", "SINGLE", "DOUBLE", "TRIPLE"][mini(cleared, 3)]
		Spin.MINI:
			points = TSPIN_MINI_POINTS[mini(cleared, 2)]
			text = "T-SPIN MINI " + ["", "SINGLE", "DOUBLE"][mini(cleared, 2)]
		_:
			if cleared > 4:
				points = LINE_POINTS[4] + (cleared - 4) * EXTRA_ROW_POINTS
				text = "%d LINES!" % cleared
			else:
				points = LINE_POINTS[cleared]
				text = ["", "SINGLE", "DOUBLE", "TRIPLE", "TETRIS"][cleared]

	var combo_bonus := 0
	if cleared == 0:
		combo = -1
	else:
		# Tetrises and T-spins in a row get the back-to-back bonus.
		var difficult := cleared >= 4 or spin != Spin.NONE
		if difficult and back_to_back:
			points = int(points * 1.5)
			text = "B2B " + text
		back_to_back = difficult
		combo += 1
		if combo > 0:
			combo_bonus = 50 * combo * level
			text += "\nCOMBO x%d" % combo

	score += points * level + combo_bonus
	lines += cleared
	level = _start_level + lines / LINES_PER_LEVEL
	return text.strip_edges()
