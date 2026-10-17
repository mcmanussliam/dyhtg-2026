class_name ColumnGeometry
extends RefCounted
## A smooth cylindrical support with a small bevel below the playable floor.

const SEGMENTS := 256
const BEVEL_STEPS := 6
const BEVEL_METRES := 0.025


static func build(radius: float, depth: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bevel := minf(BEVEL_METRES, minf(radius, depth) * 0.05)
	var profile: Array[Vector2] = []
	var normals: Array[Vector2] = []
	for index in BEVEL_STEPS + 1:
		var angle := float(index) / BEVEL_STEPS * PI * 0.5
		profile.append(
			Vector2(radius - bevel + sin(angle) * bevel, depth * 0.5 - bevel + cos(angle) * bevel)
		)
		normals.append(Vector2(sin(angle), cos(angle)))
	profile.append(Vector2(radius, -depth * 0.5))
	normals.append(Vector2(1, 0))
	for ring in profile.size() - 1:
		for index in SEGMENTS:
			var first := float(index) / SEGMENTS * TAU
			var second := float(index + 1) / SEGMENTS * TAU
			_vertex(surface, profile[ring], normals[ring], first)
			_vertex(surface, profile[ring + 1], normals[ring + 1], first)
			_vertex(surface, profile[ring], normals[ring], second)
			_vertex(surface, profile[ring], normals[ring], second)
			_vertex(surface, profile[ring + 1], normals[ring + 1], first)
			_vertex(surface, profile[ring + 1], normals[ring + 1], second)
	# Close the underside; the upper cap is the independently coloured floor disk.
	for index in SEGMENTS:
		var angle := float(index) / SEGMENTS * TAU
		var next_angle := float(index + 1) / SEGMENTS * TAU
		surface.set_normal(Vector3.DOWN)
		surface.add_vertex(Vector3(0, -depth * 0.5, 0))
		surface.add_vertex(
			Vector3(cos(next_angle) * radius, -depth * 0.5, sin(next_angle) * radius)
		)
		surface.add_vertex(Vector3(cos(angle) * radius, -depth * 0.5, sin(angle) * radius))
	return surface.commit()


static func _vertex(surface: SurfaceTool, point: Vector2, normal: Vector2, angle: float) -> void:
	surface.set_normal(Vector3(cos(angle) * normal.x, normal.y, sin(angle) * normal.x))
	surface.add_vertex(Vector3(cos(angle) * point.x, point.y, sin(angle) * point.x))
