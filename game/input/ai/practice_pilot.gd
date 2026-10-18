class_name PracticePilot
extends RefCounted
## Commits to an opponent, approaches, then turns its real jet onto them.
## Outputs steering only: real chair torque, thrust and inertia provide all movement.

enum Intent { PURSUE, FLANK, BLAST }

var target_seat: int:
	get:
		return _target.seat if is_instance_valid(_target) else -1

var _random := RandomNumberGenerator.new()
var _target: Chair
var _target_left: float = 0.0
var _blast_left: float = 0.0
var _intent: Intent = Intent.PURSUE
var _side: float = 1.0
var _offset: float = 100.0
var _recovering: bool = false
var _last_heading: float = 0.0
var _heading_ready: bool = false
var _turn_arc: float = 0.0
var _escape_left: float = 0.0
var _escape_jet := Vector2.RIGHT
var _uncontested_time: float = 0.0
var _round_age: float = 0.0
var _alive_count: int = 0
var _stall_time: float = 0.0
var _ignored: Dictionary = {}
var _risk_margin: float = 95.0
var _pit_escape_goal := Vector2.INF
var _unstuck := PilotUnstuck.new()


func _init(random_seed: int = -1) -> void:
	if random_seed < 0:
		_random.randomize()
	else:
		_random.seed = random_seed
	_risk_margin = _random.randf_range(90.0, 115.0)


func sample(chair: Chair, chairs: Array[Chair], bounds: Rect2) -> ChairCommand:
	var command := ChairCommand.new()
	var target: Chair
	var closest: float = INF
	for candidate in chairs:
		if candidate == chair or not candidate.is_in_play():
			continue
		var distance := chair.position.distance_to(candidate.position)
		if distance < closest:
			target = candidate
			closest = distance
	var desired_motion := bounds.get_center() - chair.position
	var refuge := bounds.grow(-90.0)
	var predicted_position := chair.position + chair.linear_velocity * 0.55
	if refuge.has_point(predicted_position) and target != null:
		desired_motion = target.position + target.linear_velocity * 0.20 - chair.position
		if closest < chair.tuning.spray_range * 0.75:
			desired_motion = -desired_motion
	if desired_motion.length_squared() < 1.0:
		desired_motion = Vector2.from_angle(chair.aim_angle + 1.0)
	var desired_jet := -desired_motion.normalized()
	var error := wrapf(desired_jet.angle() - chair.aim_angle, -PI, PI)
	command.turn = clampf(error * 1.25 - chair.angular_velocity * 0.22, -1.0, 1.0)
	return command


