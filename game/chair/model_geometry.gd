class_name ModelGeometry
extends RefCounted
## Immutable meshes shared by repeated model parts; instances keep their own materials.

const MAX_CACHED_MESHES := 256
static var _meshes: Dictionary = {}


static func _remember(key: Array, mesh: Mesh) -> Mesh:
	# Bound the cache when editor tools experiment with arbitrary dimensions.
	if _meshes.size() >= MAX_CACHED_MESHES:
		_meshes.clear()
	_meshes[key] = mesh
	return mesh


static func material(
	tint: Color, metal: float = 0.0, roughness: float = 0.65
) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = tint
	result.metallic = metal
	result.roughness = roughness
	return result


static func instance(
	parent: Node3D, mesh: Mesh, centre: Vector3, surface: Material
) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = mesh
	result.material_override = surface
	result.position = centre
	parent.add_child(result)
	return result


static func ellipsoid(
	parent: Node3D, centre: Vector3, size: Vector3, surface: Material
) -> MeshInstance3D:
	var key := [&"sphere"]
	if not _meshes.has(key):
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		mesh.radial_segments = 48
		mesh.rings = 24
		_remember(key, mesh)
	var result := instance(parent, _meshes[key], centre, surface)
	result.scale = size
	return result


static func capsule(
	parent: Node3D, start: Vector3, end: Vector3, radius: float, surface: Material
) -> MeshInstance3D:
	var height := start.distance_to(end) + radius * 2
	var key := [&"capsule", radius, height]
	if not _meshes.has(key):
		var mesh := CapsuleMesh.new()
		mesh.radius = radius
		mesh.height = height
		mesh.radial_segments = 40
		mesh.rings = 16
		_remember(key, mesh)
	var result := instance(parent, _meshes[key], (start + end) * 0.5, surface)
	result.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	return result


static func cylinder(
	parent: Node3D,
	start: Vector3,
	end: Vector3,
	radius: float,
	surface: Material,
	tip_radius: float = -1.0
) -> MeshInstance3D:
	var top := radius if tip_radius < 0 else tip_radius
	var height := start.distance_to(end)
	var key := [&"cylinder", radius, top, height]
	if not _meshes.has(key):
		var mesh := CylinderMesh.new()
		mesh.bottom_radius = radius
		mesh.top_radius = top
		mesh.height = height
		mesh.radial_segments = 48
		_remember(key, mesh)
	var result := instance(parent, _meshes[key], (start + end) * 0.5, surface)
	result.quaternion = Quaternion(Vector3.UP, (end - start).normalized())
	return result


static func cushion(
	parent: Node3D, centre: Vector3, size: Vector3, bevel: float, surface: Material
) -> MeshInstance3D:
	var key := [&"cushion", size, bevel]
	if _meshes.has(key):
		return instance(parent, _meshes[key], centre, surface)
	var box := BoxMesh.new()
	box.size = size
	box.subdivide_width = 12
	box.subdivide_height = 12
	box.subdivide_depth = 12
	var arrays := box.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var core := size * 0.5 - Vector3.ONE * bevel
	for index in vertices.size():
		var nearest := vertices[index].clamp(-core, core)
		var normal := (vertices[index] - nearest).normalized()
		vertices[index] = nearest + normal * bevel
		normals[index] = normal
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return instance(parent, _remember(key, mesh), centre, surface)


static func curved_cushion(
	parent: Node3D, centre: Vector3, size: Vector3, bevel: float, surface: Material
) -> MeshInstance3D:
	var key := [&"curved_cushion", size, bevel]
	if _meshes.has(key):
		return instance(parent, _meshes[key], centre, surface)
	var result := cushion(parent, centre, size, bevel, surface)
	var arrays := result.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var half_width := size.x * 0.5
	var half_height := size.y * 0.5
	for index in vertices.size():
		var p := vertices[index]
		var n := normals[index]
		var y := p.y / half_height
		var taper := 0.86 + 0.14 * y * y
		var derivative := 0.28 * p.y / (half_height * half_height)
		var nx := (n.x - 0.16 * p.x / (half_width * half_width) * n.z) / taper
		var ny := n.y - p.x * derivative * nx - 0.05 * p.y / (half_height * half_height) * n.z
		vertices[index] = Vector3(
			p.x * taper, p.y, p.z + 0.08 * pow(p.x / half_width, 2) + 0.025 * y * y
		)
		normals[index] = Vector3(nx, ny, n.z).normalized()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	result.mesh = _remember(key, mesh)
	return result


static func ring(
	parent: Node3D, centre: Vector3, inner: float, outer: float, surface: Material
) -> MeshInstance3D:
	var key := [&"ring", inner, outer]
	if not _meshes.has(key):
		var mesh := TorusMesh.new()
		mesh.inner_radius = inner
		mesh.outer_radius = outer
		mesh.rings = 48
		mesh.ring_segments = 16
		_remember(key, mesh)
	var result := instance(parent, _meshes[key], centre, surface)
	result.rotation.x = PI / 2
	return result
