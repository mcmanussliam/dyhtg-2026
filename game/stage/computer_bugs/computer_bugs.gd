@tool
class_name ComputerBugsStage
extends OfficeStage
## Broken, bugged computers kill anyone in their zone. Infection jumps to clean computers
## along straight, harmless columns of bugs, while one slow technician repairs a single
## computer at a time. Bugs never roam: the danger is exactly the infected zones.
## All timing runs on the live round clock.

enum Fixer { HIDDEN, WALKING, REPAIRING }

## A fresh zone covers ZONE_RADIUS; left alone it swells towards MAX_ZONE_RADIUS.
const ZONE_RADIUS := 105.0
const MAX_ZONE_RADIUS := 250.0
const COLONY_SIZE := 28
const COLUMN_SIZE := 7
const CAPACITY := 640
## Zones fuse like metaballs. The kernel and threshold are shared with danger_blob.gdshader.
const FIELD_REACH := 1.35
const FIELD_THRESHOLD := 0.2038
const SCREEN_SHADER = preload("res://game/stage/computer_bugs/screen_glitch.gdshader")
const BLOB_SHADER = preload("res://game/stage/computer_bugs/danger_blob.gdshader")
## Walkways the technician follows: aisle corridors between the benches, and rooms' edges.
const CORRIDOR_X := [110.0, 385.0, 655.0, 925.0, 1215.0]
const CORRIDOR_Y := [-80.0, 436.0, 960.0]
const DESK_ROWS := [100.0, 172.0, 700.0, 772.0]
const DOOR := Vector2(750, -120)

@export_range(0.5, 10.0, 0.5) var first_infection := 2.0
@export_range(0.2, 3.0, 0.1) var warning_seconds := 1.2
@export_range(3.0, 60.0, 1.0) var zone_growth_seconds := 22.0
@export_range(1.0, 20.0, 0.5) var spread_interval := 5.0
@export_range(0.3, 10.0, 0.1) var minimum_spread := 0.9
@export_range(5.0, 120.0, 1.0) var escalation_seconds := 60.0
@export_range(0.0, 20.0, 0.5) var fixer_delay := 6.0
@export_range(60.0, 500.0, 5.0) var fixer_speed := 150.0
@export_range(60.0, 500.0, 5.0) var fixer_top_speed := 300.0
@export_range(2.0, 20.0, 0.5) var repair_seconds := 7.0
@export_range(1.0, 20.0, 0.5) var minimum_repair := 3.5

var computers: Array[OfficeProp] = []
var infected: Array[bool] = []
var infections_total := 0
var repairs_total := 0
var fixer_state := Fixer.HIDDEN
var fixer_position := Vector2.ZERO
var fixer_target := -1
var _chairs: Array[Chair] = []
var _elapsed := 0.0
var _infected_at := PackedFloat64Array()
var _inbound: Array[bool] = []
var _next_spread := 0.0
var _columns: Array[Dictionary] = []
var _repair_progress := 0.0
var _fixer_ready_at := INF
var _layout: Array[PackedVector2Array] = []
var _bug_heading: Array[PackedFloat32Array] = []
var _bug_phase: Array[PackedFloat32Array] = []
var _screens: Array[MeshInstance3D] = []
var _blob_material: ShaderMaterial
var _zone_data := PackedVector4Array()
var _walkways := AStar2D.new()
var _spot_ids := PackedInt32Array()
var _node := 0
var _door_id := 0
var _path := PackedVector2Array()
var _path_index := 0
var _heading := PI / 2
var _view: BugSwarmView
var _fixer_model: BugFixer
var _units := 1.0 / RenderStyle.PIXELS_PER_UNIT
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_random.randomize()
	for prop in $Furniture.get_children():
		if prop is OfficeProp and String(prop.name).begins_with("Computer"):
			computers.append(prop)
			infected.append(false)
			_inbound.append(false)
			_infected_at.append(INF)
			# Each colony has a fixed pattern: bugs sit and skitter on the spot.
			var offsets := PackedVector2Array()
			var headings := PackedFloat32Array()
			var phases := PackedFloat32Array()
			for bug in COLONY_SIZE:
				offsets.append(Vector2.from_angle(_random.randf() * TAU) * sqrt(_random.randf()))
				headings.append(_random.randf() * TAU)
				phases.append(_random.randf() * TAU)
			_layout.append(offsets)
			_bug_heading.append(headings)
			_bug_phase.append(phases)
	_build_walkways()


