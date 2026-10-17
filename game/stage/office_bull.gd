class_name OfficeBull
extends CharacterBody2D
## Explicit, physics-clock attack phases. Charges lock their heading before moving.

enum Phase { RECOVERY, WINDUP, CHARGE, STUNNED, ENTERING }

@export var windup_seconds := 1.1
@export var stun_seconds := 1.8
@export var recovery_seconds := 0.65
@export var charge_speed := 1000.0
@export var charge_acceleration := 2800.0
@export var knockout_speed := 2300.0  # Planar pixels per second.
@export var knockout_lift := 15.0  # Native 3D metres per second.
@export var knockout_tumble := 9.0  # Radians per second.

var chairs: Array[Chair] = []
var phase := Phase.RECOVERY
var target := Vector2.ZERO
var _stage: OfficeStage
var _remaining := 1.2
var _direction := Vector2.RIGHT
var _charge_age := 0.0
var _hit_seats: Dictionary = {}
var _random := RandomNumberGenerator.new()
var _model: BullModel
var _lane: MeshInstance3D
var _marker: MeshInstance3D
var _units := 1.0 / RenderStyle.PIXELS_PER_UNIT
var _time := 0.0
var _entry_destination := Vector2.ZERO


func _ready() -> void:
	collision_layer = 1
	collision_mask = 1
	var collision := CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 42
	shape.height = 144
	collision.shape = shape
	collision.rotation = PI / 2
	add_child(collision)
	_random.randomize()


func configure(stage: OfficeStage) -> void:
	_stage = stage


func tick(delta: float) -> void:
	if not _stage.round_running:
		return
	_time += delta
	_remaining -= delta
	match phase:
		Phase.ENTERING:
			_enter_room(delta)
		Phase.RECOVERY:
			if _remaining <= 0:
				_choose_target()
		Phase.WINDUP:
			rotation = rotate_toward(rotation, _direction.angle(), delta * 7.0)
			if _remaining <= 0:
				rotation = _direction.angle()
				phase = Phase.CHARGE
				_charge_age = 0
				_hit_seats.clear()
		Phase.CHARGE:
			_charge(delta)
		Phase.STUNNED:
			move_and_collide(velocity * delta)
			velocity = velocity.move_toward(Vector2.ZERO, 700 * delta)
			if _remaining <= 0:
				phase = Phase.RECOVERY
				_remaining = recovery_seconds
	_sync_presentation(delta)


func begin_entry(start: Vector2, destination: Vector2) -> void:
	global_position = start
	_entry_destination = destination
	_direction = (destination - start).normalized()
	rotation = _direction.angle()
	phase = Phase.ENTERING
	# The closed arena boundary remains solid for players; arrivals alone pass
	# through the animated doorway, and cannot kill or shove players at the threshold.
	collision_layer = 0
	collision_mask = 0
	velocity = Vector2.ZERO


func _enter_room(delta: float) -> void:
	var offset := _entry_destination - global_position
	velocity = offset.normalized() * 230
	move_and_collide(offset.limit_length(230 * delta))
	if global_position.distance_to(_entry_destination) < 0.1:
		phase = Phase.RECOVERY
		_remaining = 0.8
		velocity = Vector2.ZERO
		collision_layer = 1
		collision_mask = 1


func _choose_target() -> void:
	var alive: Array[Chair] = []
	for chair in chairs:
		if is_instance_valid(chair) and chair.active and not chair.falling:
			alive.append(chair)
	if not alive.is_empty() and _random.randf() < 0.8:
		var chosen := alive[_random.randi_range(0, alive.size() - 1)]
		target = _stage.safe_target(chosen.global_position + chosen.linear_velocity * 0.20, 70)
	else:
		target = _stage.safe_target(
			global_position + Vector2.from_angle(_random.randf_range(-PI, PI)) * 700, 70
		)
	_direction = (target - global_position).normalized()
	if _direction.length_squared() < 0.5:
		_direction = Vector2.from_angle(rotation + PI / 2)
		target = global_position + _direction * 350
	phase = Phase.WINDUP
	_remaining = windup_seconds
	velocity = Vector2.ZERO


