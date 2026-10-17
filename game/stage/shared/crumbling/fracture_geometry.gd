class_name FractureGeometry
extends RefCounted
## Flat-colour meshes from the same polygons used for support and floor collision.


static func add_polygon(
	surface: SurfaceTool,
	polygon: PackedVector2Array,
	height: float,
	units: float,
	offset := Vector2.ZERO
) -> int:
	var indices := Geometry2D.triangulate_polygon(polygon)
	var count := 0
	for index in range(0, indices.size(), 3):
		var a := polygon[indices[index]]
		var b := polygon[indices[index + 1]]
		var c := polygon[indices[index + 2]]
		if absf((b - a).cross(c - a)) < 0.05:
			continue
		count += 3
		if (b - a).cross(c - a) < 0:
			var swap := b
			b = c
			c = swap
		for point in [a, b, c]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(
				Vector3((point.x - offset.x) * units, height, (point.y - offset.y) * units)
			)

	return count


static func pit_floor(outline: PackedVector2Array, half_size: Vector2, units: float) -> ArrayMesh:
	return pit_region(outline, Rect2(-half_size, half_size * 2), units)


static func pit_region(outline: PackedVector2Array, region: Rect2, units: float) -> ArrayMesh:
	var room := PackedVector2Array(
		[
			region.position,
			Vector2(region.end.x, region.position.y),
			region.end,
			Vector2(region.position.x, region.end.y)
		]
	)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_floor := false
	for index in outline.size():
		var a := outline[index]
		var b := outline[(index + 1) % outline.size()]
		# Three half-planes form the supported part of this radial sector. Unlike
		# boolean subtraction, shared radial edges cannot produce spurious hole polygons.
		var supported := _clip_half_plane(room, Vector2.ZERO, a, true)
		supported = _clip_half_plane(supported, Vector2.ZERO, b, false)
		supported = _clip_half_plane(supported, a, b, false)
		if supported.size() >= 3:
			has_floor = add_polygon(surface, supported, 0, units) > 0 or has_floor
	return surface.commit() if has_floor else ArrayMesh.new()


static func _clip_half_plane(
	polygon: PackedVector2Array, a: Vector2, b: Vector2, left: bool
) -> PackedVector2Array:
	var result := PackedVector2Array()
	if polygon.is_empty():
		return result
	var direction := b - a
	var previous := polygon[-1]
	var previous_distance := direction.cross(previous - a) * (1 if left else -1)
	for point in polygon:
		var distance := direction.cross(point - a) * (1 if left else -1)
		if (distance >= 0) != (previous_distance >= 0):
			result.append(previous.lerp(point, previous_distance / (previous_distance - distance)))
		if distance >= 0:
			result.append(point)
		previous = point
		previous_distance = distance
	return result


static func slab(
	polygon: PackedVector2Array, units: float, thickness: float, top: Material, sides: Material
) -> ArrayMesh:
	# Hole growth reverses the strip winding relative to island shrinkage. Normalize
	# it before building walls so both maps have outward normals and visible faces.
	var signed_area := 0.0
	for index in polygon.size():
		signed_area += polygon[index].cross(polygon[(index + 1) % polygon.size()])
	if signed_area < 0:
		polygon = polygon.duplicate()
		polygon.reverse()
	var center := Vector2.ZERO
	for point in polygon:
		center += point
	center /= polygon.size()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(top)
	add_polygon(surface, polygon, 0, units, center)
	var mesh := surface.commit()
	surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(sides)
	for index in polygon.size():
		var a := (polygon[index] - center) * units
		var b := (polygon[(index + 1) % polygon.size()] - center) * units
		for point in [
			Vector3(a.x, 0, a.y),
			Vector3(a.x, -thickness, a.y),
			Vector3(b.x, 0, b.y),
			Vector3(b.x, 0, b.y),
			Vector3(a.x, -thickness, a.y),
			Vector3(b.x, -thickness, b.y)
		]:
			var normal := (b - a).orthogonal().normalized()
			surface.set_normal(Vector3(normal.x, 0, normal.y))
			surface.add_vertex(point)
	var indices := Geometry2D.triangulate_polygon(polygon)
	for index in range(0, indices.size(), 3):
		var points := [
			polygon[indices[index]], polygon[indices[index + 1]], polygon[indices[index + 2]]
		]
		if (points[1] - points[0]).cross(points[2] - points[0]) > 0:
			points.reverse()
		for point: Vector2 in points:
			surface.set_normal(Vector3.DOWN)
			surface.add_vertex(
				Vector3((point.x - center.x) * units, -thickness, (point.y - center.y) * units)
			)
	surface.commit(mesh)
	return mesh
