@tool
class_name UnderConstructionStage
extends OfficeStage
## Diggers drive through fixed, pre-smashed wall openings along telegraphed lanes.
## Two lanes cross the room horizontally and two vertically, so all four walls have holes.

## Lane centre offsets from the room centre. Lanes 0-1 run along X, lanes 2-3 along Y.
## Openings sit where no furniture, window, door or clock stands in front of them.
const LANE_OFFSETS := [-332.0, 8.0, -536.0, 0.0]
const OPENING := 170.0
## The wall is cut a little wider than the digger; ragged brick fills the difference.
const WALL_CUT := OPENING + 36.0
const MAX_VEHICLES := 12

@export_range(1.0, 10.0, 0.5) var first_warning := 2.5
@export_range(2.0, 30.0, 0.5) var arrival_interval := 4.0
@export_range(0.1, 10.0, 0.05) var minimum_interval := 0.35
@export_range(1.0, 300.0, 1.0) var escalation_seconds := 22.0

var vehicles: Array[ConstructionVehicle] = []
var _chairs: Array[Chair] = []
var _elapsed := 0.0
var _next_arrival := 2.5
var _deployed := 0
var _departures := PackedInt32Array([0, 0, 0, 0])
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_random.randomize()
	_next_arrival = first_warning
	for index in MAX_VEHICLES:
		var actor := ConstructionVehicle.new()
		actor.configure(self)
		vehicles.append(actor)
	_create_opening_thresholds()


func bind_participants(chairs: Array[Chair]) -> void:
	_chairs = chairs
	for actor in vehicles:
		actor.chairs = chairs


func spawn_pose(index: int, count: int) -> Transform2D:
	var angle := PI * 1.25 + TAU * index / maxi(count, 1)
	return Transform2D(angle - PI / 2, to_global(center + Vector2.from_angle(angle) * 405))


func difficulty() -> float:
	return clampf(_elapsed / maxf(escalation_seconds, 1), 0, 1)


## Intervals fall steeply at first, then level off near the minimum, like the trains.
func current_interval() -> float:
	var eased := 1.0 - pow(1.0 - difficulty(), 2.5)
	return lerpf(arrival_interval, minimum_interval, eased)


func tick_hazards(delta: float) -> void:
	if not round_running:
		return
	_elapsed += maxf(delta, 0)
	for actor in vehicles:
		actor.tick(delta)
	if _elapsed >= _next_arrival:
		# A busy roster retries shortly rather than accumulating a backlog.
		_next_arrival = (_elapsed + (current_interval() if _dispatch() else 0.25))


func _dispatch() -> bool:
	var available: ConstructionVehicle
	# Per lane: the heading in use, or 0 when free. A second digger may follow on a lane
	# only in the same direction, once the one ahead has left its warning phase.
	var heading := PackedInt32Array([0, 0, 0, 0])
	var loading := PackedInt32Array([0, 0, 0, 0])
	for actor in vehicles:
		if actor.phase == ConstructionVehicle.Phase.DORMANT:
			available = available if available != null else actor
		else:
			heading[actor.lane] = 1 if actor.forward else -1
			loading[actor.lane] += 1 if actor.phase == ConstructionVehicle.Phase.WARNING else 0
	if available == null:
		return false
	var open: Array[int] = []
	for lane in LANE_OFFSETS.size():
		if loading[lane] == 0:
			open.append(lane)
	if open.is_empty():
		return false
	var lane: int = open[_random.randi_range(0, open.size() - 1)]
	# Often aim at a player's row or column, but a good share of paths are pure chance.
	if _random.randf() < 0.55 and not _chairs.is_empty():
		var local := to_local(_target_point())
		var best_gap := INF
		for candidate in open:
			var line: float = center[1 if candidate < 2 else 0] + LANE_OFFSETS[candidate]
			var gap := absf(local[1 if candidate < 2 else 0] - line) + _random.randf() * 220.0
			if gap < best_gap:
				best_gap = gap
				lane = candidate
	var forward := _random.randf() < 0.5 if heading[lane] == 0 else heading[lane] > 0
	available.warn(lane, forward, lerpf(1000.0, 1500.0, difficulty()))
	_departures[lane] += 1
	_deployed += 1
	return true


