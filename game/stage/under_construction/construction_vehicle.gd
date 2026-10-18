class_name ConstructionVehicle
extends LaneVehicle
## A reusable digger that drives a fixed lane between two wall openings, flattening
## furniture. The stage owns dispatch timing.

enum Phase { DORMANT, WARNING, CHARGING }

const WIDTH := 150.0
const LENGTH := 260.0

var phase := Phase.DORMANT
var forward := true
var warning_seconds := 1.8
var speed := 1000.0
var _remaining := 0.0
var _model: ConstructionVehicleModel
var _lane: MeshInstance3D


func _init() -> void:
	width = WIDTH
	length = LENGTH
	_elimination_reason = &"construction_vehicle"


func configure(stage: UnderConstructionStage) -> void:
	_stage = stage


func warn(next_lane: int, going_forward: bool, drive_speed: float) -> void:
	forward = going_forward
	_aim(next_lane, (_stage as UnderConstructionStage).lane_endpoints(next_lane), going_forward)
	speed = drive_speed
	phase = Phase.WARNING
	_remaining = warning_seconds
	_sync_presentation()


func tick(delta: float) -> void:
	if not _stage.round_running or phase == Phase.DORMANT:
		return
	_remaining -= delta
	if phase == Phase.WARNING:
		if _remaining <= 0:
			phase = Phase.CHARGING
	elif _advance(delta, speed):
		phase = Phase.DORMANT
	_sync_presentation()


func threatens(point: Vector2, margin: float = 0.0) -> bool:
	if not _stage or not _stage.round_running or phase == Phase.DORMANT:
		return false
	if not _in_lane(point, margin):
		return false
	return phase == Phase.WARNING or _ahead_of_tail(point)


func stop() -> void:
	if is_instance_valid(_lane):
		_lane.hide()


func _strike(prop: OfficeProp) -> void:
	prop.smash(_stage, _launch_velocity() * 0.6, _launch_spin())


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
	var warning := ModelGeometry.warning_material()
	_lane = ModelGeometry.box(parent, Vector3.ZERO, Vector3(1, 0.008, WIDTH * units), warning)
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
