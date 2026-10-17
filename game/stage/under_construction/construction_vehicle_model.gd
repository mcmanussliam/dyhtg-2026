class_name ConstructionVehicleModel
extends Node3D
## A yellow bulldozer, baked into a few surfaces. World-space clipping hides it
## beyond the wall openings, so it appears to emerge from the rubble.

const SURFACE = preload("res://game/stage/under_construction/vehicle.gdshader")


func build(width: float, length: float, stage: OfficeStage, units: float) -> void:
	var yellow := ModelGeometry.material(Color("f0b81c"), 0.1, 0.5)
	var dark := ModelGeometry.material(Color("262c31"), 0.3, 0.6)
	var steel := ModelGeometry.material(Color("6c7780"), 0.55, 0.45)
	var glass := ModelGeometry.material(Color("5e8796"), 0.4, 0.25)
	var amber := ModelGeometry.material(Color("ff8a1f"))
	# Tracks run the full length at each side; the hull sits between them.
	for side in [-1.0, 1.0]:
		var x: float = side * (width * 0.5 - 0.42)
		ModelGeometry.cushion(
			self, Vector3(x, 0.62, 0.0), Vector3(0.84, 1.24, length * 0.92), 0.28, dark
		)
		ModelGeometry.cushion(
			self, Vector3(x, 1.28, 0.0), Vector3(0.9, 0.12, length * 0.84), 0.05, steel
		)
	ModelGeometry.cushion(
		self, Vector3(0, 1.45, 0.25), Vector3(width * 0.66, 1.0, length * 0.58), 0.22, yellow
	)
	ModelGeometry.cushion(
		self, Vector3(0, 1.8, -length * 0.2), Vector3(width * 0.5, 0.9, length * 0.3), 0.2, yellow
	)
	ModelGeometry.cushion(
		self, Vector3(0, 2.7, length * 0.14), Vector3(width * 0.5, 1.35, length * 0.22), 0.12, glass
	)
	ModelGeometry.cushion(
		self,
		Vector3(0, 3.42, length * 0.14),
		Vector3(width * 0.58, 0.14, length * 0.28),
		0.05,
		yellow
	)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		ModelGeometry.cylinder(
			self,
			Vector3(corner.x * width * 0.25, 2.0, length * 0.14 + corner.y * length * 0.1),
			Vector3(corner.x * width * 0.25, 3.4, length * 0.14 + corner.y * length * 0.1),
			0.05,
			yellow
		)
	ModelGeometry.cylinder(
		self,
		Vector3(width * 0.16, 2.2, -length * 0.22),
		Vector3(width * 0.16, 3.5, -length * 0.22),
		0.08,
		dark
	)
	ModelGeometry.ellipsoid(self, Vector3(0, 3.62, length * 0.14), Vector3.ONE * 0.13, amber)
	# Push arms and the heavy blade at the front (-Z).
	for side in [-1.0, 1.0]:
		ModelGeometry.cylinder(
			self,
			Vector3(side * width * 0.3, 0.95, -length * 0.2),
			Vector3(side * width * 0.4, 0.95, -length * 0.5),
			0.1,
			steel
		)
	ModelGeometry.cushion(
		self, Vector3(0, 1.0, -length * 0.5 - 0.14), Vector3(width * 1.02, 1.5, 0.3), 0.12, steel
	)
	ModelGeometry.cushion(
		self, Vector3(0, 1.72, -length * 0.5 - 0.1), Vector3(width * 1.02, 0.14, 0.4), 0.05, dark
	)
	var low := stage.to_global(stage.center - stage.half_size - Vector2.ONE * 12) * units
	var high := stage.to_global(stage.center + stage.half_size + Vector2.ONE * 12) * units
	var bounds := Vector4(low.x, low.y, high.x, high.y)
	var materials: Dictionary = {}
	for child in get_children():
		if not child is MeshInstance3D:
			continue
		var source := child.material_override as StandardMaterial3D
		if not materials.has(source):
			var material := ShaderMaterial.new()
			material.shader = SURFACE
			material.set_shader_parameter("tint", source.albedo_color)
			material.set_shader_parameter("metalness", source.metallic)
			material.set_shader_parameter("room_bounds", bounds)
			materials[source] = material
		child.material_override = materials[source]
	# Bounds are stage-specific, so bake without the global mesh cache.
	ModelGeometry.instance(self, StaticModelBatcher.bake_direct(self), Vector3.ZERO, null)
