extends Node2D
## Live orthographic 3D artwork over the unchanged 2D rigid-body simulation.

const MODEL_SCRIPT = preload("res://game/chair/chair_model.gd")
const PIXELS_PER_UNIT := RenderStyle.PIXELS_PER_UNIT
const VIEW_SIZE := 10.0
const RENDER_SIZE := 1024

var _stage: ArenaStage
var _shared: bool = false
var _world: Node3D
var _rig: Node3D
var _shadow: MeshInstance3D
var _time := 0.0
var _fall_body: RigidBody3D
var _recovery_contact_time := 0.0
var _camera: Camera3D
var _camera_home := Vector3.ZERO
var _lean := Vector2.ZERO
var _lean_velocity := Vector2.ZERO
var _previous_velocity := Vector2.ZERO
var _model: ChairModel
var _viewport: Viewport
var _sprite: Sprite2D
var _spray: SprayView


func configure_world(viewport: Viewport, world: Node3D, stage: ArenaStage = null) -> void:
	_shared = true
	_viewport = viewport
	_world = world
	_stage = stage


func _ready() -> void:
	if _shared:
		_ready_shared()
		return
	var chair := get_parent() as Chair
	_viewport = SubViewport.new()
	_viewport.name = "CharacterViewport"
	RenderStyle.configure_viewport(_viewport, Vector2i(RENDER_SIZE, RENDER_SIZE), true)
	add_child(_viewport)
	_model = MODEL_SCRIPT.new()
	_viewport.add_child(_model)
	_model.build(chair.colour, chair.skin, chair.hat_id)
	_model.scale = Vector3.ONE * chair.size_scale
	RenderStyle.setup_world(_viewport, true)
	var target := Vector3(0, 0.85, 0)
	_camera = RenderStyle.orthographic_camera(
		_viewport, VIEW_SIZE, target + Vector3(0, 0.72, sqrt(1 - 0.72 * 0.72)) * 6.0, target
	)
	_camera_home = _camera.position
	_spray = SprayView.new()
	_spray.name = "Spray"
	_viewport.add_child(_spray)
	_sprite = Sprite2D.new()
	_sprite.name = "RenderedCharacter"
	_sprite.texture = _viewport.get_texture()
	RenderStyle.configure_composite(_sprite)
	var pixel_scale := PIXELS_PER_UNIT * VIEW_SIZE / float(RENDER_SIZE)
	_sprite.scale = Vector2(pixel_scale, pixel_scale / 0.72)
	_sprite.position.y = -0.85 * PIXELS_PER_UNIT * sqrt(1 - 0.72 * 0.72) / 0.72
	add_child(_sprite)
	_sync_heading(chair)
	chair.bumped.connect(_on_bumped)
	_update_plume(chair)


func _process(delta: float) -> void:
	_time += delta
	var chair := get_parent() as Chair
	if chair.falling:
		if not is_instance_valid(_fall_body):
			return
		if not _shared:
			var planar := Vector2(_fall_body.position.x, _fall_body.position.z)
			position = (planar * PIXELS_PER_UNIT).rotated(-chair.rotation)
			_camera.position = _camera_home + Vector3(planar.x, 0, planar.y)
		return
	var acceleration := (chair.linear_velocity - _previous_velocity) / maxf(delta, 0.001)
	_previous_velocity = chair.linear_velocity
	var target := (-acceleration.rotated(-chair.aim_angle) * 0.008).limit_length(7.0)
	target.y -= chair.angular_velocity * 0.9
	var step := minf(delta, 0.033)
	_lean_velocity += ((target - _lean) * 85.0 - _lean_velocity * 12.0) * step
	_lean += _lean_velocity * step
	_sync_heading(chair)
	var local_velocity := chair.linear_velocity.rotated(-chair.aim_angle)
	_model.animate(
		delta,
		_time,
		chair.linear_velocity.length() / chair.tuning.maximum_speed,
		chair.impact,
		_lean,
		Vector2(-local_velocity.y, local_velocity.x)
	)
	_update_plume(chair)