func _build_walkways() -> void:
	var ids := {}
	var next_id := 0
	var ys := DESK_ROWS.duplicate()
	ys.append_array(CORRIDOR_Y)
	ys.sort()
	for x: float in CORRIDOR_X:
		for y: float in ys:
			_walkways.add_point(next_id, Vector2(x, y))
			ids[Vector2(x, y)] = next_id
			next_id += 1
	for x: float in CORRIDOR_X:
		for index in ys.size() - 1:
			_walkways.connect_points(ids[Vector2(x, ys[index])], ids[Vector2(x, ys[index + 1])])
	for y: float in CORRIDOR_Y:
		for index in CORRIDOR_X.size() - 1:
			_walkways.connect_points(
				ids[Vector2(CORRIDOR_X[index], y)], ids[Vector2(CORRIDOR_X[index + 1], y)]
			)
	# The doorway joins the top aisle, and every repair spot opens onto its nearest aisle.
	_door_id = next_id
	_node = _door_id
	_walkways.add_point(_door_id, DOOR)
	_walkways.connect_points(_door_id, ids[Vector2(CORRIDOR_X[2], CORRIDOR_Y[0])])
	_walkways.connect_points(_door_id, ids[Vector2(CORRIDOR_X[3], CORRIDOR_Y[0])])
	next_id += 1
	for index in computers.size():
		var desk := to_local(computer_position(index))
		var spot := desk + Vector2(105, 0)
		var aisle := 0.0
		var gap := INF
		for x: float in CORRIDOR_X:
			if absf(x - spot.x) < gap:
				gap = absf(x - spot.x)
				aisle = x
		_walkways.add_point(next_id, spot)
		_walkways.connect_points(next_id, ids[Vector2(aisle, desk.y)])
		_spot_ids.append(next_id)
		next_id += 1


func bind_participants(chairs: Array[Chair]) -> void:
	_chairs = chairs


func start_round() -> void:
	if not round_running:
		_elapsed = 0.0
		_next_spread = 0.0
		infections_total = 0
		repairs_total = 0
		_columns.clear()
		_repair_progress = 0.0
		_fixer_ready_at = INF
		fixer_state = Fixer.HIDDEN
		fixer_target = -1
		fixer_position = to_global(DOOR)
		_node = _door_id
		_path = PackedVector2Array()
		_path_index = 0
		for index in computers.size():
			infected[index] = false
			_inbound[index] = false
			_infected_at[index] = INF
		_refresh()
	super.start_round()


func spawn_pose(index: int, _count: int) -> Transform2D:
	# Seats start in the open aisles between the workstation rows.
	var points := [
		Vector2(760, 130),
		Vector2(1060, 700),
		Vector2(1060, 130),
		Vector2(760, 700),
		Vector2(400, 420),
		Vector2(760, 420),
		Vector2(1060, 420),
		Vector2(150, 250),
		Vector2(650, 250),
		Vector2(650, 600)
	]
	var point: Vector2 = points[index % points.size()]
	return Transform2D((center - point).angle() + PI, to_global(point))


func difficulty() -> float:
	return clampf(_elapsed / maxf(escalation_seconds, 1), 0, 1)


func current_spread() -> float:
	return lerpf(spread_interval, minimum_spread, 1.0 - pow(1.0 - difficulty(), 2.0))


## Both the technician's pace and his repair time improve as the round goes on, but
## never enough to out-run the infection.
func current_fixer_speed() -> float:
	return lerpf(fixer_speed, fixer_top_speed, difficulty())


func current_repair_seconds() -> float:
	return lerpf(repair_seconds, minimum_repair, difficulty())


func columns_per_wave() -> int:
	return 1 + floori(difficulty() * 2.5)


func infected_count() -> int:
	return infected.count(true)


func computer_position(index: int) -> Vector2:
	return computers[index].global_position


