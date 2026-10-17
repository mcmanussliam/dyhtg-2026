class_name CharacterHats
extends RefCounted
## Stable cosmetic IDs. Every attachment follows the same snug head-space fit.

const IDS: Array[StringName] = [
	&"none",
	&"traffic_cone",
	&"top_hat",
	&"cap",
	&"mohawk",
	&"glasses",
	&"bald_side_hair",
	&"hot_dog",
	&"construction_helmet"
]
const NAMES := [
	"None",
	"Traffic Cone",
	"Top Hat",
	"Cap",
	"Mohawk",
	"Glasses",
	"Bald Side Hair",
	"Hot Dog Hat",
	"Construction Helmet"
]


static func build(parent: Node3D, id: StringName, colour: Color) -> void:
	if id not in IDS or id == &"none":
		return
	var root := Node3D.new()
	root.name = "Hat"
	root.position.y = -0.045
	root.scale = Vector3(0.94, 1, 0.94)
	parent.add_child(root)
	var fabric := ModelGeometry.material(CosmeticColours.fabric(colour), 0, 0.9)
	var band := ModelGeometry.material(CosmeticColours.fabric(colour).lightened(0.16), 0, 0.95)
	var hair := ModelGeometry.material(CosmeticColours.fabric(colour).darkened(0.3), 0, 0.98)
	match id:
		&"traffic_cone":
			_cone(root, fabric, band)
		&"top_hat":
			ModelGeometry.ellipsoid(root, Vector3(0, 1.21, 0), Vector3(0.31, 0.028, 0.28), fabric)
			ModelGeometry.cylinder(root, Vector3(0, 1.22, 0), Vector3(0, 1.63, 0), 0.23, fabric)
			ModelGeometry.cylinder(root, Vector3(0, 1.25, 0), Vector3(0, 1.32, 0), 0.234, band)
		&"cap":
			ModelGeometry.ellipsoid(root, Vector3(0, 1.20, 0), Vector3(0.26, 0.15, 0.25), fabric)
			ModelGeometry.cushion(
				root, Vector3(0, 1.20, 0.23), Vector3(0.44, 0.035, 0.30), 0.016, fabric
			)
			ModelGeometry.ellipsoid(root, Vector3(0, 1.35, 0), Vector3(0.03, 0.02, 0.03), band)
		&"mohawk":
			for index in 7:
				var z := (index - 3) * 0.055
				var base := 1.235 - pow(z / 0.23, 2) * 0.12
				var height := 0.24 - absf(index - 3) * 0.025
				ModelGeometry.cylinder(
					root,
					Vector3(0, base, z),
					Vector3(0, base + height, z + 0.025),
					0.052,
					fabric,
					0.009
				)
		&"glasses":
			_glasses(root, ModelGeometry.material(CosmeticColours.fabric(colour).darkened(0.75)))
		&"bald_side_hair":
			for side in [-1.0, 1.0]:
				ModelGeometry.ellipsoid(
					root, Vector3(side * 0.225, 1.07, -0.045), Vector3(0.065, 0.12, 0.16), hair
				)
			ModelGeometry.ellipsoid(
				root, Vector3(0, 1.075, -0.19), Vector3(0.235, 0.105, 0.07), hair
			)
		&"hot_dog":
			_hot_dog(root, band)
		&"construction_helmet":
			_helmet(root, fabric, band)
	StaticModelBatcher.merge_direct(root, [&"character_hat", id, colour])


static func _cone(root: Node3D, fabric: Material, band: Material) -> void:
	ModelGeometry.cushion(root, Vector3(0, 1.21, 0), Vector3(0.50, 0.045, 0.48), 0.018, fabric)
	ModelGeometry.cylinder(root, Vector3(0, 1.23, 0), Vector3(0, 1.81, 0), 0.23, fabric, 0.025)
	for height in [1.40, 1.58]:
		var radius := lerpf(0.23, 0.025, (height - 1.23) / 0.58)
		ModelGeometry.cylinder(
			root,
			Vector3(0, height, 0),
			Vector3(0, height + 0.065, 0),
			radius + 0.002,
			band,
			radius - 0.021
		)


static func _glasses(root: Node3D, frame: Material) -> void:
	for side in [-1.0, 1.0]:
		ModelGeometry.ring(root, Vector3(side * 0.069, 1.04, 0.265), 0.039, 0.049, frame)
		ModelGeometry.capsule(
			root,
			Vector3(side * 0.117, 1.04, 0.265),
			Vector3(side * 0.237, 1.05, 0.07),
			0.008,
			frame
		)
		ModelGeometry.capsule(
			root,
			Vector3(side * 0.237, 1.05, 0.07),
			Vector3(side * 0.245, 1.045, -0.06),
			0.008,
			frame
		)
	ModelGeometry.capsule(
		root, Vector3(-0.02, 1.04, 0.265), Vector3(0.02, 1.04, 0.265), 0.008, frame
	)


static func _hot_dog(root: Node3D, bun: Material) -> void:
	var sausage := ModelGeometry.material(Color("bd6350"), 0, 0.82)
	var mustard := ModelGeometry.material(Color("efc44f"), 0, 0.8)
	for side in [-1.0, 1.0]:
		ModelGeometry.capsule(
			root,
			Vector3(-0.26, 1.265, side * 0.085),
			Vector3(0.26, 1.265, side * 0.085),
			0.085,
			bun
		)
	ModelGeometry.capsule(root, Vector3(-0.27, 1.33, 0), Vector3(0.27, 1.33, 0), 0.073, sausage)
	for index in 8:
		var x := -0.24 + index * 0.06
		var a := Vector3(x, 1.398, -0.026 if index % 2 == 0 else 0.026)
		var b := Vector3(x + 0.06, 1.398, 0.026 if index % 2 == 0 else -0.026)
		ModelGeometry.capsule(root, a, b, 0.012, mustard)


static func _helmet(root: Node3D, fabric: Material, band: Material) -> void:
	ModelGeometry.ellipsoid(root, Vector3(0, 1.23, 0), Vector3(0.27, 0.165, 0.255), fabric)
	ModelGeometry.ellipsoid(root, Vector3(0, 1.19, 0.025), Vector3(0.31, 0.022, 0.30), fabric)
	ModelGeometry.cushion(root, Vector3(0, 1.39, 0), Vector3(0.055, 0.035, 0.31), 0.015, band)
	ModelGeometry.cushion(root, Vector3(0, 1.265, 0.248), Vector3(0.11, 0.065, 0.025), 0.01, band)
