@tool
class_name ArenaStage
extends Node2D
## Surface support, arena rules and navigation belong to a stage, never scoring.

signal elimination_requested(seat: int, reason: StringName)
signal round_started
signal round_stopped

@export_group("Presentation")
@export_range(640.0, 2560.0, 1.0) var view_width: float = 1280.0
@export var view_focus := Vector2(640, 422)
@export_range(0.75, 1.5, 0.01) var content_scale: float = 1.0

@export_group("AI navigation")
@export_range(0.0, 150.0, 1.0) var ai_edge_margin := 0.0

var round_running: bool = false


func has_support(_world_point: Vector2) -> bool:
	return false


func elimination_reason(world_point: Vector2) -> StringName:
	return &"" if has_support(world_point) else &"fall"


func is_safe(world_point: Vector2, _margin: float = 0.0) -> bool:
	return elimination_reason(world_point) == &""


func safe_target(world_point: Vector2, _margin: float = 90.0) -> Vector2:
	return world_point


func is_path_safe(_from: Vector2, destination: Vector2, margin: float = 0.0) -> bool:
	return is_safe(destination, margin)


func recovery_target(_from: Vector2, predicted: Vector2, margin: float) -> Vector2:
	return safe_target(predicted, margin)


func navigation_target(_from: Vector2, destination: Vector2, margin: float) -> Vector2:
	return safe_target(destination, margin)


func spawn_pose(_index: int, _count: int) -> Transform2D:
	return global_transform


func bind_participants(_chairs: Array[Chair]) -> void:
	# Optional actor-specific hazards receive the round roster explicitly.
	pass


func start_round() -> void:
	if not round_running:
		round_running = true
		round_started.emit()


func stop_round() -> void:
	if round_running:
		round_running = false
		round_stopped.emit()


func tick_hazards(_delta: float) -> void:
	pass


func create_presentation(_parent: Node3D, _units_per_pixel: float) -> void:
	# Maps own visible geometry and physical support for 3D falling bodies.
	pass


func has_support_near(world_point: Vector2, radius: float) -> bool:
	if has_support(world_point):
		return true
	for index in 12:
		if has_support(world_point + Vector2.from_angle(index * TAU / 12.0) * radius):
			return true
	return false
