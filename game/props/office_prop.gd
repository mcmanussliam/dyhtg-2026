@tool
class_name OfficeProp
extends PhysicsBody2D
## Authored 2D footprint and native presentation, shared by static and rigid prop roots.
## Fractures release the existing model/colliders to 3D; PropCollisionBridge keeps it
## solid to live planar chairs until the geometry drops below their height.

const AUTHORING_PIXELS_PER_UNIT := RenderStyle.PIXELS_PER_UNIT

@export var visual_scene: PackedScene
@export var baked_visual_mesh: Mesh

var _motion: PropMotion
var _presentation_scale := 1.0
var _presentation_units := 1.0 / RenderStyle.PIXELS_PER_UNIT
var _clip_configured := false
var _clip_boundary := PackedVector2Array()
var _clip_collisions: Array[CollisionPolygon2D] = []
var _presentation: Node3D
var _floor_detached := false


func _ready() -> void:
	if not Engine.is_editor_hint() and is_class("RigidBody2D"):
		_motion = PropMotion.new()
		add_child(_motion)


func resize_for_stage(factor: float) -> void:
	if not is_class("RigidBody2D"):
		scale *= factor
		return
	# Keep simulated bodies unscaled; resize their unique shape and visual instead.
	var collision := get_node("CollisionShape2D") as CollisionShape2D
	var shape := collision.shape.duplicate() as Shape2D
	if shape is CircleShape2D:
		shape.radius *= factor
	elif shape is RectangleShape2D:
		shape.size *= factor
	collision.shape = shape
	_presentation_scale *= factor


func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	state.linear_velocity = state.linear_velocity.limit_length(500.0)
	state.angular_velocity = clampf(state.angular_velocity, -5.0, 5.0)


func clip_to_circle(center: Vector2, radius: float) -> void:
	var boundary := PackedVector2Array()
	for index in 256:
		boundary.append(center + Vector2.from_angle(index * TAU / 256.0) * radius)
	clip_to_polygon(boundary)


func clip_to_polygon(boundary: PackedVector2Array) -> void:
	var source := get_node("CollisionShape2D") as CollisionShape2D
	var footprint := PackedVector2Array()
	if source.shape is RectangleShape2D:
		var half_size: Vector2 = source.shape.size * 0.5
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			footprint.append(source.to_global(half_size * corner))
	elif source.shape is CircleShape2D:
		for index in 64:
			footprint.append(
				source.to_global(Vector2.from_angle(index * TAU / 64.0) * source.shape.radius)
			)
	else:
		push_error("OfficeProp clipping needs a rectangle or circle footprint.")
		return
	_clip_boundary = boundary
	var intersections := Geometry2D.intersect_polygons(footprint, boundary)
	_clip_configured = true
	source.set_deferred("disabled", true)
	for collision in _clip_collisions:
		collision.free()
	_clip_collisions.clear()
	for polygon in intersections:
		var collision := CollisionPolygon2D.new()
		collision.name = "ClippedFootprint"
		var local_polygon := PackedVector2Array()
		for point in polygon:
			local_polygon.append(to_local(point))
		collision.polygon = local_polygon
		add_child(collision)
		_clip_collisions.append(collision)


func create_presentation(parent: Node3D, units_per_pixel: float) -> Node3D:
	if visual_scene == null:
		return null
	_presentation_units = units_per_pixel
	var model := visual_scene.instantiate() as Node3D
	model.name = name
	parent.add_child(model)
	var unit_scale := AUTHORING_PIXELS_PER_UNIT * units_per_pixel * _presentation_scale
	var horizontal := Vector3(global_transform.x.x, 0.0, global_transform.x.y) * unit_scale
	var depth := Vector3(global_transform.y.x, 0.0, global_transform.y.y) * unit_scale
	var basis := Basis(horizontal, Vector3.UP * unit_scale, depth)
	var origin := Vector3(global_position.x, 0.0, global_position.y) * units_per_pixel
	model.global_transform = Transform3D(basis, origin)
	if _clip_configured:
		_build_clipped_collider(model, units_per_pixel)
	if baked_visual_mesh != null:
		for child in model.find_children("*", "MeshInstance3D", true, false):
			child.free()
		var visual := MeshInstance3D.new()
		visual.name = "BakedVisual"
		visual.mesh = baked_visual_mesh
		model.add_child(visual)
	if is_instance_valid(_motion):
		model = _motion.bind_presentation(model, units_per_pixel)
	_presentation = model
	return model


