@tool
extends OfficeStage
## The office after dark. Guards patrol loops between desk pods with flashlights; a
## lit player is chased until hard furniture breaks the guard's sight. Guards arrive
## through the rear door on the live round clock, up to a nightly limit.

@export_range(0.0, 30.0, 0.5) var first_arrival := 2.5
@export_range(3.0, 60.0, 1.0) var arrival_interval := 16.0
@export_range(1, 8, 1) var max_guards := 4
## Local patrol loops through the aisles; guards take them in turn.
@export var routes: Array[PackedVector2Array] = [
	PackedVector2Array(
		[
			Vector2(750, -90),
			Vector2(1185, -90),
			Vector2(1185, 425),
			Vector2(1185, 950),
			Vector2(640, 950),
			Vector2(95, 950),
			Vector2(95, 425),
			Vector2(95, -90)
		]
	),
	PackedVector2Array(
		[
			Vector2(640, 425),
			Vector2(640, 950),
			Vector2(1185, 950),
			Vector2(1185, 425),
			Vector2(640, 425),
			Vector2(640, -90),
			Vector2(95, -90),
			Vector2(95, 425)
		]
	),
	PackedVector2Array(
		[
			Vector2(95, 425),
			Vector2(95, 950),
			Vector2(640, 950),
			Vector2(640, 425),
			Vector2(1185, 425),
			Vector2(1185, -90),
			Vector2(640, -90),
			Vector2(640, 425)
		]
	),
]

var guards: Array[NightGuard] = []
var _chairs: Array[Chair] = []
var _elapsed := 0.0
var _next_arrival := 0.0
var _world: Node3D
var _warmup_guard: NightGuardModel
var _cover: Array[OfficeProp] = []
var _units := 1.0 / RenderStyle.PIXELS_PER_UNIT


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_next_arrival = first_arrival
	# Fixed furniture blocks a guard's sight; AI uses it as cover.
	for prop in $Furniture.get_children():
		if prop is OfficeProp and prop is StaticBody2D:
			_cover.append(prop)


func bind_participants(chairs: Array[Chair]) -> void:
	_chairs = chairs
	for guard in guards:
		guard.chairs = chairs


func spawn_pose(index: int, count: int) -> Transform2D:
	# Players start in the open middle band, facing along it, well away from the door.
	var columns := ceili(count / 2.0)
	var column := index % columns
	var row := index / columns
	var x := lerpf(170, 1110, (column + 0.5) / columns)
	var point := Vector2(x, center.y - 44 if row == 0 else center.y + 56)
	return Transform2D(0.0 if row == 0 else PI, to_global(point))


func is_spawn_safe(world_point: Vector2, clearance: float) -> bool:
	var point := to_local(world_point) - center
	return (
		super.is_spawn_safe(world_point, clearance)
		and (absf(point.x - 110) > 90 + clearance or point.y > -380)
	)


func tick_hazards(delta: float) -> void:
	if not round_running:
		return
	_elapsed += delta
	for guard in guards:
		guard.tick(delta)
	if _elapsed >= _next_arrival and guards.size() < max_guards and _entrance_clear():
		_add_guard()
		_next_arrival = _elapsed + arrival_interval


func _entrance_clear() -> bool:
	var threshold := to_global(Vector2(750, center.y - half_size.y + 128))
	for guard in guards:
		if (
			guard.phase == NightGuard.Phase.ENTERING
			or guard.global_position.distance_to(threshold) < 110
		):
			return false
	return true


func _add_guard() -> void:
	var guard := NightGuard.new()
	guard.name = "Guard%d" % (guards.size() + 1)
	add_child(guard)
	var route := PackedVector2Array()
	for point in routes[guards.size() % routes.size()]:
		route.append(to_global(point))
	guard.configure(self, route, 0)
	guard.chairs = _chairs
	var doorway := Vector2(750, center.y - half_size.y)
	guard.begin_entry(to_global(doorway - Vector2(0, 80)), to_global(doorway + Vector2(0, 128)))
	guards.append(guard)
	if is_instance_valid(_world):
		guard.create_presentation(_world, _units)


