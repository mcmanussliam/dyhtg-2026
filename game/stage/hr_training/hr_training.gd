@tool
extends OfficeStage
## Three horizontal routes sweep the rear wall, middle and front wall.
## Independent arrivals overlap full warnings and crossings across a fixed actor pool.
## All timing uses live round delta; scene replacement resets the complete schedule.

const TRACK_OFFSETS := [-562.0, 0.0, 562.0]
const PORTAL_WIDTH := 152.0
const CROSSING_ORDER := [0, 2, 1]
const MAX_TRAINS := 9  # Three per track: crossing, waiting and warning.

@export_range(0.2, 10.0, 0.1) var initial_interval := 1.5
@export_range(0.0, 10.0, 0.01) var minimum_interval := 0.02
@export_range(1.0, 300.0, 1.0) var escalation_seconds := 30.0

var trains: Array[TrainingTrain] = []
var _next_arrival := 3.5
var _next_track := 0
var _lane_departures := PackedInt32Array([0, 0, 0])
var _elapsed := 0.0
var _crossings := 0
var _signals: Array[MeshInstance3D] = []
var _signal_on: StandardMaterial3D
var _signal_off: StandardMaterial3D


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	for index in MAX_TRAINS:
		var actor := TrainingTrain.new()
		actor.configure(self)
		trains.append(actor)
	_create_player_thresholds()


func bind_participants(chairs: Array[Chair]) -> void:
	for actor in trains:
		actor.chairs = chairs


func spawn_pose(index: int, _count: int) -> Transform2D:
	# All seats begin between the tracks, with clear furniture-free footprints.
	var points := [
		Vector2(140, 80),
		Vector2(970, 650),
		Vector2(970, 80),
		Vector2(140, 650),
		Vector2(140, 235),
		Vector2(1030, 805),
		Vector2(970, 235),
		Vector2(180, 790),
		Vector2(980, -30),
		Vector2(1040, 550)
	]
	var point: Vector2 = points[index % points.size()]
	return Transform2D((center - point).angle() + PI, to_global(point))


func is_spawn_safe(world_point: Vector2, clearance: float) -> bool:
	if not super.is_spawn_safe(world_point, clearance):
		return false
	var point := to_local(world_point) - center
	for offset: float in TRACK_OFFSETS:
		if absf(point.y - offset) < TrainingTrain.WIDTH * 0.5 + clearance:
			return false
	return true


func crossing_interval() -> float:
	return lerpf(initial_interval, minf(minimum_interval, initial_interval), difficulty())


func difficulty() -> float:
	return clampf(_elapsed / maxf(escalation_seconds, 1), 0, 1)


func tick_hazards(delta: float) -> void:
	if not round_running:
		return
	_elapsed += delta
	for actor in trains:
		actor.tick(delta)
	for actor in trains:
		if actor.phase == TrainingTrain.Phase.WAITING and _entry_clear(actor):
			actor.begin_crossing()
	_next_arrival -= delta
	if _next_arrival <= 0:
		# One admission per physics tick; blocked lanes never accumulate a backlog.
		_next_arrival = crossing_interval() if _schedule_train() else 0.0
	_update_signals()


func _schedule_train() -> bool:
	for offset in CROSSING_ORDER.size():
		var order_index := (_next_track + offset) % CROSSING_ORDER.size()
		var lane: int = CROSSING_ORDER[order_index]
		var occupants := 0
		var available: TrainingTrain
		for actor in trains:
			if actor.phase == TrainingTrain.Phase.COOLDOWN:
				if available == null:
					available = actor
			elif actor.lane == lane:
				occupants += 1
		if occupants >= 3 or available == null:
			continue
		available.departure_id = _crossings
		available.warn(lane, _lane_departures[lane] % 2 == 0)
		_lane_departures[lane] += 1
		_crossings += 1
		_next_track = (order_index + 1) % CROSSING_ORDER.size()
		return true
	return false


func _entry_clear(candidate: TrainingTrain) -> bool:
	for other in trains:
		if other == candidate or other.lane != candidate.lane:
			continue
		if (
			other.phase == TrainingTrain.Phase.WAITING
			and other.departure_id < candidate.departure_id
		):
			return false
		if other.phase != TrainingTrain.Phase.CROSSING:
			continue
		# Opposing trains must clear the room; following trains need tail clearance.
		if other.direction.dot(candidate.direction) < 0:
			return false
		var headway := (other.length + candidate.length) * 0.5 + 80
		if (other.position - candidate.position).dot(candidate.direction) < headway:
			return false
	return true


func stop_round() -> void:
	super.stop_round()
	for actor in trains:
		actor.stop()
	_update_signals()


func is_safe(world_point: Vector2, margin: float = 0.0) -> bool:
	if not super.is_safe(world_point, margin):
		return false
	for actor in trains:
		if actor.threatens(world_point, margin):
			return false
	return true


func safe_target(world_point: Vector2, margin: float = 90.0) -> Vector2:
	var point := super.safe_target(world_point, margin)
	for actor in trains:
		if not actor.threatens(point, margin):
			continue
		var escape := actor.avoidance_target(point, margin)
		var candidate := super.safe_target(escape, margin)
		# Wall-side lanes have no outer refuge: retry towards the room interior.
		if actor.threatens(candidate, margin):
			candidate = super.safe_target(actor.avoidance_target(point, margin, true), margin)
		point = candidate
	return point