func _physics_process(delta: float) -> void:
	var chair := get_parent() as Chair
	if not chair.falling:
		return
	if not is_instance_valid(_fall_body):
		_sync_heading(chair)
		_start_fall(chair)
	if _shared and chair.active:
		_recover_on_floor(chair, delta)
		if _try_land(chair):
			return
	# A wheel over the rim is not a loss: the native body must actually drop.
	if _fall_body.global_position.y < -0.5 * chair.size_scale:
		chair.confirm_fall()


func _sync_heading(chair: Chair) -> void:
	# Counter-rotate the texture; apply physical heading exactly once in 3D.
	rotation = -chair.rotation
	if _shared:
		_rig.position = (
			Vector3(chair.global_position.x, 0, chair.global_position.y) / PIXELS_PER_UNIT
		)
	_model.rotation.y = PI / 2.0 - chair.aim_angle


func _draw() -> void:
	if _shared or (get_parent() as Chair).falling:
		return
	draw_set_transform(Vector2(0, 5), 0, Vector2(1.1, 0.70))
	draw_circle(Vector2.ZERO, 29, Color(0.12, 0.19, 0.20, 0.09))
	draw_circle(Vector2.ZERO, 23, Color(0.12, 0.19, 0.20, 0.10))
	draw_set_transform(Vector2.ZERO)


func _on_bumped(impulse: Vector2) -> void:
	var chair := get_parent() as Chair
	var local := impulse.rotated(-chair.aim_angle)
	_model.hit(Vector2(-local.y, local.x))


func _update_plume(chair: Chair) -> void:
	var origin := _rig.global_position if _shared else Vector3.ZERO
	_spray.update_plume(chair, _model.extinguisher.nozzle.global_position, _time, origin)


