@tool
extends StaticBody3D
## A low acoustic privacy screen between paired desks; no raised arena boundary.


func _ready() -> void:
	var felt := ModelGeometry.material(Color("8da7a1"), 0.0, 0.96)
	var edge := ModelGeometry.material(Color("687d79"), 0.0, 0.9)
	var frame := ModelGeometry.material(Color("536765"), 0.18, 0.65)
	ModelGeometry.cushion(self, Vector3(0, 1.09, 0), Vector3(2.6, 0.46, 0.1), 0.025, edge)
	for side in [-1.0, 1.0]:
		ModelGeometry.cushion(
			self, Vector3(0, 1.09, side * 0.043), Vector3(2.52, 0.38, 0.014), 0.006, felt
		)
		ModelGeometry.cushion(
			self, Vector3(side * 1.03, 0.83, 0), Vector3(0.045, 0.34, 0.07), 0.012, frame
		)