func _target_point() -> Vector2:
	var living: Array[Chair] = []
	for chair in _chairs:
		if is_instance_valid(chair) and chair.active and not chair.falling:
			living.append(chair)
	if living.is_empty():
		return to_global(center)
	var chair := living[_deployed % living.size()]
	return chair.global_position + chair.linear_velocity * 0.25


## Lane endpoints are world-space wall-opening centres, matching navigation and sweeps.
func lane_endpoints(lane: int) -> PackedVector2Array:
	var along_x := lane < 2
	var midpoint := (
		center + (Vector2(0, LANE_OFFSETS[lane]) if along_x else Vector2(LANE_OFFSETS[lane], 0))
	)
	var reach := Vector2(half_size.x, 0) if along_x else Vector2(0, half_size.y)
	return PackedVector2Array([to_global(midpoint - reach), to_global(midpoint + reach)])


func wall_sections(side: int) -> Array[Rect2]:
	var base := super.wall_sections(side)[0]
	var horizontal := side % 2 == 0
	var gaps: Array[Vector2] = []
	for lane in LANE_OFFSETS.size():
		# Lanes that run along Y open the horizontal walls, and vice versa.
		if (lane >= 2) != horizontal:
			continue
		var middle: float = (center.x if horizontal else center.y) + LANE_OFFSETS[lane]
		gaps.append(Vector2(middle - WALL_CUT * 0.5, middle + WALL_CUT * 0.5))
	gaps.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	var sections: Array[Rect2] = []
	var cursor := base.position.x if horizontal else base.position.y
	var finish := base.end.x if horizontal else base.end.y
	for gap in gaps + [Vector2(finish, finish)]:
		if gap.x > cursor:
			sections.append(_wall_piece(base, horizontal, cursor, gap.x))
		cursor = maxf(cursor, gap.y)
	return sections


func _wall_piece(base: Rect2, horizontal: bool, from: float, to: float) -> Rect2:
	if horizontal:
		return Rect2(from, base.position.y, to - from, base.size.y)
	return Rect2(base.position.x, from, base.size.x, to - from)


func wall_detail_slots() -> Array:
	# Windows, the door and the clock stay clear of the rear-wall openings.
	return [
		["WorkWindowA", 290.0, 1.95, &"window"],
		["WorkWindowB", 440.0, 1.95, &"window"],
		["OfficeDoor", 960.0, 0.0, &"door"],
		["OfficeClock", 1190.0, 2.18, &"clock"]
	]


func wall_height(side: int) -> float:
	return 2.8 if side == 2 else 0.55


func stop_round() -> void:
	super.stop_round()
	for actor in vehicles:
		actor.stop()


func create_presentation(parent: Node3D, units_per_pixel: float) -> void:
	super.create_presentation(parent, units_per_pixel)
	_create_rubble(parent, units_per_pixel)
	var template: ConstructionVehicleModel
	for actor in vehicles:
		var model := actor.create_presentation(parent, units_per_pixel, template)
		if template == null:
			template = model


func set_render_warmup(enabled: bool) -> void:
	for actor in vehicles:
		actor.set_render_warmup(enabled)


func is_safe(world_point: Vector2, margin: float = 0.0) -> bool:
	if not super.is_safe(world_point, margin):
		return false
	for actor in vehicles:
		if actor.threatens(world_point, margin):
			return false
	return true


func is_path_safe(from: Vector2, destination: Vector2, margin: float = 0.0) -> bool:
	for step in range(1, 5):
		if not is_safe(from.lerp(destination, step / 4.0), margin):
			return false
	return true