func _charge(delta: float) -> void:
	_charge_age += delta
	velocity = velocity.move_toward(_direction * charge_speed, charge_acceleration * delta)
	var previous := global_position
	var collision := move_and_collide(velocity * delta)
	var hit_player := false
	# Sweep the horn/body envelope, bounded by the actual scenery collision travel.
	# This prevents high-speed tunnelling and never hits through a desk or wall.
	for chair in chairs:
		if (
			not is_instance_valid(chair)
			or not chair.active
			or chair.falling
			or _hit_seats.has(chair.seat)
		):
			continue
		var nearest := Geometry2D.get_closest_point_to_segment(
			chair.global_position, previous, global_position
		)
		if nearest.distance_to(chair.global_position) <= 66 + 23 * chair.size_scale:
			_hit_seats[chair.seat] = true
			var planar := (
				(_direction * knockout_speed + chair.linear_velocity * 0.20)
				/ RenderStyle.PIXELS_PER_UNIT
			)
			var roll := Vector3(_direction.y, 0, -_direction.x) * knockout_tumble
			roll.y = 3.5
			chair.set_knockout_launch(Vector3(planar.x, knockout_lift, planar.y), roll)
			_stage.elimination_requested.emit(chair.seat, &"bull")
			hit_player = true
	if collision != null:
		var obstacle := collision.get_collider()
		if obstacle is OfficeProp:
			obstacle.push(_direction * 600, collision.get_position() - obstacle.global_position)
	if collision != null or hit_player or _charge_age > 2.4:
		phase = Phase.STUNNED
		_remaining = stun_seconds
		velocity = -_direction * 110


func stop() -> void:
	velocity = Vector2.ZERO
	if is_instance_valid(_lane):
		_lane.hide()
		_marker.hide()


func create_presentation(parent: Node3D, units: float) -> void:
	_units = units
	_model = BullModel.new()
	parent.add_child(_model)
	_model.build()
	_model.scale = Vector3.ONE * 1.4
	var warning := ModelGeometry.material(Color(0.95, 0.32, 0.15, 0.30))
	warning.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warning.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var lane_mesh := BoxMesh.new()
	lane_mesh.size = Vector3(0.32, 0.008, 1)
	_lane = ModelGeometry.instance(parent, lane_mesh, Vector3.ZERO, warning)
	_lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring := TorusMesh.new()
	ring.inner_radius = 0.42
	ring.outer_radius = 0.50
	_marker = ModelGeometry.instance(parent, ring, Vector3.ZERO, warning)
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sync_presentation(0)


func _sync_presentation(delta: float) -> void:
	if not is_instance_valid(_model):
		return
	_model.position = Vector3(global_position.x, 0, global_position.y) * _units
	_model.rotation.y = PI / 2 - rotation
	_model.animate(
		delta,
		_time * 0.55 if phase == Phase.ENTERING else _time,
		phase in [Phase.CHARGE, Phase.ENTERING],
		phase == Phase.STUNNED,
		phase == Phase.WINDUP
	)
	var showing := phase == Phase.WINDUP and _stage.round_running
	_lane.visible = showing
	_marker.visible = showing
	if showing:
		var end := _stage.boundary_in_direction(global_position, _direction)
		var line := end - global_position
		var middle := (end + global_position) * 0.5 * _units
		_lane.position = Vector3(middle.x, 0.015, middle.y)
		_lane.rotation.y = PI / 2 - line.angle()
		_lane.scale.z = maxf(line.length() * _units, 0.01)
		_marker.position = Vector3(end.x * _units, 0.03, end.y * _units)
		_marker.scale = Vector3.ONE * (1.0 + sin(_time * 14) * 0.10)


func threatens(point: Vector2, margin: float = 0.0) -> bool:
	if phase not in [Phase.WINDUP, Phase.CHARGE]:
		return false
	var offset := point - global_position
	return (
		offset.dot(_direction) > -40
		and offset.dot(_direction) < 900
		and absf(offset.cross(_direction)) < 70 + margin * 0.35
	)


func avoidance_target(point: Vector2) -> Vector2:
	var side := signf((point - global_position).cross(_direction))
	if side == 0:
		side = 1
	return point + _direction.orthogonal() * side * 210
