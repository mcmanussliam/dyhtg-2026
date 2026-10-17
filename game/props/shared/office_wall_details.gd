class_name OfficeWallDetails
extends RefCounted
## Reusable texture-free wall dressing. Mount on an existing solid wall collider.


static func window(parent: Node3D) -> void:
	var frame := ModelGeometry.material(Color("e2dfc9"))
	var glass := ModelGeometry.material(Color("87abb8"), 0.05, 0.55)
	_box(parent, Vector3.ZERO, Vector3(2.95, 1.35, 0.10), frame)
	_box(parent, Vector3(0, 0, 0.065), Vector3(2.77, 1.17, 0.04), glass)
	_box(parent, Vector3(0, 0, 0.10), Vector3(0.055, 1.2, 0.08), frame)
	_box(parent, Vector3(0, 0.2, 0.10), Vector3(2.8, 0.055, 0.08), frame)
	_box(parent, Vector3(0, -0.70, 0.14), Vector3(3.06, 0.10, 0.38), frame)


static func door(parent: Node3D) -> void:
	var frame := ModelGeometry.material(Color("293946"))
	var panel := ModelGeometry.material(Color("60777b"))
	_box(parent, Vector3(0, 1.27, 0), Vector3(1.85, 2.54, 0.14), frame)
	_box(parent, Vector3(0, 1.24, 0.09), Vector3(1.65, 2.40, 0.08), panel)
	_box(
		parent,
		Vector3(0, 1.78, 0.14),
		Vector3(1.20, 0.70, 0.025),
		ModelGeometry.material(Color("91b0b7"))
	)
	ModelGeometry.capsule(
		parent,
		Vector3(0.48, 1.13, 0.20),
		Vector3(0.70, 1.13, 0.20),
		0.04,
		ModelGeometry.material(Color("b1b8b3"), 0.6)
	)
	_box(
		parent,
		Vector3(1.16, 1.13, 0.04),
		Vector3(0.19, 0.26, 0.05),
		ModelGeometry.material(Color("e2dfc9"))
	)


static func clock(parent: Node3D) -> void:
	var dark := ModelGeometry.material(Color("293946"))
	var face := ModelGeometry.material(Color("e2dfc9"))
	ModelGeometry.cylinder(parent, Vector3.ZERO, Vector3(0, 0, 0.10), 0.37, dark)
	ModelGeometry.cylinder(parent, Vector3(0, 0, 0.11), Vector3(0, 0, 0.13), 0.325, face)
	for index in 12:
		var angle := index * TAU / 12
		var direction := Vector3(sin(angle), cos(angle), 0)
		ModelGeometry.capsule(
			parent,
			direction * 0.26 + Vector3(0, 0, 0.15),
			direction * 0.29 + Vector3(0, 0, 0.15),
			0.012,
			dark
		)
	ModelGeometry.capsule(parent, Vector3(0, 0, 0.17), Vector3(0.02, 0.23, 0.17), 0.015, dark)
	ModelGeometry.capsule(parent, Vector3(0, 0, 0.18), Vector3(0.17, -0.08, 0.18), 0.020, dark)


static func _box(parent: Node3D, point: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	ModelGeometry.instance(parent, mesh, point, material)
