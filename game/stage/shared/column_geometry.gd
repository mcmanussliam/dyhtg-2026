class_name ColumnGeometry
extends RefCounted
## One angular outline supplies the floor, vertical foundation and baked edge cuts.

# Authored fracture silhouette: broad breaks with smaller asymmetric chips nearby.
# Normalized local X/Z coordinates; shared by every representation of the stage.
const RIM := [
	Vector2(1.0, 0.0),
	Vector2(0.99, 0.10),
	Vector2(0.96, 0.16),
	Vector2(0.975, 0.19),
	Vector2(0.935, 0.29),
	Vector2(0.89, 0.42),
	Vector2(0.86, 0.44),
	Vector2(0.87, 0.47),
	Vector2(0.79, 0.59),
	Vector2(0.68, 0.72),
	Vector2(0.57, 0.79),
	Vector2(0.55, 0.815),
	Vector2(0.51, 0.81),
	Vector2(0.43, 0.88),
	Vector2(0.29, 0.93),
	Vector2(0.22, 0.94),
	Vector2(0.19, 0.925),
	Vector2(0.16, 0.96),
	Vector2(0.02, 0.98),
	Vector2(-0.09, 0.965),
	Vector2(-0.17, 0.97),
	Vector2(-0.29, 0.925),
	Vector2(-0.40, 0.89),
	Vector2(-0.41, 0.85),
	Vector2(-0.46, 0.86),
	Vector2(-0.57, 0.79),
	Vector2(-0.67, 0.71),
	Vector2(-0.70, 0.67),
	Vector2(-0.68, 0.64),
	Vector2(-0.74, 0.60),
	Vector2(-0.83, 0.51),
	Vector2(-0.89, 0.37),
	Vector2(-0.91, 0.35),
	Vector2(-0.90, 0.30),
	Vector2(-0.95, 0.24),
	Vector2(-0.98, 0.11),
	Vector2(-0.97, -0.03),
	Vector2(-0.985, -0.11),
	Vector2(-0.95, -0.21),
	Vector2(-0.92, -0.24),
	Vector2(-0.925, -0.28),
	Vector2(-0.87, -0.43),
	Vector2(-0.79, -0.57),
	Vector2(-0.76, -0.58),
	Vector2(-0.73, -0.67),
	Vector2(-0.60, -0.78),
	Vector2(-0.48, -0.83),
	Vector2(-0.44, -0.875),
	Vector2(-0.29, -0.92),
	Vector2(-0.12, -0.96),
	Vector2(0.02, -0.97),
	Vector2(0.10, -0.95),
	Vector2(0.15, -0.975),
	Vector2(0.30, -0.93),
	Vector2(0.41, -0.87),
	Vector2(0.50, -0.84),
	Vector2(0.56, -0.78),
	Vector2(0.60, -0.80),
	Vector2(0.70, -0.70),
	Vector2(0.77, -0.61),
	Vector2(0.79, -0.54),
	Vector2(0.84, -0.50),
	Vector2(0.90, -0.35),
	Vector2(0.93, -0.30),
	Vector2(0.92, -0.24),
	Vector2(0.97, -0.13),
]


static func outline(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point: Vector2 in RIM:
		points.append(point * radius)
	return points


static func build(radius: float, depth: float) -> ArrayMesh:
	return build_outline(outline(radius), depth)


static func build_outline(points: PackedVector2Array, depth: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in points.size():
		var first := points[index]
		var next := points[(index + 1) % points.size()]
		var a := Vector3(first.x, depth * 0.5, first.y)
		var b := Vector3(first.x, -depth * 0.5, first.y)
		var c := Vector3(next.x, depth * 0.5, next.y)
		var d := Vector3(next.x, -depth * 0.5, next.y)
		_triangle(surface, a, b, c)
		_triangle(surface, c, b, d)
		_triangle(surface, Vector3(0, depth * 0.5, 0), a, c)
		_triangle(surface, Vector3(0, -depth * 0.5, 0), d, b)
	return surface.commit()


static func floor_mesh(radius: float) -> ArrayMesh:
	return floor_outline_mesh(outline(radius))


static func floor_outline_mesh(points: PackedVector2Array) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in points.size():
		var first := points[index]
		var next := points[(index + 1) % points.size()]
		_triangle(surface, Vector3.ZERO, Vector3(first.x, 0, first.y), Vector3(next.x, 0, next.y))
	return surface.commit()


static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	surface.set_normal((c - a).cross(b - a).normalized())
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)