## The zone's current reach. It grows the longer a computer stays broken, and later
## infections also start wider, so the round gets steadily more lethal.
func zone_radius(index: int) -> float:
	if not infected[index]:
		return ZONE_RADIUS
	var age := maxf(_elapsed - _infected_at[index], 0.0)
	var start := lerpf(ZONE_RADIUS, ZONE_RADIUS * 1.35, difficulty())
	return lerpf(start, MAX_ZONE_RADIUS, clampf(age / zone_growth_seconds, 0.0, 1.0))


## Sum of every zone's smooth falloff at a point. Overlapping zones fuse: the combined
## shape is wider than either circle where they meet. A single zone covers exactly its
## radius. Pass armed_only to count lethal zones alone.
func danger_field(world_point: Vector2, extra: float = 0.0, armed_only: bool = false) -> float:
	var total := 0.0
	for index in computers.size():
		if not infected[index] or (armed_only and not is_armed(index)):
			continue
		var radius := zone_radius(index) + extra
		var reach := radius * FIELD_REACH
		var d2 := computer_position(index).distance_squared_to(world_point)
		if d2 >= reach * reach:
			continue
		var falloff := 1.0 - d2 / (reach * reach)
		total += falloff * falloff
	return total


func in_danger(world_point: Vector2, extra: float = 0.0, armed_only: bool = false) -> bool:
	return danger_field(world_point, extra, armed_only) >= FIELD_THRESHOLD


## Is the infected computer's zone lethal yet? It is announced first.
func is_armed(index: int) -> bool:
	return infected[index] and _elapsed >= _infected_at[index] + warning_seconds


func tick_hazards(delta: float) -> void:
	if not round_running or computers.is_empty():
		return
	_elapsed += maxf(delta, 0)
	if _elapsed >= first_infection and infections_total == 0 and _columns.is_empty():
		_infect(_random.randi_range(0, computers.size() - 1))
		_next_spread = _elapsed + current_spread()
		_fixer_ready_at = _elapsed + fixer_delay
	if infected_count() > 0 and _elapsed >= _next_spread:
		for wave in columns_per_wave():
			_send_column()
		_next_spread = _elapsed + current_spread()
	_advance_columns(delta)
	_advance_fixer(delta)
	_sweep_chairs()
	_refresh()


func _infect(index: int) -> void:
	if infected[index]:
		return
	infected[index] = true
	_inbound[index] = false
	_infected_at[index] = _elapsed
	infections_total += 1


## A column of bugs crawls straight from a random infected computer to a random clean
## one anywhere in the office, so the infection leaps about rather than creeping.
func _send_column() -> void:
	var sources: Array[int] = []
	var targets: Array[int] = []
	for index in computers.size():
		if infected[index]:
			sources.append(index)
		elif not _inbound[index] and index != fixer_target:
			targets.append(index)
	if sources.is_empty() or targets.is_empty():
		return
	var source: int = sources[_random.randi_range(0, sources.size() - 1)]
	var target: int = targets[_random.randi_range(0, targets.size() - 1)]
	_inbound[target] = true
	_columns.append(
		{
			"from": computer_position(source),
			"to": computer_position(target),
			"target": target,
			"distance": 0.0,
			"speed": lerpf(260.0, 520.0, difficulty())
		}
	)


func _advance_columns(delta: float) -> void:
	for column in _columns.duplicate():
		column.distance += column.speed * delta
		if column.distance >= column.from.distance_to(column.to):
			_columns.erase(column)
			_infect(column.target)


func _advance_fixer(delta: float) -> void:
	if fixer_state == Fixer.HIDDEN:
		if _elapsed >= _fixer_ready_at:
			fixer_state = Fixer.WALKING
		return
	if fixer_state == Fixer.WALKING:
		if fixer_target < 0 or not infected[fixer_target]:
			_plan_route()
		if fixer_target < 0:
			return
		_follow_route(delta)
	else:
		_repair_progress += delta / current_repair_seconds()
		if _repair_progress >= 1.0:
			infected[fixer_target] = false
			_infected_at[fixer_target] = INF
			repairs_total += 1
			fixer_target = -1
			_repair_progress = 0.0
			fixer_state = Fixer.WALKING
			_plan_route()


