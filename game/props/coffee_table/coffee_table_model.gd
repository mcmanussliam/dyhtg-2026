@tool
extends StaticBody3D
## Low office lounge table with rounded timber and a small document folder.


func _ready() -> void:
	var wood := ModelGeometry.material(Color("c2a581"), 0.0, 0.75)
	var frame := ModelGeometry.material(Color("55666c"), 0.25, 0.6)
	ModelGeometry.cushion(self, Vector3(0, 0.405, 0), Vector3(1.4, 0.09, 0.8), 0.035, wood)
	for side in [-1.0, 1.0]:
		for depth in [-1.0, 1.0]:
			ModelGeometry.cushion(
				self,
				Vector3(side * 0.57, 0.185, depth * 0.27),
				Vector3(0.07, 0.37, 0.07),
				0.015,
				frame
			)
	var paper := ModelGeometry.material(Color("e1e1d1"), 0.0, 0.9)
	var folder := ModelGeometry.material(Color("829a9f"), 0.0, 0.88)
	ModelGeometry.cushion(
		self, Vector3(-0.18, 0.461, -0.03), Vector3(0.43, 0.018, 0.30), 0.007, folder
	)
	ModelGeometry.cushion(
		self, Vector3(-0.18, 0.473, -0.03), Vector3(0.38, 0.009, 0.26), 0.004, paper
	)
