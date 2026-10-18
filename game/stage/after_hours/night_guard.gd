class_name NightGuard
extends CharacterBody2D
## A patrolling guard whose flashlight cone is the hazard. Hard furniture and walls
## block sight; losing sight long enough sends the guard to search, then back on patrol.
## Every phase advances on the stage's physics clock only.

enum Phase { ENTERING, PATROL, ALERT, CHASE, SEARCH, RETURN, CAUGHT }

## Even a slow patrol shoves a loose chair clear rather than nudging it along.
const SHOVE_MIN_SPEED := 220.0

@export var sight_range := 470.0
@export var sight_half_angle := 0.42
@export var touch_range := 70.0
@export var patrol_speed := 170.0
@export var chase_speed := 540.0
@export var chase_acceleration := 700.0
@export var alert_seconds := 0.7
@export var lost_sight_seconds := 0.4
@export var search_seconds := 1.6
@export var caught_seconds := 1.4
@export var knockout_speed := 2100.0  # Planar pixels per second.
@export var knockout_lift := 14.0  # Native 3D metres per second.
@export var knockout_tumble := 9.0  # Radians per second.

var chairs: Array[Chair] = []
var phase := Phase.PATROL
var target: Chair
var route := PackedVector2Array()
var last_seen := Vector2.ZERO
## Flashlight heading in world radians; patrols sweep it slightly around the body heading.
var beam_angle := 0.0
var _stage: OfficeStage
var _waypoint := 0
var _remaining := 0.0
var _unseen := 0.0
var _time := 0.0
var _entry_destination := Vector2.ZERO
var _ray := PhysicsRayQueryParameters2D.new()
var _model: NightGuardModel
var _units := 1.0 / RenderStyle.PIXELS_PER_UNIT


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 1
	collision_mask = 1
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 30
	collision.shape = shape
	add_child(collision)
	_ray.collision_mask = 1
	_ray.exclude = [get_rid()]


func configure(stage: OfficeStage, patrol: PackedVector2Array, start: int) -> void:
	_stage = stage
	route = patrol
	_waypoint = start % maxi(route.size(), 1)


func tick(delta: float) -> void:
	if not _stage.round_running:
		return
	_time += delta
	_remaining -= delta
	match phase:
		Phase.ENTERING:
			_move_towards(_entry_destination, patrol_speed * 1.4, delta)
			if global_position.distance_to(_entry_destination) < 8:
				collision_layer = 1
				collision_mask = 1
				_begin_return()
		Phase.PATROL:
			_patrol(delta)
			_look_for_players()
		Phase.ALERT:
			velocity = Vector2.ZERO
			if _target_valid():
				last_seen = target.global_position
			_face(last_seen, delta, 9.0)
			if _remaining <= 0:
				phase = Phase.CHASE
				_unseen = 0
		Phase.CHASE:
			_chase(delta)
		Phase.SEARCH:
			if global_position.distance_to(last_seen) > 24:
				_move_towards(last_seen, patrol_speed * 1.6, delta)
			else:
				velocity = Vector2.ZERO
				beam_angle = rotation + sin(_time * 4.0) * 0.9
			_look_for_players()
			if phase == Phase.SEARCH and _remaining <= 0:
				_begin_return()
		Phase.RETURN:
			_move_towards(route[_waypoint], patrol_speed * 1.3, delta)
			if global_position.distance_to(route[_waypoint]) < 24:
				phase = Phase.PATROL
			_look_for_players()
		Phase.CAUGHT:
			velocity = velocity.move_toward(Vector2.ZERO, 900 * delta)
			move_and_collide(velocity * delta)
			if _remaining <= 0:
				_begin_return()
	_sync_presentation(delta)


## Host: [x, y, rotation, beam, phase, speed] in stage-local pixels and radians.
func write_net_state(state: PackedFloat32Array, offset: int) -> void:
	state[offset] = position.x
	state[offset + 1] = position.y
	state[offset + 2] = rotation
	state[offset + 3] = beam_angle
	state[offset + 4] = phase
	state[offset + 5] = velocity.length()


## Mirror: show a host guard's pose, beam and phase. A mirror never collides or catches.
func apply_mirror(state: PackedFloat32Array, offset: int) -> void:
	collision_layer = 0
	collision_mask = 0
	position = Vector2(state[offset], state[offset + 1])
	rotation = state[offset + 2]
	beam_angle = state[offset + 3]
	phase = int(state[offset + 4]) as Phase
	# Only the walk cycle reads this speed; mirrors never move themselves.
	velocity = Vector2.from_angle(rotation) * state[offset + 5]


## Mirror: purely visual animation on the round clock.
func mirror_tick(delta: float) -> void:
	if _stage.round_running:
		_time += delta
		_sync_presentation(delta)


func begin_entry(start: Vector2, destination: Vector2) -> void:
	global_position = start
	_entry_destination = destination
	rotation = (destination - start).angle()
	beam_angle = rotation
	phase = Phase.ENTERING
	# Arrivals pass through the closed perimeter, like the bull, harmless until inside.
	collision_layer = 0
	collision_mask = 0


## True when this guard's flashlight reaches the point with nothing hard in between.
func illuminates(point: Vector2, margin: float = 0.0) -> bool:
	if phase in [Phase.ENTERING, Phase.CAUGHT]:
		return false
	var offset := point - global_position
	var distance := offset.length()
	if distance > sight_range + margin:
		return false
	if distance > touch_range + margin:
		var spread := sight_half_angle + atan2(margin, maxf(distance, 1.0))
		if absf(angle_difference(beam_angle, offset.angle())) > spread:
			return false
	return has_line_of_sight(point)