func safe_target(world_point: Vector2, margin: float = 90.0) -> Vector2:
	var point := super.safe_target(world_point, margin)
	for actor in vehicles:
		if not actor.threatens(point, margin):
			continue
		var candidate := super.safe_target(actor.avoidance_target(point, margin), margin)
		# A lane beside a wall has no outer refuge: retry towards the room interior.
		if actor.threatens(candidate, margin):
			candidate = super.safe_target(actor.avoidance_target(point, margin, true), margin)
		point = candidate
	return point


func _create_opening_thresholds() -> void:
	# Chairs bounce at the openings like at any wall; only diggers pass through them.
	for lane in LANE_OFFSETS.size():
		for point in lane_endpoints(lane):
			var body := StaticBody2D.new()
			body.name = "OpeningBarrier"
			body.position = to_local(point)
			body.collision_layer = 1
			body.collision_mask = 3
			body.physics_material_override = PhysicsMaterial.new()
			body.physics_material_override.bounce = 0.75
			body.physics_material_override.friction = 0.05
			var collision := CollisionShape2D.new()
			collision.shape = RectangleShape2D.new()
			collision.shape.size = Vector2(24, WALL_CUT) if lane < 2 else Vector2(WALL_CUT, 24)
			body.add_child(collision)
			add_child(body)


func _create_rubble(parent: Node3D, units: float) -> void:
	var openings := Node3D.new()
	openings.name = "WallOpenings"
	parent.add_child(openings)
	var plaster := ModelGeometry.material(Color("c8bf92"), 0, 0.9)
	var brick := ModelGeometry.material(Color("8a5a48"), 0, 0.9)
	var black := ModelGeometry.material(Color.BLACK)
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var seed := 0
	for lane in LANE_OFFSETS.size():
		var ends := lane_endpoints(lane)
		for end in 2:
			var direction := (ends[1 - end] - ends[end]).normalized()
			var across := direction.orthogonal()
			var base := ends[end]
			var side := (3 if end == 0 else 1) if lane < 2 else (2 if end == 0 else 0)
			var height := wall_height(side)
			var along_x := lane < 2
			# A black backing fills the cut, so the hole reads as a clean opening.
			var back: Vector2 = (base - direction * 15) * units
			ModelGeometry.instance(
				openings,
				_box(
					(
						Vector3(0.05, height, WALL_CUT * units)
						if along_x
						else Vector3(WALL_CUT * units, height, 0.05)
					)
				),
				Vector3(back.x, height * 0.5, back.y),
				black
			)
			# Ragged courses of broken wall step into the cut along both jambs.
			var courses := clampi(int(height / 0.45) + 1, 2, 6)
			for jamb in [-1.0, 1.0]:
				for course in courses:
					seed += 1
					var depth := 6.0 + fposmod(seed * 17.3, 28.0)
					var piece_height := height / courses
					var point: Vector2 = (
						(base + across * jamb * (WALL_CUT * 0.5 - depth * 0.5)) * units
					)
					var size := (
						Vector3(0.55, piece_height, depth * units)
						if along_x
						else Vector3(depth * units, piece_height, 0.55)
					)
					ModelGeometry.instance(
						openings,
						_box(size),
						Vector3(point.x, piece_height * (course + 0.5), point.y),
						brick if (seed % 3 == 0) else plaster
					)
			# Fallen rubble in front of the opening.
			for chunk in 7:
				seed += 1
				var along := 12.0 + fposmod(seed * 37.0, 90.0)
				var lateral := (fposmod(seed * 0.37, 1.0) - 0.5) * (WALL_CUT + 60)
				var point: Vector2 = (base + direction * along + across * lateral) * units
				var size := Vector3(
					0.22 + fposmod(seed * 0.173, 0.3),
					0.12 + fposmod(seed * 0.291, 0.22),
					0.2 + fposmod(seed * 0.117, 0.3)
				)
				var piece := ModelGeometry.cushion(
					openings,
					Vector3(point.x, size.y * 0.5, point.y),
					size,
					0.04,
					brick if chunk % 3 == 0 else plaster
				)
				piece.rotation.y = seed * 0.9
	StaticModelBatcher.batch(openings)


func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh
