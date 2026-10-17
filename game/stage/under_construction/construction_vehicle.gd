class_name ConstructionVehicle
extends RefCounted
## A reusable digger that drives a fixed lane between two wall openings.
## The stage owns timing; this actor sweeps chairs and furniture along its envelope.

enum Phase { DORMANT, WARNING, CHARGING }

const WIDTH := 150.0
const LENGTH := 260.0

var chairs: Array[Chair] = []
var phase := Phase.DORMANT
var lane := -1
var forward := true
var warning_seconds := 1.8
var position := Vector2.ZERO
var direction := Vector2.RIGHT
var speed := 1000.0
var _stage: UnderConstructionStage
var _remaining := 0.0
var _start := Vector2.ZERO
var _finish := Vector2.ZERO
var _hit_seats: Dictionary = {}
var _hit_props: Dictionary = {}
var _model: ConstructionVehicleModel
var _lane: MeshInstance3D
var _units := 1.0 / RenderStyle.PIXELS_PER_UNIT


func configure(stage: UnderConstructionStage) -> void:
	_stage = stage


func warn(next_lane: int, going_forward: bool, drive_speed: float) -> void:
	lane = next_lane
	forward = going_forward
	var ends := _stage.lane_endpoints(lane)
	_start = ends[0 if going_forward else 1]
	_finish = ends[1 if going_forward else 0]
	direction = (_finish - _start).normalized()
	position = _start - direction * (LENGTH * 0.5 + 20)
	speed = drive_speed
	phase = Phase.WARNING
	_remaining = warning_seconds
	_hit_seats.clear()
	_hit_props.clear()
	_sync_presentation()


func tick(delta: float) -> void:
	if not _stage.round_running or phase == Phase.DORMANT:
		return
	_remaining -= delta
	if phase == Phase.WARNING:
		if _remaining <= 0:
			phase = Phase.CHARGING
	else:
		var previous := position
		position += direction * speed * delta
		_sweep_chairs(previous, delta)
		_sweep_props(previous)
		if (position - _finish).dot(direction) > LENGTH * 0.5 + 20:
			phase = Phase.DORMANT
	_sync_presentation()


func threatens(point: Vector2, margin: float = 0.0) -> bool:
	if not _stage or not _stage.round_running or phase == Phase.DORMANT:
		return false
	if absf((point - _start).cross(direction)) >= WIDTH * 0.5 + 24 + margin * 0.35:
		return false
	# Once the tail has passed, the cleared lane is usable immediately.
	return phase == Phase.WARNING or (point - position).dot(direction) > -LENGTH * 0.5 - 50


func avoidance_target(point: Vector2, margin: float, reverse: bool = false) -> Vector2:
	var across := direction.orthogonal()
	var offset := (point - _start).dot(across)
	var side := 1.0 if offset >= 0 else -1.0
	if reverse:
		side = -side
	return point + across * (side * (WIDTH * 0.5 + 60 + margin * 0.35) - offset)


func stop() -> void:
	if is_instance_valid(_lane):
		_lane.hide()


func _sweep_chairs(previous: Vector2, delta: float) -> void:
	for chair in chairs:
		if (
			not is_instance_valid(chair)
			or not chair.active
			or chair.falling
			or _hit_seats.has(chair.seat)
		):
			continue
		var radius := 25 * chair.size_scale
		# Relative travel catches a moving chair even if both endpoints miss the digger.
		var from := chair.global_position - chair.linear_velocity * delta - previous
		var to := chair.global_position - position
		if not _intersects(from, to, radius):
			continue
		_hit_seats[chair.seat] = true
		var planar := direction * 2450 / RenderStyle.PIXELS_PER_UNIT
		chair.set_knockout_launch(
			Vector3(planar.x, 16, planar.y), Vector3(direction.y, 0.4, -direction.x) * 10
		)
		_stage.elimination_requested.emit(chair.seat, &"construction_vehicle")


func _sweep_props(previous: Vector2) -> void:
	for prop in _stage.get_node("Furniture").get_children():
		if (
			not prop is OfficeProp
			or prop.collision_layer == 0
			or _hit_props.has(prop.get_instance_id())
		):
			continue
		if _intersects(prop.global_position - previous, prop.global_position - position, 35):
			_hit_props[prop.get_instance_id()] = true
			var planar := direction * 2450 / RenderStyle.PIXELS_PER_UNIT
			prop.smash(
				_stage,
				Vector3(planar.x, 16, planar.y) * 0.6,
				Vector3(direction.y, 0.4, -direction.x) * 10
			)


## Does the relative segment from..to touch the digger's oriented rectangle?
func _intersects(from: Vector2, to: Vector2, radius: float) -> bool:
	var across := direction.orthogonal()
	var a := Vector2(from.dot(direction), from.dot(across))
	var b := Vector2(to.dot(direction), to.dot(across))
	var extent := Vector2(LENGTH * 0.5, WIDTH * 0.5) + Vector2.ONE * radius
	if Rect2(-extent, extent * 2).has_point(a) or Rect2(-extent, extent * 2).has_point(b):
		return true
	var low := 0.0
	var high := 1.0
	var travel := b - a
	for axis in 2:
		if absf(travel[axis]) < 0.0001:
			if absf(a[axis]) > extent[axis]:
				return false
			continue
		var entry := (-extent[axis] - a[axis]) / travel[axis]
		var exit := (extent[axis] - a[axis]) / travel[axis]
		low = maxf(low, minf(entry, exit))
		high = minf(high, maxf(entry, exit))
		if low > high:
			return false
	return true


func create_presentation(
	parent: Node3D, units: float, template: ConstructionVehicleModel = null
) -> ConstructionVehicleModel:
	_units = units
	# Duplicate nodes, not immutable mesh/material resources, for the pooled models.
	_model = (
		template.duplicate() as ConstructionVehicleModel
		if template != null
		else ConstructionVehicleModel.new()
	)
	_model.name = "ConstructionVehicle"
	parent.add_child(_model)
	if template == null:
		_model.build(WIDTH * units, LENGTH * units, _stage, units)
	# One flat, transparent path marker, shared in style with the bull's charge lane.
	var warning := ModelGeometry.material(Color(0.95, 0.32, 0.15, 0.30))
	warning.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warning.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1, 0.008, WIDTH * units)
	_lane = ModelGeometry.instance(parent, mesh, Vector3.ZERO, warning)
	_lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lane.hide()
	_sync_presentation()
	return _model


func set_render_warmup(enabled: bool) -> void:
	if not is_instance_valid(_model):
		return
	if enabled:
		_model.position = Vector3(_stage.center.x * _units, 0, _stage.center.y * _units)
		_model.show()
		_lane.show()
	else:
		_sync_presentation()


func _sync_presentation() -> void:
	if not is_instance_valid(_model):
		return
	_model.visible = phase == Phase.CHARGING
	_model.position = Vector3(position.x * _units, 0, position.y * _units)
	_model.rotation.y = -direction.angle() - PI / 2
	_lane.visible = phase != Phase.DORMANT and _stage.round_running
	if _lane.visible:
		var middle := (_start + _finish) * 0.5 * _units
		_lane.position = Vector3(middle.x, 0.015, middle.y)
		_lane.rotation.y = -direction.angle()
		_lane.scale.x = _start.distance_to(_finish) * _units