func freeze_visuals() -> void:
	if is_instance_valid(_fall_body):
		_fall_body.freeze = true
	set_process(false)
	set_physics_process(false)
	if not _shared:
		(_viewport as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE


func _start_fall(chair: Chair) -> void:
	# Transfer the unsupported assembly into native 3D physics. The arena body
	# stops colliding at handoff; this body retains its exact momentum.
	_recovery_contact_time = 0.0
	_fall_body = RigidBody3D.new()
	_fall_body.name = "FallingChair"
	_fall_body.mass = chair.mass
	_fall_body.continuous_cd = true
	_fall_body.contact_monitor = true
	_fall_body.max_contacts_reported = 8
	_fall_body.rotation.y = _model.global_rotation.y
	_fall_body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	_fall_body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	_fall_body.linear_damp = 0.0
	_fall_body.angular_damp = 0.0
	_fall_body.position = _model.global_position + Vector3(0, 0.8 * chair.size_scale, 0)
	if _shared:
		_world.add_child(_fall_body)
		_shadow.hide()
	else:
		_viewport.add_child(_fall_body)
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35 * chair.size_scale
	shape.height = 1.4 * chair.size_scale
	collision.position.y = 0.2 * chair.size_scale
	collision.shape = shape
	_fall_body.add_child(collision)
	var base := CollisionShape3D.new()
	var base_shape := BoxShape3D.new()
	base_shape.size = Vector3(1.3, 0.15, 1.2) * chair.size_scale
	base.shape = base_shape
	base.position.y = -0.7 * chair.size_scale
	_fall_body.add_child(base)
	_model.reparent(_fall_body, true)
	_fall_body.linear_velocity = (
		Vector3(chair.fall_velocity.x, 0, chair.fall_velocity.y) / PIXELS_PER_UNIT
	)
	_fall_body.angular_velocity = Vector3(0, -chair.fall_spin, 0)
	if not chair.knockout_velocity.is_zero_approx():
		# Eliminated launch bodies are ballistic visual projectiles. Ignoring arena
		# collision lets them sail out instead of lodging in a wall or nearby desk.
		# Native gravity and full angular inertia still control the complete flight.
		_fall_body.collision_layer = 0
		_fall_body.collision_mask = 0
		_fall_body.linear_velocity = chair.knockout_velocity
		_fall_body.angular_velocity = chair.knockout_spin
	_spray.hide()
	if not _shared:
		queue_redraw()


func _recover_on_floor(chair: Chair, delta: float) -> void:
	# Assist a grounded tumble with damped torque, never lift a chair over a void.
	if _stage == null or not _stage.round_running:
		return
	var grounded := false
	for contact in _fall_body.get_colliding_bodies():
		if contact.is_in_group("stage_floor"):
			grounded = true
	if not grounded:
		_recovery_contact_time = 0.0
		return
	_recovery_contact_time += delta
	if _recovery_contact_time < 0.35:
		return
	var up := _fall_body.global_basis.y.normalized()
	var axis := up.cross(Vector3.UP)
	var angle := acos(clampf(up.dot(Vector3.UP), -1.0, 1.0))
	if angle < 0.02:
		return
	# Exactly inverted orientations have a zero cross product; choose a roll axis.
	if axis.length_squared() < 0.0001:
		axis = _fall_body.global_basis.x
		axis.y = 0
	axis = axis.normalized()
	var tumble := _fall_body.angular_velocity
	tumble.y = 0
	_fall_body.sleeping = false
	_fall_body.apply_torque((axis * angle * 18.0 - tumble * 6.0) * chair.mass)


func _try_land(chair: Chair) -> bool:
	# A real upright floor contact can return a fast gap crossing to planar play.
	# No minimum speed, hover timer or position snap carries a chair over empty space.
	if _stage == null or not _stage.round_running:
		return false
	if _fall_body.global_basis.y.dot(Vector3.UP) < 0.96:
		return false
	if absf(_fall_body.global_position.y - 0.8 * chair.size_scale) > 0.12 * chair.size_scale:
		return false
	var landed := false
	for contact in _fall_body.get_colliding_bodies():
		if contact.is_in_group("stage_floor"):
			landed = true
	if not landed:
		return false
	var point := (
		Vector2(_fall_body.global_position.x, _fall_body.global_position.z) * PIXELS_PER_UNIT
	)
	if not _stage.has_support(point):
		return false
	var velocity := (
		Vector2(_fall_body.linear_velocity.x, _fall_body.linear_velocity.z) * PIXELS_PER_UNIT
	)
	var heading := PI / 2.0 - _fall_body.global_rotation.y
	var spin := -_fall_body.angular_velocity.y
	_model.reparent(_rig, true)
	_model.position = Vector3.ZERO
	_model.rotation = Vector3.ZERO
	_fall_body.queue_free()
	_fall_body = null
	chair.land_from_fall(point, heading, velocity, spin)
	_shadow.show()
	_spray.show()
	_previous_velocity = velocity
	_sync_heading(chair)
	return true


func _ready_shared() -> void:
	var chair := get_parent() as Chair
	_rig = Node3D.new()
	_rig.name = "ChairRig%d" % chair.seat
	_world.add_child(_rig)
	_model = MODEL_SCRIPT.new()
	_rig.add_child(_model)
	_model.build(chair.colour, chair.skin, chair.hat_id)
	_model.scale = Vector3.ONE * chair.size_scale
	_spray = SprayView.new()
	_world.add_child(_spray)
	_shadow = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.6, 1.3) * chair.size_scale
	_shadow.mesh = plane
	_shadow.position.y = 0.012
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shadow_material := ShaderMaterial.new()
	shadow_material.shader = preload("res://game/chair/art/contact_shadow.gdshader")
	_shadow.material_override = shadow_material
	_rig.add_child(_shadow)
	_sync_heading(chair)
	chair.bumped.connect(_on_bumped)
	_update_plume(chair)


func _exit_tree() -> void:
	if not _shared:
		return
	for node in [_rig, _spray, _fall_body]:
		if is_instance_valid(node):
			node.queue_free()
