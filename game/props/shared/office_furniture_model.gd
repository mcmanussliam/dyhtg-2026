@tool
extends StaticBody3D
## Geometry in metres, sharing the authored collision footprints in each scene.

enum Kind { DESK, CABINET }

@export var kind: Kind = Kind.DESK


func _ready() -> void:
	if kind == Kind.DESK:
		_build_desk()
	else:
		_build_cabinet()


func _build_desk() -> void:
	var wood := ModelGeometry.material(Color("c8ac84"), 0.0, 0.72)
	var edge := ModelGeometry.material(Color("9b7e5e"), 0.0, 0.76)
	var frame := ModelGeometry.material(Color("52636a"), 0.3, 0.5)
	var dark := ModelGeometry.material(Color("28383f"), 0.12, 0.55)
	ModelGeometry.cushion(self, Vector3(0, 0.80, 0), Vector3(2.4, 0.12, 1.2), 0.035, wood)
	ModelGeometry.cushion(self, Vector3(0, 0.73, 0), Vector3(2.30, 0.045, 1.10), 0.012, edge)
	for side in [-1.0, 1.0]:
		for depth in [-1.0, 1.0]:
			ModelGeometry.cushion(
				self,
				Vector3(side * 1.04, 0.36, depth * 0.44),
				Vector3(0.09, 0.72, 0.09),
				0.015,
				frame
			)
		ModelGeometry.cushion(
			self, Vector3(side * 1.04, 0.14, 0), Vector3(0.10, 0.08, 0.96), 0.02, frame
		)
	ModelGeometry.cushion(self, Vector3(0, 0.90, -0.28), Vector3(0.40, 0.06, 0.27), 0.02, dark)
	ModelGeometry.cushion(self, Vector3(0, 1.06, -0.31), Vector3(0.07, 0.30, 0.07), 0.01, frame)
	ModelGeometry.cushion(self, Vector3(0, 1.30, -0.30), Vector3(0.91, 0.55, 0.065), 0.03, dark)
	var screen := ModelGeometry.material(Color("83b5bd"), 0.05, 0.44)
	ModelGeometry.cushion(self, Vector3(0, 1.30, -0.262), Vector3(0.80, 0.44, 0.014), 0.01, screen)
	ModelGeometry.cushion(self, Vector3(0, 0.89, 0.25), Vector3(0.72, 0.045, 0.25), 0.018, dark)
	var keys := ModelGeometry.material(Color("b8c4c4"), 0.0, 0.8)
	for row in 3:
		for column in 9:
			ModelGeometry.cushion(
				self,
				Vector3(-0.29 + column * 0.072, 0.917, 0.17 + row * 0.065),
				Vector3(0.05, 0.012, 0.043),
				0.003,
				keys
			)


func _build_cabinet() -> void:
	var case := ModelGeometry.material(Color("839796"), 0.15, 0.66)
	var drawer := ModelGeometry.material(Color("a3b2ad"), 0.10, 0.68)
	var dark := ModelGeometry.material(Color("45595c"), 0.25, 0.54)
	ModelGeometry.cushion(self, Vector3(0, 0.625, 0), Vector3(1.0, 1.25, 0.8), 0.035, case)
	ModelGeometry.cushion(self, Vector3(0, 0.055, 0), Vector3(0.89, 0.11, 0.70), 0.018, dark)
	for index in 3:
		var height := 0.29 + index * 0.36
		ModelGeometry.cushion(
			self, Vector3(0, height, 0.395), Vector3(0.88, 0.31, 0.025), 0.018, drawer
		)
		ModelGeometry.cushion(
			self, Vector3(0, height + 0.045, 0.424), Vector3(0.28, 0.045, 0.03), 0.01, dark
		)
