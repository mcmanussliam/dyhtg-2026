class_name PracticePilot
extends RefCounted
## Uses the same left/right steering as humans; no aiming or movement shortcuts.


func sample(chair: Chair, chairs: Array[Chair], bounds: Rect2) -> ChairCommand:
	var command := ChairCommand.new()
	var target: Chair
	var closest: float = INF
	for candidate in chairs:
		if candidate == chair or not candidate.active:
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
