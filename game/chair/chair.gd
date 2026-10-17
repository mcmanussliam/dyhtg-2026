class_name Chair
extends RigidBody2D
## Real linear/angular inertia; one steering command, unlimited continuous thrust.

signal bumped(impulse: Vector2)

@export var tuning: ChairTuning

var seat: int = 0
var colour := Color("f4d782")
var active: bool = true
var spraying: bool = true
var drive_enabled: bool = true
var falling: bool = false
var fall_velocity := Vector2.ZERO
var fall_spin: float = 0.0
var impact: float = 0.0
var spray_reach: float = 176.0
var command := ChairCommand.new()
var aim_angle: float:
	get:
		return global_rotation


func configure(index: int, tint: Color, heading: Vector2) -> void:
	seat = index
	colour = tint
	rotation = heading.angle()
	linear_damp = tuning.coast_drag
	angular_damp = tuning.steering_drag


func step(delta: float) -> void:
	spraying = active and drive_enabled
	if not spraying:
		return
	apply_central_impulse(-Vector2.from_angle(aim_angle) * tuning.thrust * delta)
	var steering := clampf(command.turn, -1.0, 1.0)
	apply_torque_impulse(steering * tuning.steering_torque * delta)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	impact = move_toward(impact, 0.0, state.step * tuning.impact_decay)
	var strongest := Vector2.ZERO
	for index in state.get_contact_count():
		var impulse := state.get_contact_impulse(index)
		# Some GodotPhysics builds report zero impulse here. Normal closing speed
		# still measures a real contact, including each body's angular motion.
		if impulse.is_zero_approx():
			var normal := state.get_contact_local_normal(index)
			var relative := (
				state.get_contact_local_velocity_at_position(index)
				- state.get_contact_collider_velocity_at_position(index)
			)
			var closing_speed := maxf(-relative.dot(normal), 0.0)
			impulse = normal * closing_speed * mass
		if impulse.length_squared() > strongest.length_squared():
			strongest = impulse
	var change := strongest.length() / mass
	if change > tuning.impact_threshold:
		impact = maxf(impact, minf(change / tuning.impact_reference_speed, 1.0))
		bumped.emit(strongest)
	state.linear_velocity = state.linear_velocity.limit_length(tuning.maximum_speed)
	state.angular_velocity = clampf(
		state.angular_velocity, -tuning.maximum_spin, tuning.maximum_spin
	)


func prepare_round() -> void:
	active = true
	drive_enabled = false
	spraying = false
	freeze = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	command.turn = 0.0


func begin_round() -> void:
	if not active:
		return
	freeze = false
	sleeping = false
	drive_enabled = true
	spraying = true


func stop_drive() -> void:
	drive_enabled = false
	spraying = false
	command.turn = 0.0
	freeze = true


func eliminate(reason: StringName) -> void:
	if not active:
		return
	fall_velocity = linear_velocity
	fall_spin = angular_velocity
	falling = reason == &"fall"
	active = false
	stop_drive()
	collision_layer = 0
	collision_mask = 0
	if not falling:
		visible = false