func release_for_fracture(
	stage: ArenaStage, chips: Array[PackedVector2Array], center: Vector2
) -> void:
	if _floor_detached:
		return
	var source := get_node("CollisionShape2D") as CollisionShape2D
	var reach := source.shape.get_rect().size.length() * global_scale.x * 0.5
	var touched := not stage.has_support_near(global_position, reach)
	if not chips.is_empty():
		# Compare the actual rotated footprint to newly removed floor, not a centre
		# or bounding-circle test. Edge contact hands support/tipping to native 3D.
		var footprint := PackedVector2Array()
		if source.shape is RectangleShape2D:
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point := source.to_global(source.shape.size * 0.5 * corner)
				footprint.append(stage.to_local(point) - center)
		elif source.shape is CircleShape2D:
			for index in 24:
				var point := source.to_global(
					Vector2.from_angle(index * TAU / 24) * source.shape.radius
				)
				footprint.append(stage.to_local(point) - center)
		for chip in chips:
			if not Geometry2D.intersect_polygons(footprint, chip).is_empty():
				touched = true
				break
	if not touched:
		return
	if _motion != null:
		_floor_detached = true
		_motion.release_to_3d()
		return
	_floor_detached = true
	collision_layer = 0
	collision_mask = 0
	if not is_instance_valid(_presentation):
		return
	var falling := FallingStagePiece.new()
	falling.name = "FallingFurniture"
	falling.mass = 20
	falling.continuous_cd = true
	falling.lifetime = 0
	stage.round_stopped.connect(falling.freeze_for_results)
	_presentation.get_parent().add_child(falling)
	falling.global_transform = _presentation.global_transform.orthonormalized()
	for child in _presentation.get_children():
		child.reparent(falling, true)
	_presentation.queue_free()
	_presentation = falling
	attach_falling_collision(falling, _presentation_units)


func attach_falling_collision(body: RigidBody3D, units: float) -> void:
	var bridge := PropCollisionBridge.new()
	get_parent().add_child(bridge)
	bridge.configure(body, units, maxf(_presentation_scale, global_scale.x))


func _build_clipped_collider(model: Node3D, units_per_pixel: float) -> void:
	# Keep the authored compound pieces: a tall monitor does not turn the entire
	# tabletop into an invisible wall. Only each piece's radial footprint is cut.
	for child in model.find_children("*", "CollisionShape3D", true, false):
		var source := child as CollisionShape3D
		var footprint := PackedVector2Array()
		var bottom := INF
		var top := -INF
		for vertex in _shape_vertices(source.shape):
			var point := source.to_global(vertex)
			footprint.append(Vector2(point.x, point.z) / units_per_pixel)
			bottom = minf(bottom, point.y)
			top = maxf(top, point.y)
		footprint = Geometry2D.convex_hull(footprint)
		if footprint.size() > 1 and footprint[0].is_equal_approx(footprint[-1]):
			footprint.resize(footprint.size() - 1)
		var intersections := Geometry2D.intersect_polygons(footprint, _clip_boundary)
		var collision_name := source.name
		source.free()
		for polygon in intersections:
			# Chips can make this intersection concave or split it into islands.
			for piece in Geometry2D.decompose_polygon_in_convex(polygon):
				var points := PackedVector3Array()
				for point in piece:
					for elevation in [bottom, top]:
						var world := Vector3(
							point.x * units_per_pixel, elevation, point.y * units_per_pixel
						)
						points.append(model.to_local(world))
				var shape := ConvexPolygonShape3D.new()
				shape.points = points
				var collision := CollisionShape3D.new()
				collision.name = collision_name
				collision.shape = shape
				model.add_child(collision)


func _shape_vertices(shape: Shape3D) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	if shape is CylinderShape3D:
		for index in 64:
			var radial: Vector2 = Vector2.from_angle(float(index) * TAU / 64.0) * shape.radius
			for elevation in [-shape.height * 0.5, shape.height * 0.5]:
				vertices.append(Vector3(radial.x, elevation, radial.y))
	else:
		var bounds := shape.get_debug_mesh().get_aabb()
		for index in 8:
			vertices.append(bounds.get_endpoint(index))
	return vertices


func is_movable() -> bool:
	return is_instance_valid(_motion)


func push(impulse: Vector2, offset: Vector2) -> void:
	if is_movable():
		_motion.push(impulse, offset)


func set_simulation_active(enabled: bool) -> void:
	if is_movable():
		_motion.set_active(enabled)
