class_name StaticModelBatcher
extends RefCounted
## Instance repeated opaque parts within one static prop, retaining its culling bounds.
## Never use on animated rigs: their child transforms must remain independent.


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
