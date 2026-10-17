class_name TrainingTrainModel
extends AnimatableBody3D
## Four connected carriages, merged into a handful of surfaces and reused all round.
## World-space clipping hides the train beyond the actual office entrances.

const SURFACE = preload("res://game/stage/hr_training/train.gdshader")


func build(width: float, length: float, stage: OfficeStage, units: float) -> void:
	sync_to_physics = false
	var shell := ModelGeometry.material(Color("d9dedb"), 0.15)
	var blue := ModelGeometry.material(Color("307e9a"), 0.2)
	var dark := ModelGeometry.material(Color("1a2834"), 0.35)
	var glass := ModelGeometry.material(Color("477e91"), 0.4, 0.25)
	var yellow := ModelGeometry.material(Color("efc351"), 0.15)
	var white := ModelGeometry.material(Color("f9edce"))
	var carriage_count := 4
	var carriage_spacing := length / carriage_count
	var carriage_length := carriage_spacing - 0.12
	for index in carriage_count:
		var middle := (index - (carriage_count - 1) * 0.5) * carriage_spacing
		ModelGeometry.cushion(
			self, Vector3(0, 1.65, middle), Vector3(width, 2.7, carriage_length), 0.3, shell
		)
		ModelGeometry.cushion(
			self,
			Vector3(0, 0.64, middle),
			Vector3(width + 0.02, 0.44, carriage_length - 0.18),
			0.12,
			blue
		)
		ModelGeometry.cushion(
			self,
			Vector3(0, 2.96, middle),
			Vector3(width * 0.9, 0.18, carriage_length - 0.3),
			0.08,
			dark
		)
		for side in [-1.0, 1.0]:
			for window in 4:
				var z := middle + (window - 1.5) * carriage_length * 0.2
				ModelGeometry.cushion(
					self,
					Vector3(side * width * 0.503, 2.0, z),
					Vector3(0.045, 1.0, carriage_length * 0.15),
					0.02,
					glass
				)
			for z in [-0.33, 0.33]:
				ModelGeometry.cylinder(
					self,
					Vector3(side * width * 0.38, 0.35, middle + z * carriage_length),
					Vector3(side * width * 0.52, 0.35, middle + z * carriage_length),
					0.34,
					dark
				)
		ModelGeometry.cushion(
			self,
			Vector3(0, 1.3, middle),
			Vector3(width + 0.04, 0.18, carriage_length - 0.2),
			0.04,
			blue
		)
	ModelGeometry.cushion(
		self, Vector3(0, 1.6, -length * 0.5 + 0.08), Vector3(width * 0.94, 2.3, 0.38), 0.17, yellow
	)
	ModelGeometry.cushion(
		self, Vector3(0, 2.1, -length * 0.5 - 0.12), Vector3(width * 0.8, 0.86, 0.08), 0.035, dark
	)
	for side in [-1.0, 1.0]:
		ModelGeometry.ellipsoid(
			self,
			Vector3(side * width * 0.31, 0.96, -length * 0.5 - 0.14),
			Vector3(0.16, 0.16, 0.07),
			white
		)
	ModelGeometry.cushion(
		self, Vector3(0, 0.5, 0), Vector3(width * 0.62, 0.6, length * 0.98), 0.12, dark
	)
	var bounds_min := stage.to_global(stage.center - stage.half_size - Vector2.ONE * 12) * units
	var bounds_max := stage.to_global(stage.center + stage.half_size + Vector2.ONE * 12) * units
	var bounds := Vector4(bounds_min.x, bounds_min.y, bounds_max.x, bounds_max.y)
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
	# Bounds are stage-specific, so bake this one model without a global mesh cache.
	ModelGeometry.instance(self, StaticModelBatcher.bake_direct(self), Vector3.ZERO, null)
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(width, 3.0, length)
	collision.position.y = 1.6
	add_child(collision)
