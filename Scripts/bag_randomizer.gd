class_name BagRandomizer
extends RefCounted
## Randomizer 7-bag: cada "saco" contém as 7 peças baralhadas.

var _queue: Array[int] = []
var _rng := RandomNumberGenerator.new()


func reset(seed_value: int = -1) -> void:
	_queue.clear()
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


## Devolve a próxima peça e remove-a da fila.
func next() -> int:
	_ensure(PieceData.COUNT + 1)
	return _queue.pop_front()


## Devolve as `n` peças seguintes sem as remover.
func peek(n: int) -> Array[int]:
	_ensure(n)
	return _queue.slice(0, n)


func _ensure(n: int) -> void:
	while _queue.size() < n:
		_refill()


func _refill() -> void:
	var bag: Array[int] = [0, 1, 2, 3, 4, 5, 6]
	# Fisher-Yates com o nosso RNG (permite seeds reprodutíveis).
	for i in range(bag.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := bag[i]
		bag[i] = bag[j]
		bag[j] = tmp
	_queue.append_array(bag)