## Picks the broken computer with the shortest walk along the aisles.
func _plan_route() -> void:
	fixer_target = -1
	_path = PackedVector2Array()
	_path_index = 0
	var best_length := INF
	for index in computers.size():
		if not infected[index]:
			continue
		var route := _walkways.get_point_path(_node, _spot_ids[index])
		var length := 0.0
		for step in range(1, route.size()):
			length += route[step - 1].distance_to(route[step])
		if length < best_length:
			best_length = length
			fixer_target = index
			_path = route
	for step in _path.size():
		_path[step] = to_global(_path[step])
	_path_index = 1 if _path.size() > 1 else 0
	_repair_progress = 0.0


func _follow_route(delta: float) -> void:
	var travel := current_fixer_speed() * delta
	while travel > 0.0 and _path_index < _path.size():
		var offset := _path[_path_index] - fixer_position
		if offset.length() <= travel:
			fixer_position = _path[_path_index]
			travel -= offset.length()
			_path_index += 1
		else:
			fixer_position += offset.normalized() * travel
			_heading = rotate_toward(_heading, offset.angle(), 14.0 * delta)
			travel = 0.0
	if _path_index >= _path.size():
		_node = _spot_ids[fixer_target]
		fixer_state = Fixer.REPAIRING
		_repair_progress = 0.0


func _sweep_chairs() -> void:
	for chair in _chairs:
		if not is_instance_valid(chair) or not chair.active or chair.falling:
			continue
		if not in_danger(chair.global_position, 0.0, true):
			continue
		# Bowl the chair away from the nearest lethal computer rather than deleting it.
		var source := Vector2.ZERO
		var nearest := INF
		for index in computers.size():
			if not is_armed(index):
				continue
			var distance := computer_position(index).distance_to(chair.global_position)
			if distance < nearest:
				nearest = distance
				source = computer_position(index)
		var away := (chair.global_position - source).normalized()
		if away.length_squared() < 0.5:
			away = Vector2.RIGHT
		var planar := away * 16.0
		chair.set_knockout_launch(
			Vector3(planar.x, 9.0, planar.y), Vector3(away.y, 0.5, -away.x) * 8.0
		)
		elimination_requested.emit(chair.seat, &"bugs")


func is_safe(world_point: Vector2, margin: float = 0.0) -> bool:
	return super.is_safe(world_point, margin) and not in_danger(world_point, 30.0 + margin * 0.4)


func is_path_safe(from: Vector2, destination: Vector2, margin: float = 0.0) -> bool:
	for step in range(1, 5):
		if not is_safe(from.lerp(destination, step / 4.0), margin):
			return false
	return true


func safe_target(world_point: Vector2, margin: float = 90.0) -> Vector2:
	var point := super.safe_target(world_point, margin)
	for pass_index in 6:
		if not in_danger(point, 60.0 + margin * 0.4):
			break
		# Retreat away from the heart of the nearest zone, then re-check.
		var nearest := -1
		var nearest_distance := INF
		for index in computers.size():
			if not infected[index]:
				continue
			var distance := computer_position(index).distance_to(point)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = index
		if nearest < 0:
			break
		var away := (point - computer_position(nearest)).normalized()
		if away.length_squared() < 0.5:
			away = Vector2.RIGHT
		point = super.safe_target(
			computer_position(nearest) + away * (zone_radius(nearest) + 120.0 + margin * 0.4),
			margin
		)
	return point


func create_presentation(parent: Node3D, units_per_pixel: float) -> void:
	super.create_presentation(parent, units_per_pixel)
	_units = units_per_pixel
	_view = BugSwarmView.new()
	parent.add_child(_view)
	_view.build(CAPACITY, units_per_pixel)
	var screen_material := ShaderMaterial.new()
	screen_material.shader = SCREEN_SHADER
	for prop in computers:
		# A corrupted screen lies over each healthy monitor while infected.
		var model := prop.get("_presentation") as Node3D
		var screen := MeshInstance3D.new()
		var quad := BoxMesh.new()
		quad.size = Vector3(0.80, 0.44, 0.012)
		screen.mesh = quad
		screen.material_override = screen_material
		screen.position = Vector3(0, 1.30, -0.255)
		screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		screen.hide()
		if is_instance_valid(model):
			model.add_child(screen)
		_screens.append(screen)
	# One floor decal draws every zone as a single fluid shape.
	_blob_material = ShaderMaterial.new()
	_blob_material.shader = BLOB_SHADER
	_zone_data.resize(16)
	_blob_material.set_shader_parameter("zones", _zone_data)
	var floor_plane := PlaneMesh.new()
	floor_plane.size = half_size * 2 * units_per_pixel
	var blob := MeshInstance3D.new()
	blob.name = "DangerBlob"
	blob.mesh = floor_plane
	blob.material_override = _blob_material
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var floor_centre := to_global(center) * units_per_pixel
	blob.position = Vector3(floor_centre.x, 0.014, floor_centre.y)
	parent.add_child(blob)
	_fixer_model = BugFixer.new()
	_fixer_model.name = "BugFixer"
	_fixer_model.scale = Vector3.ONE * content_scale
	parent.add_child(_fixer_model)
	_fixer_model.build()
	_fixer_model.hide()
	_refresh()