func sample_on_stage(
	chair: Chair, chairs: Array[Chair], stage: ArenaStage, delta: float = 1.0 / 60.0
) -> ChairCommand:
	var command := ChairCommand.new()
	if not chair.is_in_play():
		return command
	_update_engagement(chair, chairs, delta)
	_target_left -= maxf(delta, 0.0)
	_blast_left -= maxf(delta, 0.0)
	if _target_left <= 0.0 or not is_instance_valid(_target) or not _target.active:
		_choose_target(chair, chairs)
	# Eliminations ease immediate pressure, but never reset the round's urgency.
	var pressure := 0.0
	if _alive_count > 1:
		pressure = clampf(
			maxf((_uncontested_time - 2.0) / 16.0, (_round_age - 10.0) / 20.0), 0.0, 1.0
		)
	var safety_margin := stage.ai_edge_margin * lerpf(1.0, 0.35, pressure)
	var horizon := lerpf(1.0, 0.40, pressure)
	if stage.ai_edge_margin > 0:
		# Hole avoidance keeps time to turn and shed inward momentum even late in a fight.
		horizon = maxf(horizon, lerpf(0.85, 0.55, pressure))
		# Long fights trade reaction time for committed, riskier attacks.
		horizon *= lerpf(1.0, 0.45, clampf((_round_age - 30.0) / 30.0, 0, 1))
	var predicted := chair.global_position + chair.linear_velocity * horizon
	if (
		not _recovering
		and not stage.is_path_safe(
			chair.global_position,
			predicted,
			maxf(safety_margin, lerpf(_risk_margin, 10.0, pressure))
		)
	):
		_recovering = true
	elif (
		_recovering
		and stage.is_path_safe(
			chair.global_position,
			predicted,
			maxf(stage.ai_edge_margin + 20, lerpf(145.0, 65.0, pressure))
		)
		and stage.is_safe(chair.global_position, lerpf(140.0, 60.0, pressure))
	):
		_recovering = false
	if absf(_turn_arc) > PI * 1.65 and _escape_left <= 0.0:
		_escape_left = _random.randf_range(0.6, 0.85)
		_escape_jet = Vector2.from_angle(chair.aim_angle)
		_turn_arc = 0.0
		_choose_target(chair, chairs)
	if stage is PitOfficeStage:
		if _escape_left <= 0:
			_pit_escape_goal = Vector2.INF
		elif _pit_escape_goal == Vector2.INF:
			_pit_escape_goal = stage.open_floor_target(chair.global_position)
			_escape_left = 1.7
	var unstuck_goal := _unstuck.update(chair, chairs, stage, delta)
	if _unstuck.started:
		_blast_left = 0
		_escape_left = 0
		_turn_arc = 0
		_choose_target(chair, chairs)
	var desired_jet: Vector2
	if unstuck_goal != Vector2.INF:
		desired_jet = -_approach_acceleration(chair, unstuck_goal, 340)
	elif (
		_escape_left > 0.0
		and not _recovering
		and stage.is_path_safe(
			chair.global_position, chair.global_position + chair.linear_velocity * 0.5, 100.0
		)
	):
		if stage is PitOfficeStage:
			desired_jet = -_approach_acceleration(chair, _pit_escape_goal, 320)
		else:
			desired_jet = _escape_jet
	elif _recovering:
		# Cancel both outward drift and the sideways velocity created while turning.
		var refuge := stage.recovery_target(chair.global_position, predicted, 300.0)
		desired_jet = -_approach_acceleration(chair, refuge, 250.0)
	elif not is_instance_valid(_target):
		desired_jet = Vector2.from_angle(chair.aim_angle)
	else:
		var separation := _target.global_position - chair.global_position
		var retreat := (
			chair.global_position - separation.normalized() * lerpf(230.0, 90.0, pressure)
		)
		var can_attack := (
			stage.is_path_safe(
				chair.global_position, retreat, maxf(safety_margin, lerpf(70.0, 0.0, pressure))
			)
			and stage.is_path_safe(
				chair.global_position, predicted, maxf(safety_margin, lerpf(135.0, 15.0, pressure))
			)
		)
		if stage is PitOfficeStage:
			can_attack = (
				can_attack and stage.has_push_angle(chair.global_position, _target.global_position)
			)
		if (
			separation.length() < chair.tuning.spray_range * 0.90
			and _blast_left <= 0.0
			and can_attack
		):
			_blast_left = _random.randf_range(1.2, 1.9)
			_intent = Intent.BLAST
		if _intent == Intent.BLAST and _blast_left > 0.0 and can_attack:
			# Hold the attack long enough to actually turn and deliver a sustained shove.
			desired_jet = separation + _target.linear_velocity * 0.12
		else:
			if _intent == Intent.BLAST:
				_intent = Intent.PURSUE
			var goal := _target.global_position + _target.linear_velocity * 0.28
			if _intent == Intent.FLANK:
				goal += separation.normalized().orthogonal() * _side * _offset
				if separation.length() < 210.0:
					_intent = Intent.PURSUE
			if separation.length() < 350:
				var flank := (
					separation.normalized().orthogonal() * _side * (50 + chair.seat % 3 * 25)
				)
				var crowded := chairs.any(
					func(rival: Chair):
						return (
							rival != chair
							and rival != _target
							and rival.active
							and rival.global_position.distance_squared_to(goal) < 150 * 150
						)
				)
				if crowded:
					goal += flank
			if stage is PitOfficeStage:
				goal = stage.attack_position(goal)
			goal = stage.navigation_target(
				chair.global_position, goal, maxf(safety_margin, lerpf(155.0, 30.0, pressure))
			)
			desired_jet = -(goal - chair.global_position - chair.linear_velocity * 0.25)
	var before_obstacle := desired_jet
	# The watchdog already checked the escape corridor. Re-running reactive detours
	# here can steer a pinned chair straight back into the obstruction.
	if unstuck_goal == Vector2.INF:
		desired_jet = _avoid_obstacles(chair, stage, desired_jet)
	if (
		stage.ai_edge_margin > 0
		and not stage.is_path_safe(
			chair.global_position,
			chair.global_position - desired_jet.normalized() * 140,
			stage.ai_edge_margin
		)
	):
		# A desk detour must not replace a safe route with a shortcut into the pit.
		desired_jet = before_obstacle
	if desired_jet.length_squared() < 1.0:
		desired_jet = Vector2.from_angle(chair.aim_angle)
	var error := wrapf(desired_jet.angle() - chair.aim_angle, -PI, PI)
	# Track a bounded angular rate, brake before alignment, then hold the heading.
	# Random decisions never inject spin; they choose a destination or opponent.
	var turn_limit := 6.0 if _recovering else 4.5
	var desired_spin := clampf(error * 5.0, -turn_limit, turn_limit)
	command.turn = clampf(
		(desired_spin - chair.angular_velocity) * 0.40 + desired_spin * 0.10, -1.0, 1.0
	)
	if unstuck_goal == Vector2.INF and _escape_left > 0.0 and absf(chair.angular_velocity) > 1.5:
		command.turn = -signf(chair.angular_velocity)
	if stage is PitOfficeStage:
		command.turn = PitSteeringGuard.filter(
			chair,
			stage,
			command.turn,
			desired_jet,
			turn_limit,
			pressure + clampf((_round_age - 30.0) / 30.0, 0, 1),
			unstuck_goal
		)
	return command