func has_line_of_sight(point: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	_ray.from = global_position
	_ray.to = point
	var excluded: Array[RID] = [get_rid()]
	# Only walls and fixed furniture hide players; loose props and chairs never do.
	for attempt in 8:
		_ray.exclude = excluded
		var hit := space.intersect_ray(_ray)
		if hit.is_empty():
			return true
		if hit.collider is StaticBody2D:
			return false
		excluded.append(hit.rid)
	return true


func is_hunting() -> bool:
	return phase in [Phase.ALERT, Phase.CHASE, Phase.SEARCH]


func stop() -> void:
	velocity = Vector2.ZERO


func _patrol(delta: float) -> void:
	if route.is_empty():
		return
	var goal := route[_waypoint]
	_move_towards(goal, patrol_speed, delta)
	if global_position.distance_to(goal) < 24:
		_waypoint = (_waypoint + 1) % route.size()
	beam_angle = rotation + sin(_time * 1.3) * 0.35


func _look_for_players() -> void:
	var closest: Chair
	var best := INF
	for chair in chairs:
		if not is_instance_valid(chair) or not chair.is_in_play():
			continue
		var distance := chair.global_position.distance_to(global_position)
		if distance < best and illuminates(chair.global_position):
			closest = chair
			best = distance
	if closest == null:
		return
	target = closest
	last_seen = closest.global_position
	# A brief freeze telegraphs the chase; a guard already hunting reacts faster.
	var was_searching := phase == Phase.SEARCH
	phase = Phase.ALERT
	_remaining = alert_seconds * (0.4 if was_searching else 1.0)


func _chase(delta: float) -> void:
	if not _target_valid():
		_begin_search()
		return
	if illuminates(target.global_position, 20):
		last_seen = target.global_position
		_unseen = 0
	else:
		_unseen += delta
		if _unseen >= lost_sight_seconds:
			_begin_search()
			return
	var direction := (last_seen - global_position).normalized()
	velocity = velocity.move_toward(direction * chase_speed, chase_acceleration * delta)
	var previous := global_position
	_slide(delta)
	_face(global_position + velocity, delta, 8.0)
	beam_angle = (last_seen - global_position).angle()
	_check_catch(previous)


func _check_catch(previous: Vector2) -> void:
	for chair in chairs:
		if not is_instance_valid(chair) or not chair.is_in_play():
			continue
		var nearest := Geometry2D.get_closest_point_to_segment(
			chair.global_position, previous, global_position
		)
		if nearest.distance_to(chair.global_position) > 36 + 23 * chair.size_scale:
			continue
		var direction := velocity.normalized()
		if direction.is_zero_approx():
			direction = (chair.global_position - global_position).normalized()
		chair.knock_out(direction, knockout_speed, knockout_lift, knockout_tumble)
		_stage.elimination_requested.emit(chair.seat, &"guard")
		phase = Phase.CAUGHT
		_remaining = caught_seconds
		velocity = -direction * 120
		target = null
		return


func _begin_search() -> void:
	phase = Phase.SEARCH
	_remaining = search_seconds
	target = null


func _begin_return() -> void:
	phase = Phase.RETURN
	target = null
	# Resume at the nearest visible patrol point so guards never cut through furniture.
	var best := INF
	for index in route.size():
		var distance := route[index].distance_to(global_position)
		if distance < best and has_line_of_sight(route[index]):
			best = distance
			_waypoint = index


func _target_valid() -> bool:
	return is_instance_valid(target) and target.is_in_play()


func _move_towards(goal: Vector2, speed: float, delta: float) -> void:
	var offset := goal - global_position
	velocity = offset.normalized() * minf(speed, offset.length() / maxf(delta, 0.001))
	if collision_mask == 0:
		global_position += velocity * delta
	else:
		_slide(delta)
	if offset.length() > 4:
		_face(goal, delta, 4.0)
	beam_angle = rotation


func _slide(delta: float) -> void:
	# Advance on the stage's supplied clock, sliding along fixed furniture and walls.
	var collision := move_and_collide(velocity * delta)
	if collision == null:
		return
	var obstacle := collision.get_collider()
	if obstacle is OfficeProp and obstacle.is_movable():
		# Barge loose clutter clear, faster than the guard is moving, and keep going.
		var shove := velocity.normalized() * maxf(velocity.length(), SHOVE_MIN_SPEED) * 1.5
		obstacle.push(
			shove * (obstacle as RigidBody2D).mass,
			collision.get_position() - obstacle.global_position
		)
		add_collision_exception_with(obstacle)
		move_and_collide(collision.get_remainder())
		remove_collision_exception_with(obstacle)
		return
	move_and_collide(collision.get_remainder().slide(collision.get_normal()))


func _face(point: Vector2, delta: float, turn_rate: float) -> void:
	if point.distance_squared_to(global_position) > 1:
		rotation = rotate_toward(rotation, (point - global_position).angle(), turn_rate * delta)


func create_presentation(parent: Node3D, units: float) -> void:
	_units = units
	_model = NightGuardModel.new()
	parent.add_child(_model)
	# Match the players' content scale; the beam keeps the gameplay sight range.
	_model.scale = Vector3.ONE * _stage.content_scale
	_model.build(sight_range * units / _stage.content_scale, sight_half_angle)
	_sync_presentation(0)


func set_render_warmup(enabled: bool) -> void:
	if is_instance_valid(_model):
		_model.set_alert(enabled or is_hunting())


func _sync_presentation(delta: float) -> void:
	if not is_instance_valid(_model):
		return
	_model.position = Vector3(global_position.x, 0, global_position.y) * _units
	_model.rotation.y = PI / 2 - rotation
	_model.aim(beam_angle - rotation)
	_model.set_alert(is_hunting())
	_model.animate(delta, _time, velocity.length())