func stop_round() -> void:
	super.stop_round()
	for guard in guards:
		guard.stop()


func set_render_warmup(enabled: bool) -> void:
	# Guards arrive after the title, so warm a hidden flashlight and alert marker now.
	if enabled and guards.is_empty() and is_instance_valid(_world):
		_warmup_guard = NightGuardModel.new()
		_world.add_child(_warmup_guard)
		_warmup_guard.build(10, 0.4)
		_warmup_guard.set_alert(true)
		var hidden := to_global(Vector2(750, center.y - half_size.y - 60)) * _units
		_warmup_guard.position = Vector3(hidden.x, 0, hidden.y)
	elif not enabled and is_instance_valid(_warmup_guard):
		_warmup_guard.queue_free()
		_warmup_guard = null
	for guard in guards:
		guard.set_render_warmup(enabled)


func create_presentation(parent: Node3D, units_per_pixel: float) -> void:
	_world = parent
	_units = units_per_pixel
	super.create_presentation(parent, units_per_pixel)
	for prop in _cover:
		var model := parent.get_node_or_null(NodePath(String(prop.name))) as Node3D
		if model == null:
			continue
		for node in [model] + model.find_children("*", "GeometryInstance3D", true, false):
			if node is GeometryInstance3D:
				node.layers |= NightGuardModel.COVER_LAYER
	# Moonlight through the rear windows; flashlights do the real lighting.
	var environment := (parent.get_node("StudioEnvironment") as WorldEnvironment).environment
	environment.ambient_light_color = Color(0.55, 0.62, 0.9)
	environment.ambient_light_energy = 0.13
	var key := parent.get_node("KeyLight") as DirectionalLight3D
	key.light_color = Color(0.62, 0.7, 1.0)
	key.light_energy = 0.2
	(parent.get_node("FillLight") as DirectionalLight3D).light_energy = 0.04
	for guard in guards:
		guard.create_presentation(parent, units_per_pixel)


func _create_wall_details(parent: Node3D, units: float) -> void:
	# After hours the office door stands open onto a dark corridor for arriving guards.
	super._create_wall_details(parent, units)
	var door := parent.get_node("OfficeDoor") as Node3D
	for child in door.get_children():
		child.free()
	var frame := ModelGeometry.material(Color("293946"))
	var dark := ModelGeometry.material(Color("07090d"), 0, 1)
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side in [-1.0, 1.0]:
		ModelGeometry.box(door, Vector3(side * 0.86, 1.27, 0.02), Vector3(0.13, 2.54, 0.18), frame)
	ModelGeometry.box(door, Vector3(0, 2.48, 0.02), Vector3(1.85, 0.12, 0.18), frame)
	ModelGeometry.box(door, Vector3(0, 1.21, 0.0), Vector3(1.6, 2.42, 0.1), dark)


func is_safe(world_point: Vector2, margin: float = 0.0) -> bool:
	if not super.is_safe(world_point, margin):
		return false
	for guard in guards:
		if guard.illuminates(world_point, margin * 0.5):
			return false
	return true


func safe_target(world_point: Vector2, margin: float = 90.0) -> Vector2:
	var point := super.safe_target(world_point, margin)
	for guard in guards:
		if guard.illuminates(point, 40):
			return _hiding_spot(point, guard, margin)
	return point


## The nearest unlit point behind hard furniture, as seen from the guard.
func _hiding_spot(point: Vector2, guard: NightGuard, margin: float) -> Vector2:
	var best := point + (point - guard.global_position).normalized() * 260
	var best_distance := INF
	for prop in _cover:
		var away := (prop.global_position - guard.global_position).normalized()
		var spot := super.safe_target(prop.global_position + away * 115, margin)
		var distance := spot.distance_squared_to(point)
		if distance < best_distance and not guard.illuminates(spot, 30):
			best = spot
			best_distance = distance
	return super.safe_target(best, margin)
