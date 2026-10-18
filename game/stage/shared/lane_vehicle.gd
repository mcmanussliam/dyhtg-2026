class_name LaneVehicle
extends RefCounted
## A scripted vehicle crossing one straight lane between two wall openings.
## Sweeps relative chair motion to prevent tunnelling; subclasses own their phase
## timing and presentation, and request eliminations through the shared contract.

const LAUNCH_SPEED := 2450.0  # Planar pixels per second.

var width := 0.0
var length := 0.0
var chairs: Array[Chair] = []
var lane := -1
var position := Vector2.ZERO
var direction := Vector2.RIGHT
var _stage: OfficeStage
var _elimination_reason := &""
var _start := Vector2.ZERO
var _finish := Vector2.ZERO
var _hit_seats: Dictionary = {}
var _hit_props: Dictionary = {}
var _units := 1.0 / RenderStyle.PIXELS_PER_UNIT


## Line up behind the entrance of `next_lane`, ready to drive towards its exit.
func _aim(next_lane: int, ends: PackedVector2Array, forward: bool) -> void:
	lane = next_lane
	_start = ends[0 if forward else 1]
	_finish = ends[1 if forward else 0]
	direction = (_finish - _start).normalized()
	position = _start - direction * (length * 0.5 + 20)
	_hit_seats.clear()
	_hit_props.clear()


## Drive forward, striking chairs and furniture; true once wholly past the exit.
func _advance(delta: float, speed: float) -> bool:
	var previous := position
	position += direction * speed * delta
	_sweep_chairs(previous, delta)
	_sweep_props(previous)
	return (position - _finish).dot(direction) > length * 0.5 + 20


func _in_lane(point: Vector2, margin: float) -> bool:
	return absf((point - _start).cross(direction)) < width * 0.5 + 24 + margin * 0.35


## Once the tail has passed, the cleared lane is usable immediately.
func _ahead_of_tail(point: Vector2) -> bool:
	return (point - position).dot(direction) > -length * 0.5 - 50


func avoidance_target(point: Vector2, margin: float, reverse: bool = false) -> Vector2:
	var across := direction.orthogonal()
	var offset := (point - _start).dot(across)
	var side := 1.0 if offset >= 0 else -1.0
	if reverse:
		side = -side
	return point + across * (side * (width * 0.5 + 60 + margin * 0.35) - offset)


func _launch_velocity() -> Vector3:
	var planar := direction * LAUNCH_SPEED / RenderStyle.PIXELS_PER_UNIT
	return Vector3(planar.x, 16, planar.y)


func _launch_spin() -> Vector3:
	return Vector3(direction.y, 0.4, -direction.x) * 10


func _sweep_chairs(previous: Vector2, delta: float) -> void:
	for chair in chairs:
		if not is_instance_valid(chair) or not chair.is_in_play() or _hit_seats.has(chair.seat):
			continue
		var radius := 25 * chair.size_scale
		# Relative travel catches a moving chair even if both endpoints miss the vehicle.
		var from := chair.global_position - chair.linear_velocity * delta - previous
		var to := chair.global_position - position
		if not _intersects(from, to, radius):
			continue
		_hit_seats[chair.seat] = true
		chair.set_knockout_launch(_launch_velocity(), _launch_spin())
		_stage.elimination_requested.emit(chair.seat, _elimination_reason)


func _sweep_props(previous: Vector2) -> void:
	for prop in _stage.get_node("Furniture").get_children():
		if (
			not prop is OfficeProp
			or not _can_strike(prop)
			or prop.collision_layer == 0
			or _hit_props.has(prop.get_instance_id())
		):
			continue
		if _intersects(prop.global_position - previous, prop.global_position - position, 35):
			_hit_props[prop.get_instance_id()] = true
			_strike(prop)


## Furniture this vehicle can hit at all; every prop by default.
func _can_strike(_prop: OfficeProp) -> bool:
	return true


func _strike(_prop: OfficeProp) -> void:
	pass


## Does the relative segment from..to touch the vehicle's oriented rectangle?
func _intersects(from: Vector2, to: Vector2, radius: float) -> bool:
	var across := direction.orthogonal()
	var a := Vector2(from.dot(direction), from.dot(across))
	var b := Vector2(to.dot(direction), to.dot(across))
	var extent := Vector2(length * 0.5, width * 0.5) + Vector2.ONE * radius
	if Rect2(-extent, extent * 2).has_point(a) or Rect2(-extent, extent * 2).has_point(b):
		return true
	var low := 0.0
	var high := 1.0
	var travel := b - a
	for axis in 2:
		if absf(travel[axis]) < 0.0001:
			if absf(a[axis]) > extent[axis]:
				return false
			continue
		var entry := (-extent[axis] - a[axis]) / travel[axis]
		var exit := (extent[axis] - a[axis]) / travel[axis]
		low = maxf(low, minf(entry, exit))
		high = minf(high, maxf(entry, exit))
		if low > high:
			return false
	return true
