@tool
class_name FaultyFloorsStage
extends OfficeStage
## Chairs leave permanent holes behind them. The grid drives support, art and AI.

@export_range(0.5, 4.0, 0.1) var warning_duration := 2.2
@export_range(0.0, 5.0, 0.1) var opening_grace := 2.0

var grid := FaultyFloorGrid.new()
var _chairs: Array[Chair] = []
var _previous: Dictionary = {}
var _elapsed := 0.0
var _view: FaultyFloorView
var _routes: Dictionary = {}
var _route_revision := -1


func _ready() -> void:
	super._ready()
	grid.configure(Rect2(center - half_size, half_size * 2))


func bind_participants(chairs: Array[Chair]) -> void:
	_chairs = chairs
	_previous.clear()
	for chair in chairs:
		_previous[chair.seat] = to_local(chair.global_position)


func spawn_pose(index: int, count: int) -> Transform2D:
	var angle := PI * 1.25 + TAU * index / maxi(count, 1)
	return Transform2D(angle - PI / 2, to_global(center + Vector2.from_angle(angle) * 405))


func has_support(world_point: Vector2) -> bool:
	return grid.supported(to_local(world_point))


func is_safe(world_point: Vector2, margin: float = 0.0) -> bool:
	return grid.clear_at(to_local(world_point), _clearance(margin))


func is_path_safe(from: Vector2, destination: Vector2, margin: float = 0.0) -> bool:
	var start := to_local(from)
	var end := to_local(destination)
	var index := grid.index_at(start)
	var ignored := (
		index if index >= 0 and grid.states[index] == FaultyFloorGrid.State.WARNING else -1
	)
	var steps := maxi(1, ceili(start.distance_to(end) / (grid.cell_size.x * 0.2)))
	for step in range(1, steps + 1):
		if not grid.clear_at(start.lerp(end, float(step) / steps), _clearance(margin), ignored):
			return false
	return grid.clear_at(end, _clearance(margin))


func safe_target(world_point: Vector2, margin: float = 90.0) -> Vector2:
	if is_safe(world_point, margin):
		return world_point
	var nearest := INF
	var target := to_local(world_point)
	for index in grid.states.size():
		var point := grid.cell_rect(index).get_center()
		var distance := point.distance_squared_to(to_local(world_point))
		if distance < nearest and grid.clear_at(point, _clearance(margin)):
			nearest = distance
			target = point
	return to_global(target)


func navigation_target(from: Vector2, destination: Vector2, margin: float) -> Vector2:
	var goal := safe_target(destination, margin)
	if is_path_safe(from, goal, margin):
		return goal
	if _route_revision != grid.revision:
		_routes.clear()
		_route_revision = grid.revision
	var key := Vector2i(grid.index_at(to_local(from)), grid.index_at(to_local(goal)))
	if not _routes.has(key):
		_routes[key] = grid.route(key.x, key.y)
	var path: PackedInt32Array = _routes[key]
	# Commit to the first adjacent panel; skipping a bend can cut across a hole.
	if path.size() > 1:
		return to_global(grid.cell_rect(path[1]).get_center())
	return from


func recovery_target(from: Vector2, predicted: Vector2, margin: float) -> Vector2:
	return navigation_target(from, predicted, margin)


func tick_hazards(delta: float) -> void:
	if not round_running:
		return
	_elapsed += maxf(0, delta)
	var fallen := grid.advance(_elapsed, warning_duration)
	var chips: Array[PackedVector2Array] = []
	for index in fallen:
		var area := grid.cell_rect(index)
		chips.append(
			PackedVector2Array(
				[
					area.position - center,
					Vector2(area.end.x, area.position.y) - center,
					area.end - center,
					Vector2(area.position.x, area.end.y) - center
				]
			)
		)
		if _view != null:
			_view.drop(index)
	if not chips.is_empty():
		for prop in $Furniture.get_children():
			if prop is OfficeProp:
				prop.release_for_fracture(self, chips, center)
	for chair in _chairs:
		if not is_instance_valid(chair) or not chair.active or chair.falling:
			continue
		var point := to_local(chair.global_position)
		var previous: Vector2 = _previous.get(chair.seat, point)
		_previous[chair.seat] = point
		if _elapsed < opening_grace:
			continue
		# Sweep travelled floor as well as endpoints, including boosted/spectator steps.
		var steps := maxi(1, ceili(previous.distance_to(point) / (grid.cell_size.x * 0.25)))
		for step in range(steps + 1):
			var touched := grid.arm(
				previous.lerp(point, float(step) / steps), 20 * chair.size_scale, _elapsed
			)
			if _view != null:
				for index in touched:
					_view.warn(index)
	if _view != null:
		_view.update_clock(_elapsed)


func stop_round() -> void:
	super.stop_round()
	if _view != null:
		_view.set_active(false)


func create_presentation(parent: Node3D, units_per_pixel: float) -> void:
	_view = FaultyFloorView.new()
	_view.configure(self, grid, parent, units_per_pixel, warning_duration)
	_view.update_clock(_elapsed)
	_create_office_presentation(parent, units_per_pixel)


func set_render_warmup(enabled: bool) -> void:
	if _view != null:
		_view.set_render_warmup(enabled)


func _create_carpet(
	_parent: Node3D, _units: float, _area: Rect2, _colour: Color, _label: String
) -> void:
	# Carpet colours are part of each panel, so they never bridge a missing floor.
	pass


func _clearance(margin: float) -> float:
	# Single-panel routes remain traversable; never demand more than a chair's width.
	return clampf(margin, 0, 30 * content_scale)
