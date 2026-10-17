class_name OfficeAccessories
extends RefCounted
## Small visual dressing stays on existing furniture, outside driving routes.


static func desk(parent: Node3D, colour: Color) -> void:
	var ceramic := ModelGeometry.material(colour, 0.0, 0.8)
	var coffee := ModelGeometry.material(Color("302c2b"), 0.0, 0.95)
	ModelGeometry.cylinder(
		parent, Vector3(0.76, 0.86, 0.12), Vector3(0.76, 1.03, 0.12), 0.075, ceramic
	)
	ModelGeometry.cylinder(
		parent, Vector3(0.76, 1.031, 0.12), Vector3(0.76, 1.033, 0.12), 0.059, coffee
	)
	ModelGeometry.capsule(
		parent, Vector3(0.85, 0.91, 0.12), Vector3(0.85, 0.98, 0.12), 0.025, ceramic
	)
	var paper := ModelGeometry.material(Color("d8d8c9"), 0.0, 1.0)
	var folder := ModelGeometry.material(Color("627f81"), 0.0, 0.95)
	ModelGeometry.cushion(
		parent, Vector3(-0.76, 0.875, 0.12), Vector3(0.43, 0.03, 0.33), 0.008, folder
	)
	ModelGeometry.cushion(
		parent, Vector3(-0.76, 0.896, 0.12), Vector3(0.38, 0.012, 0.29), 0.003, paper
	)


static func archive_boxes(parent: Node3D, height: float) -> void:
	var cardboard := ModelGeometry.material(Color("ac9c81"), 0.0, 1.0)
	var label := ModelGeometry.material(Color("dcd9c9"), 0.0, 1.0)
	for index in 2:
		var x := -0.23 + index * 0.46
		ModelGeometry.cushion(
			parent, Vector3(x, height + 0.16, 0), Vector3(0.40, 0.32, 0.51), 0.012, cardboard
		)
		ModelGeometry.cushion(
			parent, Vector3(x, height + 0.13, 0.259), Vector3(0.20, 0.07, 0.009), 0.003, label
		)
