@tool
extends StaticBody3D
## Compact office copier with a scanner lid, control panel and recessed paper tray.


func _ready() -> void:
	var case := ModelGeometry.material(Color("bbc2bf"), 0.05, 0.75)
	var lid := ModelGeometry.material(Color("d1d5ce"), 0.0, 0.72)
	var dark := ModelGeometry.material(Color("46565b"), 0.12, 0.65)
	var paper := ModelGeometry.material(Color("e6e6d9"), 0.0, 0.92)
	ModelGeometry.cushion(self, Vector3(0, 0.48, 0), Vector3(1.16, 0.92, 0.96), 0.055, case)
	ModelGeometry.cushion(self, Vector3(0, 0.08, 0), Vector3(1.04, 0.16, 0.86), 0.025, dark)
	for height in [0.27, 0.48]:
		ModelGeometry.cushion(
			self, Vector3(0, height, 0.483), Vector3(1.0, 0.17, 0.025), 0.018, lid
		)
		ModelGeometry.cushion(
			self, Vector3(0, height + 0.045, 0.499), Vector3(0.28, 0.025, 0.015), 0.006, dark
		)
	ModelGeometry.cushion(self, Vector3(0, 0.76, 0.482), Vector3(0.84, 0.17, 0.03), 0.025, dark)
	ModelGeometry.cushion(self, Vector3(0, 0.715, 0.49), Vector3(0.65, 0.026, 0.02), 0.005, paper)
	ModelGeometry.cushion(self, Vector3(0, 1.01, -0.07), Vector3(1.2, 0.17, 0.83), 0.04, dark)
	ModelGeometry.cushion(self, Vector3(0, 1.17, -0.10), Vector3(1.17, 0.16, 0.76), 0.045, lid)
	ModelGeometry.cushion(self, Vector3(0, 1.25, -0.10), Vector3(0.49, 0.016, 0.39), 0.008, case)
	var controls := Node3D.new()
	controls.position = Vector3(0.18, 1.075, 0.36)
	controls.rotation.x = -0.35
	add_child(controls)
	ModelGeometry.cushion(controls, Vector3.ZERO, Vector3(0.65, 0.075, 0.24), 0.025, dark)
	var screen := ModelGeometry.material(Color("8baea9"), 0.0, 0.5)
	ModelGeometry.cushion(
		controls, Vector3(-0.10, 0.043, 0), Vector3(0.31, 0.015, 0.16), 0.008, screen
	)
	for index in 3:
		ModelGeometry.cylinder(
			controls,
			Vector3(0.13 + index * 0.065, 0.040, 0),
			Vector3(0.13 + index * 0.065, 0.052, 0),
			0.018,
			lid
		)
