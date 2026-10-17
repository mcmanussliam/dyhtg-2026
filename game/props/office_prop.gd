@tool
class_name OfficeProp
extends StaticBody2D
## Authored 2D gameplay footprint with a reusable, depth-tested 3D presentation.

const AUTHORING_PIXELS_PER_UNIT := RenderStyle.PIXELS_PER_UNIT

@export var visual_scene: PackedScene
@export var baked_visual_mesh: Mesh

var _clip_configured := false
var _clipped_global := PackedVector2Array()
var _clip_boundary := PackedVector2Array()
var _clip_collision: CollisionPolygon2D


func clip_to_circle(center: Vector2, radius: float) -> void:
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
	var boundary := PackedVector2Array()
	for index in 256:
		boundary.append(center + Vector2.from_angle(index * TAU / 256.0) * radius)
	_clip_boundary = boundary
	var intersections := Geometry2D.intersect_polygons(footprint, boundary)
	_clipped_global = intersections[0] if not intersections.is_empty() else PackedVector2Array()
	_clip_configured = true
	source.set_deferred("disabled", true)
	if is_instance_valid(_clip_collision):
		_clip_collision.free()
	_clip_collision = CollisionPolygon2D.new()
	_clip_collision.name = "ClippedFootprint"
	var local_polygon := PackedVector2Array()
	for point in _clipped_global:
		local_polygon.append(to_local(point))
	_clip_collision.polygon = local_polygon
	add_child(_clip_collision)


func create_presentation(parent: Node3D, units_per_pixel: float) -> Node3D:
	if visual_scene == null:
		return null
	var model := visual_scene.instantiate() as Node3D
	model.name = name
	parent.add_child(model)
	var unit_scale := AUTHORING_PIXELS_PER_UNIT * units_per_pixel
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
	return model


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
		if intersections.is_empty():
			continue
		var points := PackedVector3Array()
		for point in intersections[0]:
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
