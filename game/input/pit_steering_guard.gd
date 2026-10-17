class_name PitSteeringGuard
extends RefCounted
## Short torque/thrust rollouts protect the pit approach without changing body physics.

const STEP := 0.04
const STEPS := 25


static func filter(
	chair: Chair,
	stage: PitOfficeStage,
	requested: float,
	desired_jet: Vector2,
	turn_limit: float,
	commitment: float,
	navigation_goal: Vector2 = Vector2.INF
) -> float:
	var state := PhysicsServer2D.body_get_direct_state(chair.get_rid())
	if state == null:
		return requested
	var center := stage.to_global(stage.center)
	var radius := stage.hole_radius
	# Commitment rises from cautious opening play (0) to late-round risks (2).
	var margin := lerpf(35.0 + chair.size_scale * 10, 8.0, minf(commitment, 1.0))
	var wanted := desired_jet.angle()
	var original := _clearance(
		chair,
		center,
		radius,
		requested,
		wanted,
		turn_limit,
		state.inverse_mass,
		state.inverse_inertia,
		commitment,
		navigation_goal
	)
	if original >= margin:
		return requested
	var best := requested
	var best_score := original
	for turn in [-1.0, -0.5, 0.0, 0.5, 1.0]:
		var clearance := _clearance(
			chair,
			center,
			radius,
			turn,
			wanted,
			turn_limit,
			state.inverse_mass,
			state.inverse_inertia,
			commitment,
			navigation_goal
		)
		var score := clearance - absf(turn - requested) * 2.0
		if score > best_score:
			best_score = score
			best = turn
	return best


static func _clearance(
	chair: Chair,
	center: Vector2,
	radius: float,
	initial_turn: float,
	wanted: float,
	turn_limit: float,
	inverse_mass: float,
	inverse_inertia: float,
	commitment: float,
	navigation_goal: Vector2
) -> float:
	var point := chair.global_position
	var velocity := chair.linear_velocity
	var heading := chair.aim_angle
	var spin := chair.angular_velocity
	var nearest := point.distance_to(center) - radius
	for index in int(lerpf(STEPS, 7, commitment / 2.0)):
		var turn := initial_turn
		if index >= 5:
			if navigation_goal != Vector2.INF:
				# A committed escape brakes on approach; do not predict infinite travel
				# through its destination and veto the very turn that frees the chair.
				var desired_velocity := ((navigation_goal - point) * 2.2).limit_length(340)
				wanted = (velocity - desired_velocity).angle()
			var desired_spin := clampf(
				wrapf(wanted - heading, -PI, PI) * 5, -turn_limit, turn_limit
			)
			turn = clampf((desired_spin - spin) * 0.4 + desired_spin * 0.1, -1, 1)
		spin += chair.tuning.steering_torque * turn * inverse_inertia * STEP
		spin *= maxf(0, 1 - chair.tuning.steering_drag * STEP)
		spin = clampf(spin, -chair.tuning.maximum_spin, chair.tuning.maximum_spin)
		var drag := (
			chair.tuning.coast_drag
			+ chair.tuning.turning_drag * absf(spin) / chair.tuning.maximum_spin
		)
		velocity -= (
			Vector2.from_angle(heading)
			* chair.tuning.thrust
			* chair.jet_strength_after((index + 1) * STEP)
			* inverse_mass
			* STEP
		)
		velocity *= maxf(0, 1 - drag * STEP)
		velocity = velocity.limit_length(chair.tuning.maximum_speed)
		heading += spin * STEP
		point += velocity * STEP
		nearest = minf(nearest, point.distance_to(center) - radius)
	return nearest
