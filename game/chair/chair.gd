class_name Chair
extends RigidBody2D
## Real linear/angular inertia; one steering command, unlimited continuous thrust.

@export var tuning: ChairTuning

var seat: int = 0
var colour := Color("ece2d0")
var active: bool = true
var spraying: bool = true
var impact: float = 0.0
var spray_reach: float = 176.0
var command := ChairCommand.new()
var aim_angle: float:
	get:
		return global_rotation

var _last_velocity := Vector2.ZERO


func configure(index: int, tint: Color, heading: Vector2) -> void:
	seat = index
	colour = tint
	rotation = heading.angle()
	linear_damp = tuning.coast_drag
	angular_damp = tuning.steering_drag


func step(delta: float) -> void:
	impact = move_toward(impact, 0.0, delta * 5.0)
	var velocity_change := (linear_velocity - _last_velocity).length()
	if velocity_change > 90.0:
		impact = minf(velocity_change / 400.0, 1.0)
	_last_velocity = linear_velocity
	spraying = active
	if not active:
		return
	apply_central_impulse(-Vector2.from_angle(aim_angle) * tuning.thrust * delta)
	var steering := clampf(command.turn, -1.0, 1.0)
	apply_torque_impulse(steering * tuning.steering_torque * delta)


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	state.linear_velocity = state.linear_velocity.limit_length(tuning.maximum_speed)
	state.angular_velocity = clampf(
		state.angular_velocity, -tuning.maximum_spin, tuning.maximum_spin
	)