func _approach_acceleration(chair: Chair, goal: Vector2, speed: float) -> Vector2:
	var desired_velocity := ((goal - chair.global_position) * 2.2).limit_length(speed)
	return desired_velocity - chair.linear_velocity


func _choose_target(chair: Chair, chairs: Array[Chair]) -> void:
	_target_left = _random.randf_range(3.0, 5.5)
	_blast_left = 0.0
	_intent = Intent.FLANK if _random.randf() < 0.30 else Intent.PURSUE
	_side = -1.0 if _random.randf() < 0.5 else 1.0
	_offset = _random.randf_range(80.0, 140.0)
	var candidates: Array[Chair] = []
	var weights := PackedFloat32Array()
	var total := 0.0
	for candidate in chairs:
		if candidate == chair or not candidate.is_in_play():
			continue
		# All opponents are eligible, including other AIs. Distance is only a mild
		# preference, so the nearest seat or human does not monopolise every bot.
		var weight := 1.0 / (250.0 + chair.global_position.distance_to(candidate.global_position))
		weight *= 1.0 + minf(float(_ignored.get(candidate.seat, 0.0)) / 3.0, 4.0)
		if candidate == _target:
			weight *= 0.45
		var crowd := 0
		for rival in chairs:
			if rival != chair and rival != candidate and rival.is_in_play():
				if rival.global_position.distance_squared_to(candidate.global_position) < 180 * 180:
					crowd += 1
		weight /= 1.0 + crowd * 0.7
		candidates.append(candidate)
		weights.append(weight)
		total += weight
	_target = null
	var roll := _random.randf() * total
	for index in candidates.size():
		roll -= weights[index]
		if roll <= 0.0:
			_target = candidates[index]
			return
	if not candidates.is_empty():
		_target = candidates.back()


func _update_engagement(chair: Chair, chairs: Array[Chair], delta: float) -> void:
	_round_age += maxf(delta, 0.0)
	var alive := 0
	for other in chairs:
		if not other.active:
			continue
		alive += 1
		if other != chair:
			_ignored[other.seat] = float(_ignored.get(other.seat, 0.0)) + delta
	if is_instance_valid(_target):
		_ignored[_target.seat] = 0.0
	if alive != _alive_count:
		_uncontested_time = 0.0
		_alive_count = alive
	else:
		_uncontested_time += delta
	_escape_left -= delta
	if (
		is_instance_valid(_target)
		and chair.linear_velocity.length() < 70.0
		and chair.global_position.distance_to(_target.global_position) < 180.0
	):
		_stall_time += delta
	else:
		_stall_time = 0.0
	if _stall_time > 1.2 + (_risk_margin - 90.0) / 25.0:
		# Break a stationary pushing contest, even when only two rivals remain.
		_escape_left = 0.85
		_escape_jet = Vector2.from_angle(chair.aim_angle + _side * PI / 2.0)
		_target_left = 0.0
		_stall_time = 0.0
	if _heading_ready:
		var turn := wrapf(chair.aim_angle - _last_heading, -PI, PI)
		if turn * _turn_arc < 0.0 or absf(chair.angular_velocity) < 0.45:
			_turn_arc = 0.0
		_turn_arc += turn
	_last_heading = chair.aim_angle
	_heading_ready = true


func _avoid_obstacles(chair: Chair, stage: ArenaStage, desired_jet: Vector2) -> Vector2:
	var motion := -desired_jet.normalized()
	if chair.linear_velocity.length() > 80.0:
		motion = chair.linear_velocity.normalized()
	var reach := clampf(chair.linear_velocity.length() * 0.45 + 65.0, 85.0, 220.0)
	var closest := INF
	var normal := Vector2.ZERO
	for offset in [-22.0, 0.0, 22.0]:
		var origin: Vector2 = chair.global_position + motion.orthogonal() * offset
		var query := PhysicsRayQueryParameters2D.create(origin, origin + motion * reach, 1)
		var hit := chair.get_world_2d().direct_space_state.intersect_ray(query)
		if (
			not hit.is_empty()
			and (hit.collider is OfficeProp or hit.collider is PropCollisionBridge)
			and hit.collider.is_movable()
		):
			continue
		if not hit.is_empty() and origin.distance_to(hit.position) < closest:
			closest = origin.distance_to(hit.position)
			normal = hit.normal
	if normal.is_zero_approx():
		return desired_jet
	var tangent := normal.orthogonal()
	var preference := tangent.dot(-desired_jet.normalized())
	if preference < -0.05 or (absf(preference) <= 0.05 and _side < 0.0):
		tangent = -tangent
	if not stage.is_path_safe(chair.global_position, chair.global_position + tangent * 110.0, 70.0):
		tangent = -tangent
	var desired_velocity := (tangent + normal * 0.65).normalized() * 280.0
	return -(desired_velocity - chair.linear_velocity)
