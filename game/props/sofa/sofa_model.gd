@tool
extends StaticBody3D
## Compact office seating with softly bevelled upholstery and a solid footprint.


func _ready() -> void:
	var cloth := ModelGeometry.material(Color("7e9da8"), 0.0, 0.9)
	var seam := ModelGeometry.material(Color("668590"), 0.0, 0.92)
	var base := ModelGeometry.material(Color("4c6269"), 0.12, 0.8)
	ModelGeometry.cushion(self, Vector3(0, 0.24, 0), Vector3(2.20, 0.22, 0.82), 0.055, base)
	ModelGeometry.cushion(self, Vector3(0, 0.66, -0.34), Vector3(2.3, 0.58, 0.22), 0.06, seam)
	for side in [-1.0, 1.0]:
		ModelGeometry.cushion(
			self, Vector3(side * 1.04, 0.56, 0), Vector3(0.22, 0.46, 0.9), 0.06, cloth
		)
		ModelGeometry.cushion(
			self, Vector3(side * 0.49, 0.43, 0.04), Vector3(0.94, 0.23, 0.66), 0.065, cloth
		)
		ModelGeometry.cushion(
			self, Vector3(side * 0.49, 0.72, -0.25), Vector3(0.94, 0.40, 0.17), 0.045, cloth
		)
		for depth in [-1.0, 1.0]:
			ModelGeometry.cylinder(
				self,
				Vector3(side * 0.96, 0.02, depth * 0.30),
				Vector3(side * 0.96, 0.17, depth * 0.30),
				0.055,
				base
			)
