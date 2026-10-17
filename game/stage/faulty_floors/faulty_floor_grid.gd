class_name FaultyFloorGrid
extends RefCounted
## Authoritative panel states in stage-local pixels. Warnings still support bodies.

enum State { SOLID, WARNING, GONE }

var columns := 12
var rows := 12
var bounds := Rect2()
var cell_size := Vector2.ZERO
var states := PackedByteArray()
var armed_at := PackedFloat64Array()
var pending: Array[int] = []
var revision := 0


func configure(area: Rect2) -> void:
	bounds = area
	cell_size = bounds.size / Vector2(columns, rows)
	states.resize(columns * rows)
	states.fill(State.SOLID)
	armed_at.resize(states.size())
	armed_at.fill(-1)
	pending.clear()
	revision = 0


func index_at(point: Vector2) -> int:
	if not bounds.has_point(point):
		return -1
	var cell := Vector2i((point - bounds.position) / cell_size)
	return cell.y * columns + cell.x


func cell_rect(index: int) -> Rect2:
	return Rect2(bounds.position + Vector2(index % columns, index / columns) * cell_size, cell_size)


func supported(point: Vector2) -> bool:
	var index := index_at(point)
	return index >= 0 and states[index] != State.GONE


func clear_at(point: Vector2, clearance: float, ignored_warning: int = -1) -> bool:
	if not bounds.grow(-clearance).has_point(point):
		return false
	for index in _touching(point, clearance):
		if states[index] != State.SOLID:
			if index != ignored_warning or states[index] == State.GONE:
				return false
	return true


func arm(point: Vector2, radius: float, clock: float) -> Array[int]:
	var changed: Array[int] = []
	for index in _touching(point, radius):
		if states[index] == State.SOLID:
			states[index] = State.WARNING
			armed_at[index] = clock
			pending.append(index)
			changed.append(index)
	if not changed.is_empty():
		revision += 1
	return changed


func advance(clock: float, warning_duration: float) -> Array[int]:
	var fallen: Array[int] = []
	for slot in range(pending.size() - 1, -1, -1):
		var index := pending[slot]
		if clock - armed_at[index] >= warning_duration:
			states[index] = State.GONE
			pending.remove_at(slot)
			fallen.append(index)
	if not fallen.is_empty():
		revision += 1
	return fallen


## Four-connected routes cannot cut diagonally across unsupported corners.
## If the requested island is unreachable, return the nearest reachable panel.
func route(start: int, destination: int) -> PackedInt32Array:
	if start < 0 or destination < 0:
		return PackedInt32Array()
	var parents := PackedInt32Array()
	parents.resize(states.size())
	parents.fill(-2)
	parents[start] = -1
	var queue := PackedInt32Array([start])
	var head := 0
	var nearest := start
	var target := cell_rect(destination).get_center()
	var best := cell_rect(start).get_center().distance_squared_to(target)
	while head < queue.size():
		var current := queue[head]
		head += 1
		var distance := cell_rect(current).get_center().distance_squared_to(target)
		if distance < best:
			best = distance
			nearest = current
		if current == destination:
			break
		for offset in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var cell: Vector2i = Vector2i(current % columns, current / columns) + offset
			if cell.x < 0 or cell.x >= columns or cell.y < 0 or cell.y >= rows:
				continue
			var next: int = cell.y * columns + cell.x
			if parents[next] != -2 or states[next] != State.SOLID:
				continue
			parents[next] = current
			queue.append(next)
	var path := PackedInt32Array()
	while nearest != -1:
		path.append(nearest)
		nearest = parents[nearest]
	path.reverse()
	return path


func _touching(point: Vector2, radius: float) -> Array[int]:
	var result: Array[int] = []
	var low := Vector2i(((point - Vector2.ONE * radius - bounds.position) / cell_size).floor())
	var high := Vector2i(((point + Vector2.ONE * radius - bounds.position) / cell_size).floor())
	for y in range(maxi(0, low.y), mini(rows - 1, high.y) + 1):
		for x in range(maxi(0, low.x), mini(columns - 1, high.x) + 1):
			var index := y * columns + x
			var area := cell_rect(index)
			var closest := point.clamp(area.position, area.end)
			if closest.distance_squared_to(point) <= radius * radius:
				result.append(index)
	return result
