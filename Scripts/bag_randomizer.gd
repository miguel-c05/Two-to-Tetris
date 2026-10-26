class_name BagRandomizer
extends RefCounted
# 7-bag randomizer: pieces come out in shuffled bags that contain each shape once,
# so you never wait more than 12 pieces for an I.

var _queue: Array[int] = []
var _rng := RandomNumberGenerator.new()


# Pass a seed to get the same sequence every time (handy for testing/recording).
func reset(seed_value: int = -1) -> void:
	_queue.clear()
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


func next() -> int:
	_fill_to(PieceData.COUNT + 1)
	return _queue.pop_front()


func peek(n: int) -> Array[int]:
	_fill_to(n)
	return _queue.slice(0, n)


func _fill_to(n: int) -> void:
	while _queue.size() < n:
		_add_bag()


func _add_bag() -> void:
	var bag: Array[int] = [0, 1, 2, 3, 4, 5, 6]
	# Fisher-Yates with our own RNG instead of shuffle(), so seeds work.
	for i in range(bag.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := bag[i]
		bag[i] = bag[j]
		bag[j] = tmp
	_queue.append_array(bag)
