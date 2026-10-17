@tool
extends StaticBody3D
## A small ceramic pot supports a clean, readable cluster of broad leaves.


func _ready() -> void:
	var ceramic := ModelGeometry.material(Color("c7b9a6"), 0.0, 0.7)
	var soil := ModelGeometry.material(Color("5e5148"), 0.0, 0.95)
	var stem := ModelGeometry.material(Color("607963"), 0.0, 0.9)
	var leaves := ModelGeometry.material(Color("7c9b77"), 0.0, 0.88)
	ModelGeometry.cylinder(self, Vector3(0, 0.015, 0), Vector3(0, 0.435, 0), 0.22, ceramic, 0.28)
	ModelGeometry.cylinder(self, Vector3(0, 0.425, 0), Vector3(0, 0.45, 0), 0.28, ceramic)
	ModelGeometry.cylinder(self, Vector3(0, 0.451, 0), Vector3(0, 0.454, 0), 0.24, soil)
	ModelGeometry.capsule(self, Vector3(0, 0.44, 0), Vector3(0, 1.09, 0), 0.018, stem)
	for index in 7:
		var angle := float(index) * 2.39996
		var height := 0.70 + float(index % 3) * 0.16
		var centre := Vector3(cos(angle) * 0.13, height, sin(angle) * 0.13)
		var leaf := ModelGeometry.ellipsoid(self, centre, Vector3(0.085, 0.27, 0.045), leaves)
		leaf.rotation = Vector3(sin(angle) * 0.65, angle, -cos(angle) * 0.65)
	ModelGeometry.ellipsoid(self, Vector3(0, 1.12, 0), Vector3(0.075, 0.18, 0.05), leaves)
