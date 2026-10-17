@tool
class_name ArenaStage
extends Node2D
## Surface support, arena rules and navigation belong to a stage, never scoring.

signal elimination_requested(seat: int, reason: StringName)

@export_group("Presentation")
@export_range(640.0, 2560.0, 1.0) var view_width: float = 1280.0
@export var view_focus := Vector2(640, 422)

var round_running: bool = false


func has_support(_world_point: Vector2) -> bool:
	return false


func elimination_reason(world_point: Vector2) -> StringName:
	return &"" if has_support(world_point) else &"fall"


func is_safe(world_point: Vector2, _margin: float = 0.0) -> bool:
	return elimination_reason(world_point) == &""


func safe_target(world_point: Vector2, _margin: float = 90.0) -> Vector2:
	return world_point


func spawn_pose(_index: int, _count: int) -> Transform2D:
	return global_transform


func start_round() -> void:
	round_running = true


func stop_round() -> void:
	round_running = false


func tick_hazards(_delta: float) -> void:
	pass


func create_presentation(_parent: Node3D, _units_per_pixel: float) -> void:
	# Maps own visible geometry and physical support for 3D falling bodies.
	pass
