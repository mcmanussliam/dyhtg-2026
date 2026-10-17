class_name PropMotion
extends Node
## Passive planar furniture motion; edge fractures hand support and tipping to native 3D.

var _body: RigidBody2D
var _stage: ArenaStage
var _model: Node3D
var _units := 1.0 / RenderStyle.PIXELS_PER_UNIT
var _falling := false


func _ready() -> void:
	_body = get_parent() as RigidBody2D
	var ancestor := _body.get_parent()
	while ancestor != null and not ancestor is ArenaStage:
		ancestor = ancestor.get_parent()
	_stage = ancestor as ArenaStage
	if _stage != null:
		_stage.round_started.connect(set_active.bind(true))
		_stage.round_stopped.connect(set_active.bind(false))
		set_active(_stage.round_running)


func bind_presentation(source: Node3D, units: float) -> Node3D:
	_units = units
	var proxy := AnimatableBody3D.new()
	proxy.sync_to_physics = false
	proxy.collision_layer = 1
	proxy.collision_mask = 1
	source.get_parent().add_child(proxy)
	proxy.global_transform = source.global_transform.orthonormalized()
	for child in source.get_children():
		child.reparent(proxy, true)
	var label := source.name
	source.get_parent().remove_child(source)
	source.queue_free()
	proxy.name = label
	_model = proxy
	return proxy


func set_active(enabled: bool) -> void:
	if not _falling:
		_body.freeze = not enabled
		if enabled:
			_body.sleeping = false
	if is_instance_valid(_model) and _model is RigidBody3D:
		(_model as RigidBody3D).freeze = not enabled


func _physics_process(_delta: float) -> void:
	if _falling:
		if is_instance_valid(_model) and _model.global_position.y < -35.0:
			_model.queue_free()
			set_physics_process(false)
		return
	# Sleeping props have unchanged poses and support; native impulses wake them.
	if _body.sleeping or _body.freeze:
		return
	if is_instance_valid(_model):
		_model.global_transform = Transform3D(
			Basis(Vector3.UP, -_body.global_rotation),
			Vector3(_body.global_position.x, 0, _body.global_position.y) * _units
		)
	if _body.freeze or _stage == null:
		return
	var shape := (_body.get_node("CollisionShape2D") as CollisionShape2D).shape
	var radius := shape.get_rect().size.length() * 0.5
	if shape is CircleShape2D:
		radius = shape.radius
	if not _stage.has_support_near(_body.global_position, radius):
		_start_fall()


func release_to_3d() -> void:
	# Floor fractures can wake/release a sleeping prop before its centre loses support.
	if not _falling:
		_start_fall()


func launch(velocity: Vector3, spin: Vector3) -> void:
	if _falling or _body.freeze or not is_instance_valid(_model):
		return
	_start_fall()
	var native := _model as RigidBody3D
	# Match player knockouts: ballistic launches clear trains, walls and desks.
	# Ordinary floor fractures still keep their native arena collision.
	native.collision_layer = 0
	native.collision_mask = 0
	native.linear_velocity = velocity
	native.angular_velocity = spin


func _start_fall() -> void:
	_falling = true
	var velocity := _body.linear_velocity
	var spin := _body.angular_velocity
	_body.freeze = true
	_body.collision_layer = 0
	_body.collision_mask = 0
	if not is_instance_valid(_model):
		return
	var falling := RigidBody3D.new()
	falling.name = "FallingProp"
	falling.mass = _body.mass
	falling.continuous_cd = true
	_model.get_parent().add_child(falling)
	# Bake presentation scale into children, never into the native rigid body.
	falling.global_transform = _model.global_transform.orthonormalized()
	for child in _model.get_children():
		child.reparent(falling, true)
	_model.queue_free()
	_model = falling
	falling.linear_velocity = Vector3(velocity.x, 0, velocity.y) * _units
	falling.angular_velocity = Vector3(0, -spin, 0)
	_body.call("attach_falling_collision", falling, _units)


func _exit_tree() -> void:
	if is_instance_valid(_model):
		_model.queue_free()


func push(impulse: Vector2, offset: Vector2) -> void:
	if not _body.freeze:
		_body.apply_impulse(impulse, offset)
