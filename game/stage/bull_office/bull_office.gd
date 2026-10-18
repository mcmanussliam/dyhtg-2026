@tool
extends OfficeStage
## First bull starts centrally; later bulls enter through the shared saloon doorway.
## Arrivals use the live round clock, with no spawn timers outliving the scene.

const NET_STRIDE := 5

@export_range(3.0, 60.0, 1.0) var arrival_interval := 14.0
@export_range(1, 12, 1) var max_bulls := 6

var bulls: Array[OfficeBull] = []
var bull: OfficeBull:
	get:
		return bulls[0] if not bulls.is_empty() else null

var _chairs: Array[Chair] = []
var _elapsed := 0.0
var _next_arrival := 14.0
var _world: Node3D
var _units := 1.0 / RenderStyle.PIXELS_PER_UNIT
var _door: SaloonDoor


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_next_arrival = arrival_interval
	_add_bull(true)


func bind_participants(chairs: Array[Chair]) -> void:
	_chairs = chairs
	for actor in bulls:
		actor.chairs = chairs


func spawn_pose(index: int, count: int) -> Transform2D:
	# Keep players out of the entrance lane, with clear furniture-free starts.
	var angle := PI * 1.25 + TAU * index / maxi(count, 1)
	return Transform2D(angle - PI / 2, to_global(center + Vector2.from_angle(angle) * 405))


func is_spawn_safe(world_point: Vector2, clearance: float) -> bool:
	var point := to_local(world_point) - center
	return (
		super.is_spawn_safe(world_point, clearance)
		and (absf(point.x) > 80 + clearance or point.y > clearance + 80)
	)


func tick_hazards(delta: float) -> void:
	if not round_running:
		return
	if net_mirror:
		for actor in bulls:
			actor.mirror_tick(delta)
		if is_instance_valid(_door):
			_door.tick(delta)
		return
	_elapsed += delta
	for actor in bulls:
		actor.tick(delta)
	if _elapsed >= _next_arrival and bulls.size() < max_bulls and _entrance_clear():
		_add_bull()
		_next_arrival = _elapsed + arrival_interval
	if is_instance_valid(_door):
		_door.tick(delta)


func set_net_mirror(enabled: bool) -> void:
	super.set_net_mirror(enabled)
	if enabled:
		for actor in bulls:
			actor.collision_layer = 0
			actor.collision_mask = 0


## Host: five floats per bull, in arrival order. Clients add arrivals on demand.
func net_state() -> Variant:
	# A fresh array: packed arrays are shared by reference with the snapshot.
	var state := PackedFloat32Array()
	state.resize(bulls.size() * NET_STRIDE)
	for index in bulls.size():
		bulls[index].write_net_state(state, index * NET_STRIDE)
	return state


func apply_net_state(state: Variant) -> void:
	if not state is PackedFloat32Array:
		return
	var count := mini(state.size() / NET_STRIDE, max_bulls)
	while bulls.size() < count:
		_add_bull()
	for index in count:
		var offset := index * NET_STRIDE
		bulls[index].apply_mirror(
			Vector2(state[offset], state[offset + 1]),
			state[offset + 2],
			int(state[offset + 3]),
			state[offset + 4]
		)


func _entrance_clear() -> bool:
	var threshold := to_global(Vector2(center.x, center.y - half_size.y + 160))
	for actor in bulls:
		if (
			actor.phase == OfficeBull.Phase.ENTERING
			or actor.global_position.distance_to(threshold) < 190
		):
			return false
	return true


func _add_bull(first: bool = false) -> void:
	var actor := OfficeBull.new()
	actor.name = "Bull%d" % (bulls.size() + 1)
	add_child(actor)
	actor.configure(self)
	actor.chairs = _chairs
	var doorway := Vector2(center.x, center.y - half_size.y)
	if first:
		actor.global_position = to_global(center)
		actor.rotation = PI / 2
	else:
		actor.begin_entry(
			to_global(doorway - Vector2(0, 120)), to_global(doorway + Vector2(0, 160))
		)
	bulls.append(actor)
	if is_instance_valid(_world):
		actor.create_presentation(_world, _units)
	if not first and is_instance_valid(_door):
		_door.open_for(1.7)


func stop_round() -> void:
	super.stop_round()
	for actor in bulls:
		actor.stop()


func set_render_warmup(enabled: bool) -> void:
	for actor in bulls:
		actor.set_render_warmup(enabled)


func create_presentation(parent: Node3D, units_per_pixel: float) -> void:
	_world = parent
	_units = units_per_pixel
	super.create_presentation(parent, units_per_pixel)
	for actor in bulls:
		actor.create_presentation(parent, units_per_pixel)


func _create_wall_details(parent: Node3D, units: float) -> void:
	# Replace only this map's office door; the shared room and pit retain their door.
	super._create_wall_details(parent, units)
	var old := parent.get_node("OfficeDoor")
	parent.remove_child(old)
	old.queue_free()
	_door = SaloonDoor.new()
	_door.name = "SaloonDoor"
	var point := to_global(Vector2(center.x, center.y - half_size.y)) * units
	_door.position = Vector3(point.x, 0, point.y + 0.29)
	parent.add_child(_door)
	_door.build()


func is_safe(world_point: Vector2, margin: float = 0.0) -> bool:
	if not super.is_safe(world_point, margin):
		return false
	for actor in bulls:
		if actor.threatens(world_point, margin):
			return false
	return true


func safe_target(world_point: Vector2, margin: float = 90.0) -> Vector2:
	var point := super.safe_target(world_point, margin)
	for actor in bulls:
		if actor.threatens(point, 60):
			point = super.safe_target(actor.avoidance_target(point), margin)
	return point
