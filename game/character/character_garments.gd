class_name CharacterGarments
extends RefCounted
## Separate, pre-baked closed shells: real collars, cuffs and hems over untouched skin.
## Meshes are shared; each model owns its fabric colour and logo material.


static func build(parent: Node3D, skin: CharacterSkin, tint: Color) -> void:
	if skin.garment_mesh == null or skin.garment_shader == null:
		return
	var fabric := CosmeticColours.fabric(tint)
	var material := _material(skin, fabric, skin.chest_logo != null)
	var clothing := ModelGeometry.instance(parent, skin.garment_mesh, Vector3.ZERO, material)
	clothing.name = "Clothing"
	if skin.garment != CharacterSkin.Garment.HOODIE:
		return
	var root := Node3D.new()
	root.name = "GarmentDetails"
	parent.add_child(root)
	var cloth := ModelGeometry.material(fabric, 0, 0.95)
	ModelGeometry.ellipsoid(root, Vector3(0, 0.79, -0.16), Vector3(0.24, 0.13, 0.14), cloth)
	if skin.pocket_mesh != null:
		ModelGeometry.instance(
			root, skin.pocket_mesh, Vector3.ZERO, _material(skin, fabric.darkened(0.06), false)
		)
	# Follow the baked chest profile so cords sit on the fabric, clear of the face.
	var cord := ModelGeometry.material(fabric.lightened(0.65), 0, 0.9)
	var tips := ModelGeometry.material(fabric.darkened(0.30), 0, 0.8)
	for side in [-1.0, 1.0]:
		var points := PackedVector3Array(
			[
				Vector3(side * 0.160, 0.75, 0.229),
				Vector3(side * 0.161, 0.72, 0.235),
				Vector3(side * 0.163, 0.68, 0.245),
				Vector3(side * 0.165, 0.64, 0.253),
				Vector3(side * 0.168, 0.615, 0.256),
			]
		)
		for index in points.size() - 1:
			ModelGeometry.capsule(root, points[index], points[index + 1], 0.008, cord)
		ModelGeometry.capsule(root, points[-1], points[-1] + Vector3(0, -0.022, 0.002), 0.009, tips)
	StaticModelBatcher.merge_direct(root, [&"hoodie_details", tint])


static func _material(skin: CharacterSkin, fabric: Color, logo: bool) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = skin.garment_shader
	material.set_shader_parameter("clothing_colour", fabric)
	material.set_shader_parameter("logo_colour", CosmeticColours.logo_ink(fabric))
	material.set_shader_parameter("garment_kind", skin.garment)
	material.set_shader_parameter("has_logo", logo)
	if logo:
		material.set_shader_parameter("chest_logo", skin.chest_logo)
	return material
