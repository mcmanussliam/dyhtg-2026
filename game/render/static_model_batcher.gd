class_name StaticModelBatcher
extends RefCounted
## Instance repeated opaque parts within one static prop, retaining its culling bounds.
## Never use on animated rigs: their child transforms must remain independent.

static var _assemblies: Dictionary = {}


static func batch(model: Node3D) -> void:
	var groups: Dictionary = {}
	for child: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if child.mesh == null or child.mesh.get_surface_count() != 1 or not child.visible:
			continue
		var material := child.get_active_material(0) as StandardMaterial3D
		if material == null or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			continue
		var key := [child.mesh, material, child.cast_shadow]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(child)
	for key: Array in groups:
		var parts: Array = groups[key]
		if parts.size() < 2:
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = key[0]
		multimesh.instance_count = parts.size()
		var local := model.global_transform.affine_inverse()
		for index in parts.size():
			multimesh.set_instance_transform(index, local * parts[index].global_transform)
		var renderer := MultiMeshInstance3D.new()
		renderer.name = "RepeatedParts"
		renderer.multimesh = multimesh
		renderer.material_override = key[1]
		renderer.cast_shadow = key[2]
		model.add_child(renderer)
		for part: MeshInstance3D in parts:
			part.free()


static func merge_direct(model: Node3D, cache_key: Array) -> void:
	# Merge only direct rigid parts. Animated child pivots and colliders stay independent.
	if not _assemblies.has(cache_key):
		if _assemblies.size() >= 64:
			_assemblies.clear()
		_assemblies[cache_key] = bake_direct(model)
	else:
		for child in model.get_children():
			if child is MeshInstance3D:
				child.free()
	ModelGeometry.instance(model, _assemblies[cache_key], Vector3.ZERO, null)


static func bake_direct(model: Node3D) -> ArrayMesh:
	var groups: Dictionary = {}
	for child in model.get_children():
		if child is MeshInstance3D:
			var material: Material = child.get_active_material(0)
			if not groups.has(material):
				groups[material] = []
			groups[material].append(child)
	var mesh := ArrayMesh.new()
	for material: Material in groups:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_material(material)
		for part: MeshInstance3D in groups[material]:
			tool.append_from(part.mesh, 0, part.transform)
			part.free()
		tool.commit(mesh)
	return mesh
