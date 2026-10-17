class_name ExtinguisherModel
extends Node3D
## Rounded pressure vessel, yellow band, sculpted red levers and a curved rubber hose.

var nozzle: Marker3D


func build() -> void:
	name = "Extinguisher"
	var enamel := ShaderMaterial.new()
	enamel.shader = preload("res://game/chair/art/extinguisher.gdshader")
	var red := ModelGeometry.material(Color("c53f38"), 0.08, 0.45)
	var rubber := ModelGeometry.material(Color("303a3d"), 0, 0.83)
	var metal := ModelGeometry.material(Color("788588"), 0.45, 0.4)
	var horn := ModelGeometry.material(Color("4b5558"), 0.12, 0.62)
	ModelGeometry.instance(self, _tank_mesh(), Vector3.ZERO, enamel)
	ModelGeometry.cylinder(self, Vector3(0, -0.015, 0), Vector3(0, -0.005, 0), 0.115, rubber)
	ModelGeometry.cylinder(self, Vector3(0, 0.445, 0), Vector3(0, 0.505, 0), 0.052, metal)
	ModelGeometry.cylinder(self, Vector3(-0.074, 0.505, 0), Vector3(0.074, 0.505, 0), 0.012, metal)
	var top: Array[Vector3] = [
		Vector3(0, 0.51, 0.015),
		Vector3(0, 0.60, -0.05),
		Vector3(0, 0.56, -0.18),
		Vector3(0, 0.53, -0.25)
	]
	var trigger: Array[Vector3] = [
		Vector3(0, 0.49, 0),
		Vector3(0, 0.46, -0.06),
		Vector3(0, 0.38, -0.17),
		Vector3(0, 0.31, -0.19)
	]
	ModelGeometry.instance(self, _curve_mesh(top, 0.13, 0.035), Vector3.ZERO, red)
	ModelGeometry.instance(self, _curve_mesh(trigger, 0.11, 0.033), Vector3.ZERO, red)
	var hose: Array[Vector3] = [
		Vector3(0, 0.48, 0.035),
		Vector3(0, 0.48, 0.095),
		Vector3(0, 0.405, 0.11),
		Vector3(0, 0.405, 0.17)
	]
	ModelGeometry.instance(self, _curve_mesh(hose, 0.047, 0.047), Vector3.ZERO, rubber)
	# A shoulder-mounted cradle supports the horn instead of leaving it cantilevered.
	ModelGeometry.capsule(self, Vector3(0, 0.34, 0.10), Vector3(0, 0.405, 0.17), 0.024, rubber)
	ModelGeometry.cylinder(self, Vector3(0, 0.405, 0.145), Vector3(0, 0.405, 0.205), 0.043, metal)
	ModelGeometry.cylinder(
		self, Vector3(0, 0.405, 0.20), Vector3(0, 0.405, 0.355), 0.043, horn, 0.078
	)
	ModelGeometry.ring(self, Vector3(0, 0.405, 0.355), 0.060, 0.077, horn)
	ModelGeometry.cylinder(self, Vector3(0, 0.405, 0.343), Vector3(0, 0.405, 0.348), 0.060, rubber)
	nozzle = Marker3D.new()
	nozzle.name = "Nozzle"
	nozzle.position = Vector3(0, 0.405, 0.36)
	add_child(nozzle)


func _tank_profile(t: float) -> Vector2:
	var profile: Array[Vector2] = [
		Vector2(0, -0.015),
		Vector2(0.095, -0.015),
		Vector2(0.12, 0.01),
		Vector2(0.125, 0.06),
		Vector2(0.125, 0.30),
		Vector2(0.12, 0.36),
		Vector2(0.102, 0.405),
		Vector2(0.06, 0.44),
		Vector2(0.045, 0.47),
		Vector2(0, 0.47)
	]
	var sample := clampf(t, 0, 1) * (profile.size() - 1)
	var index := mini(int(sample), profile.size() - 2)
	return profile[index].cubic_interpolate(
		profile[index + 1],
		profile[maxi(index - 1, 0)],
		profile[mini(index + 2, profile.size() - 1)],
		sample - index
	)


func _tank_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for ring in 65:
		var t := float(ring) / 64
		var p := _tank_profile(t)
		var tangent := _tank_profile(minf(t + 0.001, 1)) - _tank_profile(maxf(t - 0.001, 0))
		for side in 49:
			var angle := TAU * float(side) / 48
			vertices.append(Vector3(cos(angle) * p.x, p.y, sin(angle) * p.x))
			normals.append(
				Vector3(cos(angle) * tangent.y, -tangent.x, sin(angle) * tangent.y).normalized()
			)
			if ring > 0 and side < 48:
				var current := ring * 49 + side
				indices.append_array(
					PackedInt32Array(
						[
							current - 49,
							current + 1,
							current,
							current - 49,
							current - 48,
							current + 1
						]
					)
				)
	return _mesh(vertices, normals, indices)


func _curve_mesh(points: Array[Vector3], width: float, thickness: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for ring in 25:
		var t := float(ring) / 24
		var p := points[0].bezier_interpolate(points[1], points[2], points[3], t)
		var tangent := points[0].bezier_derivative(points[1], points[2], points[3], t).normalized()
		var right := (Vector3.RIGHT - tangent * tangent.x).normalized()
		var up := tangent.cross(right).normalized()
		var cap := smoothstep(0, 0.10, t) * (1.0 - smoothstep(0.90, 1.0, t))
		for side in 21:
			var angle := TAU * float(side) / 20
			var radial := right * cos(angle) * width * 0.5 + up * sin(angle) * thickness * 0.5
			vertices.append(p + radial * cap)
			var normal := right * cos(angle) / width + up * sin(angle) / thickness
			normal += tangent * (smoothstep(0.9, 1.0, t) - (1.0 - smoothstep(0, 0.1, t))) * 25
			normals.append(normal.normalized())
			if ring > 0 and side < 20:
				var current := ring * 21 + side
				indices.append_array(
					PackedInt32Array(
						[
							current - 21,
							current,
							current + 1,
							current - 21,
							current + 1,
							current - 20
						]
					)
				)
	return _mesh(vertices, normals, indices)


func _mesh(
	vertices: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array
) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
