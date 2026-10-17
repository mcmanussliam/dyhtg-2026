class_name PilotUnstuck
extends RefCounted
## Watches actual positional progress, including oscillation and spinning in place.
## Escape goals change steering only; native torque, thrust and collisions still move the chair.

var started := false
var _anchor := Vector2.INF
var _stalled := 0.0
var _goal := Vector2.INF
var _remaining := 0.0
var _attempt := 0
var _retry_left := 0.0


func update(chair: Chair, chairs: Array[Chair], stage: ArenaStage, delta: float) -> Vector2:
	started = false
	var elapsed := maxf(delta, 0)
	if _anchor == Vector2.INF:
		_anchor = chair.global_position
	if chair.global_position.distance_to(_anchor) > 60 * chair.size_scale:
		_anchor = chair.global_position
		_stalled = 0.0
		if _goal == Vector2.INF:
			_attempt = 0
	else:
		_stalled += elapsed
	_retry_left -= elapsed
	if _goal != Vector2.INF:
		_remaining -= elapsed
		if (
			chair.global_position.distance_to(_goal) < 45 * chair.size_scale
			or _remaining <= 0
			or not stage.is_path_safe(chair.global_position, _goal, 10)
		):
			_goal = Vector2.INF
		else:
			return _goal
	# Give real pushing contests time to resolve. Seat offsets prevent synchronized retries.
	if _stalled < 3.0 + (chair.seat % 4) * 0.17 or _retry_left > 0:
		return Vector2.INF
	_attempt += 1
	_goal = _choose_goal(chair, chairs, stage)
	_retry_left = 0.45
	if _goal != Vector2.INF:
		_remaining = minf(2.2 + (chair.seat % 3) * 0.23 + _attempt * 0.25, 3.8)
		_stalled = 0
		_anchor = chair.global_position
		started = true
	return _goal


func _choose_goal(chair: Chair, chairs: Array[Chair], stage: ArenaStage) -> Vector2:
	var origin := chair.global_position
	var clearance := 30 * chair.size_scale
	var space := chair.get_world_2d().direct_space_state
	var best := Vector2.INF
	var best_score := -INF
	# Retry from a different angle and with more room, rather than repeating one turn.
	var offset := chair.aim_angle + chair.seat * 2.399963 + _attempt * 1.618
	for index in 12:
		var direction := Vector2.from_angle(offset + index * TAU / 12)
		var goal := stage.navigation_target(
			origin, origin + direction * minf(240 + _attempt * 40, 380), clearance + 20
		)
		var route := goal - origin
		var distance := route.length()
		if distance < 100 or not stage.is_path_safe(origin, goal, 10):
			continue
		direction = route / distance
		var available := distance
		for lateral in [-clearance, 0.0, clearance]:
			var start: Vector2 = origin + direction.orthogonal() * lateral
			var hit := space.intersect_ray(
				PhysicsRayQueryParameters2D.create(start, start + route, 1)
			)
			if (
				not hit.is_empty()
				and not (hit.collider is OfficeProp and hit.collider.is_movable())
			):
				available = minf(available, start.distance_to(hit.position) - clearance)
		if available < 100:
			continue
		goal = origin + direction * available
		if not stage.is_path_safe(origin, goal, 10):
			continue
		var score := available
		for other in chairs:
			if other != chair and other.active and not other.falling:
				score -= maxf(0, 190 - goal.distance_to(other.global_position)) * 2
		# A small asymmetric preference breaks mirrored two-player responses.
		score += cos(index * 1.7 + chair.seat) * 35
		if score > best_score:
			best_score = score
			best = goal
	return best
