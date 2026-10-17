class_name TrainingTrain
extends RefCounted
## A bounded, reusable crossing. Sweeps relative chair motion to prevent tunnelling.
## The stage owns timing; this actor requests eliminations through the shared contract.

enum Phase { COOLDOWN, WARNING, CROSSING, WAITING }

const WIDTH := 112.0

var width := WIDTH
var length := 1000.0
var warning_seconds := 1.8
var chairs: Array[Chair] = []
var phase := Phase.COOLDOWN
var phase_age := 0.0
var lane := -1
var departure_id := -1
var position := Vector2.ZERO
var direction := Vector2.RIGHT
var _remaining := 0.0
var _stage: OfficeStage
var _start := Vector2.ZERO
var _finish := Vector2.ZERO
var _hit_seats: Dictionary = {}
var _hit_props: Dictionary = {}
var _model: TrainingTrainModel
var _units := 1.0 / RenderStyle.PIXELS_PER_UNIT


func configure(stage: OfficeStage) -> void:
	_stage = stage


func warn(next_lane: int, forward: bool) -> void:
	lane = next_lane
	var ends: PackedVector2Array = _stage.lane_endpoints(lane)
	_start = ends[0 if forward else 1]
	_finish = ends[1 if forward else 0]
	direction = (_finish - _start).normalized()
	position = _start - direction * (length * 0.5 + 20)
	phase = Phase.WARNING
	phase_age = 0
	_remaining = warning_seconds
	_hit_seats.clear()
	_hit_props.clear()
	_sync_model()


func tick(delta: float) -> void:
	if not _stage.round_running or phase == Phase.COOLDOWN:
		return
	phase_age += delta
	_remaining -= delta
	if phase == Phase.WARNING and _remaining <= 0:
		phase = Phase.WAITING
	elif phase == Phase.CROSSING:
		var previous := position
		position += direction * lerpf(1250, 1650, _stage.difficulty()) * delta
		_sweep_chairs(previous, delta)
		_sweep_props(previous)
		if (position - _finish).dot(direction) > length * 0.5 + 20:
			phase = Phase.COOLDOWN
			phase_age = 0
			_remaining = 0.0
	_sync_model()


func begin_crossing() -> void:
	phase = Phase.CROSSING
	phase_age = 0
	_sync_model()


func threatens(point: Vector2, margin: float = 0.0) -> bool:
	if not _stage or not _stage.round_running or phase == Phase.COOLDOWN:
		return false
	var lateral := absf((point - _start).cross(direction))
	if lateral >= width * 0.5 + 24 + margin * 0.35:
		return false
	# Once the tail has passed, the cleared track is usable immediately.
	return (
		phase in [Phase.WARNING, Phase.WAITING]
		or (point - position).dot(direction) > -length * 0.5 - 50
	)


func avoidance_target(point: Vector2, margin: float, reverse: bool = false) -> Vector2:
	var across := direction.orthogonal()
	var offset := (point - _start).dot(across)
	var side := 1.0 if offset >= 0 else -1.0
	if reverse:
		side = -side
	return point + across * (side * (width * 0.5 + 60 + margin * 0.35) - offset)


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
		# Relative travel catches a moving chair even if both endpoints miss the train.
		var from := chair.global_position - chair.linear_velocity * delta - previous
		var to := chair.global_position - position
		if not _intersects_envelope(from, to, radius):
			continue
		_hit_seats[chair.seat] = true
		var planar := direction * 2450 / RenderStyle.PIXELS_PER_UNIT
		chair.set_knockout_launch(
			Vector3(planar.x, 16, planar.y), Vector3(direction.y, 0.4, -direction.x) * 10
		)
		_stage.elimination_requested.emit(chair.seat, &"train")


func _sweep_props(previous: Vector2) -> void:
	for prop in _stage.get_node("Furniture").get_children():
		if (
			not prop is OfficeProp
			or not prop.is_movable()
			or prop.collision_layer == 0
			or _hit_props.has(prop.get_instance_id())
		):
			continue
		if _intersects_envelope(
			prop.global_position - previous, prop.global_position - position, 35
		):
			_hit_props[prop.get_instance_id()] = true
			var planar := direction * 2450 / RenderStyle.PIXELS_PER_UNIT
			prop.launch(
				Vector3(planar.x, 16, planar.y), Vector3(direction.y, 0.4, -direction.x) * 10
			)


func _intersects_envelope(from: Vector2, to: Vector2, radius: float) -> bool:
	var across := direction.orthogonal()
	var a := Vector2(from.dot(direction), from.dot(across))
	var b := Vector2(to.dot(direction), to.dot(across))
	var extent := Vector2(length * 0.5, width * 0.5) + Vector2.ONE * radius
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


func stop() -> void:
	if is_instance_valid(_model):
		_model.collision_layer = 0
		_model.collision_mask = 0


func create_presentation(
	parent: Node3D, units: float, template: TrainingTrainModel = null
) -> TrainingTrainModel:
	_units = units
	# Duplicate nodes, not immutable mesh/material resources, for the pooled models.
	_model = (
		template.duplicate() as TrainingTrainModel if template != null else TrainingTrainModel.new()
	)
	_model.name = "TrainingTrain"
	parent.add_child(_model)
	if template == null:
		_model.build(width * units, length * units, _stage, units)
	_sync_model()
	return _model


func set_render_warmup(enabled: bool) -> void:
	if not is_instance_valid(_model):
		return
	if enabled:
		_model.position = Vector3(_stage.center.x * _units, 0, _stage.center.y * _units)
		_model.show()
	else:
		_sync_model()


func _sync_model() -> void:
	if not is_instance_valid(_model):
		return
	_model.visible = phase == Phase.CROSSING
	_model.position = Vector3(position.x * _units, 0, position.y * _units)
	_model.rotation.y = -direction.angle() - PI / 2
	_model.collision_layer = 1 if _stage.round_running and phase == Phase.CROSSING else 0
	_model.collision_mask = _model.collision_layer