## Lane endpoints are in world space, matching navigation and swept impact queries.
func lane_endpoints(lane: int) -> PackedVector2Array:
	var midpoint := center + Vector2(0, TRACK_OFFSETS[lane])
	return PackedVector2Array(
		[
			to_global(midpoint - Vector2(half_size.x, 0)),
			to_global(midpoint + Vector2(half_size.x, 0))
		]
	)


func wall_sections(side: int) -> Array[Rect2]:
	if side % 2 == 0:
		return super.wall_sections(side)
	var fixed := half_size.x * (1 if side == 1 else -1)
	var sections: Array[Rect2] = []
	var opening_width := PORTAL_WIDTH - 0.4 * RenderStyle.PIXELS_PER_UNIT
	var start := -half_size.y
	for edge in 4:
		var finish: float = TRACK_OFFSETS[edge] - opening_width * 0.5 if edge < 3 else half_size.y
		var location := center + Vector2(fixed, (start + finish) * 0.5)
		var size := Vector2(24, finish - start)
		sections.append(Rect2(location - size * 0.5, size))
		if edge < 3:
			start = TRACK_OFFSETS[edge] + opening_width * 0.5
	return sections


func wall_height(side: int) -> float:
	return 3.9 if side == 2 else 0.55


func create_presentation(parent: Node3D, units_per_pixel: float) -> void:
	super.create_presentation(parent, units_per_pixel)
	var tracks := TrainingTracks.new()
	parent.add_child(tracks)
	tracks.build(self, units_per_pixel)
	var template: TrainingTrainModel
	for actor in trains:
		var model := actor.create_presentation(parent, units_per_pixel, template)
		if template == null:
			template = model
	_create_native_thresholds(parent, units_per_pixel)
	_update_signals()


func set_render_warmup(enabled: bool) -> void:
	for actor in trains:
		actor.set_render_warmup(enabled)
	if enabled:
		for signal_mesh in _signals:
			signal_mesh.material_override = _signal_on
	else:
		_update_signals()


func _create_wall_details(parent: Node3D, units: float) -> void:
	# The sealed rear wall keeps its office details; only side walls have portals.
	super._create_wall_details(parent, units)
	_signal_on = ModelGeometry.material(Color("ff2925"))
	_signal_on.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_signal_off = ModelGeometry.material(Color("481b20"))
	for lane in TRACK_OFFSETS.size():
		var endpoints := lane_endpoints(lane)
		for end in 2:
			var direction := (endpoints[1 - end] - endpoints[end]).normalized()
			var portal := TrainingTracks.portal(
				parent, endpoints[end], direction, units, PORTAL_WIDTH
			)
			_signals.append(portal)


func _create_carpet(
	parent: Node3D, units: float, _area: Rect2, colour: Color, label: String
) -> void:
	# Keep the shared shell's dressing hook, but move its two carpets off the rails.
	var area := Rect2(1190, 0, 80, 340) if label == "StorageCarpet" else Rect2(1030, 560, 240, 315)
	super._create_carpet(parent, units, area, colour, label)


func _update_signals() -> void:
	var warning_ages := PackedFloat64Array([-1, -1, -1])
	if round_running:
		for actor in trains:
			if actor.phase in [TrainingTrain.Phase.WARNING, TrainingTrain.Phase.WAITING]:
				warning_ages[actor.lane] = maxf(warning_ages[actor.lane], actor.phase_age)
	for index in _signals.size():
		var age := warning_ages[index / 2]
		var flashing := age >= 0 and fmod(age, 0.28) < 0.16
		_signals[index].material_override = _signal_on if flashing else _signal_off


func _create_player_thresholds() -> void:
	# Trains move on a scripted sweep, while chairs bounce at the room boundary.
	# Closed player thresholds prevent camping beyond the visible tunnel mouths.
	for lane in TRACK_OFFSETS.size():
		for point in lane_endpoints(lane):
			var body := StaticBody2D.new()
			body.name = "PlayerThreshold"
			body.position = to_local(point)
			body.collision_layer = 1
			body.collision_mask = 3
			body.physics_material_override = PhysicsMaterial.new()
			body.physics_material_override.bounce = 0.75
			body.physics_material_override.friction = 0.05
			var collision := CollisionShape2D.new()
			collision.shape = RectangleShape2D.new()
			collision.shape.size = Vector2(24, PORTAL_WIDTH)
			body.add_child(collision)
			add_child(body)


func _create_native_thresholds(parent: Node3D, units: float) -> void:
	# Native falling chairs/furniture see the same containment as live 2D bodies.
	var body := StaticBody3D.new()
	body.name = "PlayerThresholds"
	parent.add_child(body)
	for lane in TRACK_OFFSETS.size():
		for point in lane_endpoints(lane):
			var collision := CollisionShape3D.new()
			collision.shape = BoxShape3D.new()
			collision.shape.size = Vector3(24 * units, 3.9, PORTAL_WIDTH * units)
			collision.position = Vector3(point.x * units, 1.95, point.y * units)
			body.add_child(collision)
