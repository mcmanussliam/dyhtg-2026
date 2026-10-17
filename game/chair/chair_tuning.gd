class_name ChairTuning
extends Resource
## Physics constants for continuous propulsion and torque-based steering.

@export_group("Movement")
@export var thrust: float = 700.0
@export var maximum_speed: float = 420.0
@export var coast_drag: float = 0.80
@export var turning_drag: float = 0.0

@export_group("Steering")
@export var steering_torque: float = 3200.0
@export var steering_drag: float = 3.5
@export var maximum_spin: float = 3.2

@export_group("Collision feedback")
@export var impact_threshold: float = 55.0
@export var impact_reference_speed: float = 260.0
@export var impact_decay: float = 2.5

@export_group("Spray")
@export var spray_range: float = 176.0
@export var half_angle_degrees: float = 24.0
@export var push_force: float = 1350.0
