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
var _crowded := 0.0
var _arrival_distance := 45.0
var _escape_origin := Vector2.ZERO
var _failed_direction := Vector2.ZERO


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
			_failed_direction = Vector2.ZERO
	else:
		_stalled += elapsed
	var neighbours := 0
	for other in chairs:
		if other != chair and other.active and not other.falling:
			if (
				(
					chair.global_position.distance_squared_to(other.global_position)
					< pow(125 * chair.size_scale, 2)
				)
				and (chair.linear_velocity - other.linear_velocity).length_squared() < 140 * 140
				and chair.linear_velocity.length_squared() < 180 * 180
			):
				neighbours += 1
	_crowded = _crowded + elapsed if neighbours > 0 else maxf(0, _crowded - elapsed * 2)
	_retry_left -= elapsed
	if _goal != Vector2.INF:
		_remaining -= elapsed
		if (
			chair.global_position.distance_to(_goal) < _arrival_distance
			or _remaining <= 0
			or not stage.is_path_safe(chair.global_position, _goal, 10)
		):
			if (
				_remaining <= 0
				and chair.global_position.distance_to(_escape_origin) < 50 * chair.size_scale
			):
				_failed_direction = (_goal - _escape_origin).normalized()
			_goal = Vector2.INF
		else:
			return _goal
	# Give real pushing contests time to resolve. Seat offsets prevent synchronized retries.
	if (
		(_stalled < 3.0 + (chair.seat % 4) * 0.17 and _crowded < 2.2 + (chair.seat % 4) * 0.2)
		or _retry_left > 0
	):
		return Vector2.INF
	_attempt += 1
	_goal = _choose_goal(chair, chairs, stage)
	_retry_left = 0.45
	if _goal != Vector2.INF:
		_escape_origin = chair.global_position
		_arrival_distance = minf(
			45 * chair.size_scale, chair.global_position.distance_to(_goal) * 0.3
		)
		_remaining = minf(2.2 + (chair.seat % 3) * 0.23 + _attempt * 0.25, 3.8)
		_stalled = 0
		_crowded = 0
		_anchor = chair.global_position
		started = true
	return _goal


func _choose_goal(chair: Chair, chairs: Array[Chair], stage: ArenaStage) -> Vector2:
	var origin := chair.global_position
	# If a full corridor is unavailable, take a shorter step around the obstruction
	# with clearance approaching the real 23-pixel body radius, never inside it.
	var clearance := lerpf(30, 24, clampf((_attempt - 2) / 4.0, 0, 1)) * chair.size_scale
	var minimum_step := maxf(35, 100 - _attempt * 12)
	if not _failed_direction.is_zero_approx():
		clearance = 24 * chair.size_scale
		minimum_step = 35
	var space := chair.get_world_2d().direct_space_state
	var best := Vector2.INF
	var best_score := -INF
	# Retry from a different angle and with more room, rather than repeating one turn.
	var offset := chair.aim_angle + chair.seat * 2.399963 + _attempt * 1.618
	for index in 36:
		var direction := Vector2.from_angle(offset + floorf(index / 3.0) * TAU / 12)
		var reach: float = [70.0, 160.0, minf(240 + _attempt * 40, 380)][index % 3]
		var goal := origin + direction * reach
		# Include nearby raw waypoints. A distant navigation projection may lie behind
		# the same desk that trapped us, even when a short sideways step is clear.
		if not stage.is_path_safe(origin, goal, 10):
			goal = stage.navigation_target(origin, goal, clearance + 20)
		var route := goal - origin
		var distance := route.length()
		if distance < minimum_step or not stage.is_path_safe(origin, goal, 10):
			continue
		direction = route / distance
		if direction.dot(_failed_direction) > 0.6:
			continue
		var available := distance
		for lateral in [-clearance, 0.0, clearance]:
			var start: Vector2 = origin + direction.orthogonal() * lateral
			var hit := space.intersect_ray(
				PhysicsRayQueryParameters2D.create(start, start + route, 1)
			)
			if (
				not hit.is_empty()
				and not (
					(hit.collider is OfficeProp or hit.collider is PropCollisionBridge)
					and hit.collider.is_movable()
				)
			):
				available = minf(available, start.distance_to(hit.position) - clearance)
		if available < minimum_step:
			continue
		goal = origin + direction * available
		if not stage.is_path_safe(origin, goal, 10):
			continue
		# Remember a corridor that looked clear but made no physical progress. A short
		# sideways manoeuvre can clear a desk corner before another long escape.
		var score := available - maxf(0, direction.dot(_failed_direction)) * available * 1.8
		for other in chairs:
			if other != chair and other.active and not other.falling:
				score -= maxf(0, 220 - goal.distance_to(other.global_position)) * 2.5
				var closest := Geometry2D.get_closest_point_to_segment(
					other.global_position, origin, goal
				)
				score -= maxf(
					0, 100 * chair.size_scale - closest.distance_to(other.global_position)
				)
		# A small asymmetric preference breaks mirrored two-player responses.
		score += cos(index * 1.7 + chair.seat) * 35
		if score > best_score:
			best_score = score
			best = goal
	return best
