class_name TrainingTrain
extends LaneVehicle
## A bounded, reusable crossing. The stage owns timing and releases each warned train.

enum Phase { COOLDOWN, WARNING, CROSSING, WAITING }

const WIDTH := 112.0

var warning_seconds := 1.8
var phase := Phase.COOLDOWN
var phase_age := 0.0
var departure_id := -1
var _remaining := 0.0
var _model: TrainingTrainModel


func _init() -> void:
	width = WIDTH
	length = 1000.0
	_elimination_reason = &"train"


func configure(stage: OfficeStage) -> void:
	_stage = stage


func warn(next_lane: int, forward: bool) -> void:
	_aim(next_lane, _stage.lane_endpoints(next_lane), forward)
	phase = Phase.WARNING
	phase_age = 0
	_remaining = warning_seconds
	_sync_model()


func tick(delta: float) -> void:
	if not _stage.round_running or phase == Phase.COOLDOWN:
		return
	phase_age += delta
	_remaining -= delta
	if phase == Phase.WARNING and _remaining <= 0:
		phase = Phase.WAITING
	elif phase == Phase.CROSSING:
		if _advance(delta, lerpf(1250, 1650, _stage.difficulty())):
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
	if not _in_lane(point, margin):
		return false
	return phase in [Phase.WARNING, Phase.WAITING] or _ahead_of_tail(point)


func _can_strike(prop: OfficeProp) -> bool:
	return prop.is_movable()


func _strike(prop: OfficeProp) -> void:
	prop.launch(_launch_velocity(), _launch_spin())
	_report_strike(prop, false, _launch_velocity(), _launch_spin())


## Host: [phase, lane, forward, x, y, phase age], world pixels.
func write_net_state(state: PackedFloat32Array, offset: int) -> void:
	state[offset] = phase
	state[offset + 1] = lane
	state[offset + 2] = 1.0 if heading_forward else 0.0
	state[offset + 3] = position.x
	state[offset + 4] = position.y
	state[offset + 5] = phase_age


## Mirror: show the host train's lane, phase and position.
func apply_mirror(state: PackedFloat32Array, offset: int) -> void:
	var next_lane := int(state[offset + 1])
	var forward := state[offset + 2] > 0.5
	if _mirror_lane_changed(next_lane, forward):
		_mirror_lane(next_lane, _stage.lane_endpoints(next_lane), forward)
	phase = int(state[offset]) as Phase
	position = Vector2(state[offset + 3], state[offset + 4])
	phase_age = state[offset + 5]
	_sync_model()


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
	_model.collision_layer = (
		1 if _stage.round_running and phase == Phase.CROSSING and not mirror else 0
	)
	_model.collision_mask = _model.collision_layer
