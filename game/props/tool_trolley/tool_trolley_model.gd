@tool
extends StaticBody3D
## Wheeled site trolley; tools are dressing on its existing collision footprint.


func _ready() -> void:
	var paint := ModelGeometry.material(Color("bc9b4b"), 0.15, 0.75)
	var metal := ModelGeometry.material(Color("718088"), 0.65, 0.5)
	var dark := ModelGeometry.material(Color("303c44"), 0, 0.85)
	for height in [0.25, 0.91]:
		ModelGeometry.cushion(self, Vector3(0, height, 0), Vector3(1.15, 0.075, 0.76), 0.018, paint)
	for x in [-0.50, 0.50]:
		for z in [-0.30, 0.30]:
			ModelGeometry.capsule(self, Vector3(x, 0.13, z), Vector3(x, 0.96, z), 0.025, metal)
			ModelGeometry.cylinder(
				self, Vector3(x, 0.10, z - 0.04), Vector3(x, 0.10, z + 0.04), 0.10, dark
			)
	ModelGeometry.capsule(self, Vector3(0.53, 1.10, -0.30), Vector3(0.53, 1.10, 0.30), 0.03, metal)
	for z in [-0.30, 0.30]:
		ModelGeometry.capsule(self, Vector3(0.53, 0.9, z), Vector3(0.53, 1.10, z), 0.025, metal)
	# Toolbox below, a drill and a wrench on the top tray.
	ModelGeometry.cushion(self, Vector3(-0.10, 0.44, 0), Vector3(0.72, 0.32, 0.44), 0.025, dark)
	ModelGeometry.cushion(self, Vector3(-0.10, 0.61, 0), Vector3(0.34, 0.055, 0.12), 0.018, metal)
	ModelGeometry.cushion(
		self, Vector3(-0.22, 1.04, -0.10), Vector3(0.33, 0.13, 0.15), 0.025, paint
	)
	ModelGeometry.cushion(self, Vector3(-0.10, 0.99, -0.10), Vector3(0.10, 0.14, 0.13), 0.012, dark)
	ModelGeometry.cylinder(
		self, Vector3(-0.39, 1.04, -0.10), Vector3(-0.48, 1.04, -0.10), 0.025, metal
	)
	ModelGeometry.capsule(self, Vector3(0.05, 0.97, 0.20), Vector3(0.32, 0.97, 0.20), 0.025, metal)
	for z in [0.16, 0.24]:
		ModelGeometry.capsule(self, Vector3(0.31, 0.97, z), Vector3(0.39, 0.97, z), 0.022, metal)