func set_render_warmup(enabled: bool) -> void:
	# First-use shader and multimesh paths draw under the black title card.
	if not is_instance_valid(_view):
		return
	if enabled:
		for screen in _screens:
			screen.show()
		_fixer_model.show()
		_view.multimesh.visible_instance_count = 1
	else:
		_refresh()


func _update_zone_data() -> void:
	if _zone_data.size() < 16:
		return
	for index in 16:
		if index >= computers.size() or not infected[index]:
			_zone_data[index] = Vector4.ZERO
			continue
		var position := computer_position(index) * _units
		_zone_data[index] = Vector4(
			position.x, position.y, zone_radius(index) * _units, 2.0 if is_armed(index) else 1.0
		)
	if is_instance_valid(_blob_material):
		_blob_material.set_shader_parameter("zones", _zone_data)


func _refresh() -> void:
	for index in _screens.size():
		var sick := index < infected.size() and infected[index]
		if is_instance_valid(_screens[index]):
			_screens[index].visible = sick
	_update_zone_data()
	if not is_instance_valid(_view):
		return
	var points := PackedVector2Array()
	var headings := PackedFloat32Array()
	var phases := PackedFloat32Array()
	var danger := PackedByteArray()
	for index in computers.size():
		if not infected[index]:
			continue
		var age := _elapsed - _infected_at[index]
		# The colony spreads out from the machine, and thins as it is repaired.
		var spread := clampf(age / 2.0, 0.15, 1.0)
		var share := 1.0
		if index == fixer_target and fixer_state == Fixer.REPAIRING:
			share = 1.0 - _repair_progress
		var radius := zone_radius(index)
		# A wider zone carries a bigger colony.
		var colony := lerpf(
			COLONY_SIZE * 0.55,
			COLONY_SIZE,
			(radius - ZONE_RADIUS) / (MAX_ZONE_RADIUS - ZONE_RADIUS)
		)
		var amount := ceili(clampf(colony, 8.0, COLONY_SIZE) * share)
		for bug in amount:
			if points.size() >= CAPACITY:
				break
			points.append(computer_position(index) + _layout[index][bug] * radius * 0.92 * spread)
			headings.append(_bug_heading[index][bug])
			phases.append(_bug_phase[index][bug])
			danger.append(2 if is_armed(index) else 1)
	for column in _columns:
		if points.size() >= CAPACITY - COLUMN_SIZE:
			break
		var direction: Vector2 = (column.to - column.from).normalized()
		for bug in COLUMN_SIZE:
			var along: float = column.distance - bug * 22.0
			if along < 0.0 or along > column.from.distance_to(column.to):
				continue
			var sway := sin(bug * 1.7 + _elapsed * 6.0) * 9.0
			points.append(column.from + direction * along + direction.orthogonal() * sway)
			headings.append(direction.angle())
			phases.append(bug * 0.9)
			danger.append(0)
	_view.update(points, headings, phases, danger, _elapsed)
	if is_instance_valid(_fixer_model):
		_fixer_model.visible = fixer_state != Fixer.HIDDEN
		_fixer_model.position = Vector3(fixer_position.x * _units, 0, fixer_position.y * _units)
		if fixer_state == Fixer.REPAIRING and fixer_target >= 0:
			_heading = rotate_toward(
				_heading, (computer_position(fixer_target) - fixer_position).angle(), 0.5
			)
		_fixer_model.rotation.y = -_heading + PI / 2
		_fixer_model.animate(_elapsed, fixer_state == Fixer.WALKING, fixer_state == Fixer.REPAIRING)
