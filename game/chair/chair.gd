class_name Chair
extends RigidBody2D
## Real linear/angular inertia; one steering command, unlimited continuous thrust.

signal bumped(impulse: Vector2)
signal fall_confirmed(seat: int)

@export var tuning: ChairTuning

var size_scale: float = 1.0
var seat: int = 0
var hat_id: StringName = &"none"
var skin: CharacterSkin
var colour := Color("f4d782")
var active: bool = true
var spraying: bool = true
var jet_strength: float = 1.0
var drive_enabled: bool = true
var falling: bool = false
var fall_velocity := Vector2.ZERO
var fall_spin: float = 0.0
# World-space 3D velocities are presentation data for an already eliminated actor.
var knockout_velocity := Vector3.ZERO
var knockout_spin := Vector3.ZERO
var impact: float = 0.0
var spray_reach: float = 176.0
var command := ChairCommand.new()
var aim_angle: float:
	get:
		return global_rotation

var _fall_reported := false
var _ramp_duration := 0.0
var _ramp_elapsed := 0.0


func resize_for_stage(factor: float) -> void:
	var ratio := factor / size_scale
	if is_equal_approx(ratio, 1.0):
		return
	var collision := get_node("CollisionShape2D") as CollisionShape2D
	var shape := collision.shape.duplicate() as CapsuleShape2D
	shape.radius *= ratio
	shape.height *= ratio
	collision.shape = shape
	# Resize the shape rather than scaling a live rigid body. Keep its steering
	# acceleration consistent as the larger footprint increases angular inertia.
	tuning = tuning.duplicate() as ChairTuning
	tuning.steering_torque *= ratio * ratio
	tuning.spray_range *= ratio
	size_scale = factor


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
	_ramp_elapsed = minf(_ramp_elapsed + maxf(delta, 0), _ramp_duration)
	jet_strength = jet_strength_after(0.0)
	# Turning scrubs momentum through drag; straight travel retains its drift.
	var turn_ratio := clampf(absf(angular_velocity) / maxf(tuning.maximum_spin, 0.01), 0.0, 1.0)
	linear_damp = tuning.coast_drag + tuning.turning_drag * turn_ratio
	apply_central_impulse(-Vector2.from_angle(aim_angle) * tuning.thrust * jet_strength * delta)
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
	falling = false
	_fall_reported = false
	_ramp_duration = 0.0
	_ramp_elapsed = 0.0
	jet_strength = 0.0
	knockout_velocity = Vector3.ZERO
	knockout_spin = Vector3.ZERO
	drive_enabled = false
	spraying = false
	freeze = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	command.turn = 0.0


func start_extinguisher_ramp(seconds: float) -> void:
	_ramp_duration = maxf(seconds, 0.0)
	_ramp_elapsed = 0.0
	jet_strength = jet_strength_after(0.0)


func jet_strength_after(seconds: float) -> float:
	# One curve drives propulsion, spray pushes and presentation. Steering stays fully responsive.
	return smoothstep(0, _ramp_duration, _ramp_elapsed + seconds) if _ramp_duration > 0 else 1.0


func begin_round() -> void:
	if not active:
		return
	freeze = false
	sleeping = false
	drive_enabled = true
	spraying = true
	jet_strength = jet_strength_after(0.0)


func stop_drive() -> void:
	drive_enabled = false
	spraying = false
	command.turn = 0.0
	freeze = true


func begin_fall() -> void:
	if not active or falling:
		return
	fall_velocity = linear_velocity
	fall_spin = angular_velocity
	falling = true
	stop_drive()
	collision_layer = 0
	collision_mask = 0


func land_from_fall(point: Vector2, heading: float, velocity: Vector2, spin: float) -> void:
	if not active or not falling or _fall_reported:
		return
	falling = false
	global_position = point
	global_rotation = heading
	collision_layer = 2
	collision_mask = 3
	begin_round()
	linear_velocity = velocity.limit_length(tuning.maximum_speed)
	angular_velocity = clampf(spin, -tuning.maximum_spin, tuning.maximum_spin)


func confirm_fall() -> void:
	if active and falling and not _fall_reported:
		_fall_reported = true
		fall_confirmed.emit(seat)


func set_knockout_launch(velocity: Vector3, spin: Vector3) -> void:
	if active and not falling:
		knockout_velocity = velocity
		knockout_spin = spin


func eliminate(reason: StringName) -> void:
	if not active:
		return
	if reason in [&"fall", &"bull"]:
		begin_fall()
	active = false
	stop_drive()
	collision_layer = 0
	collision_mask = 0
	if not falling:
		visible = false
