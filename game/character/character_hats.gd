class_name CharacterHats
extends RefCounted
## Stable cosmetic IDs and shared native geometry, independent of gameplay physics.

const IDS: Array[StringName] = [&"none", &"traffic_cone", &"top_hat", &"cap"]
const NAMES := ["None", "Traffic Cone", "Top Hat", "Cap"]


static func build(parent: Node3D, id: StringName, colour: Color) -> void:
	if id not in IDS or id == &"none":
		return
	var root := Node3D.new()
	root.name = "Hat"
	parent.add_child(root)
	var fabric := ModelGeometry.material(CosmeticColours.fabric(colour), 0, 0.9)
	var band := ModelGeometry.material(CosmeticColours.fabric(colour).lightened(0.16), 0, 0.95)
	match id:
		&"traffic_cone":
			ModelGeometry.cushion(
				root, Vector3(0, 1.21, 0), Vector3(0.56, 0.045, 0.52), 0.018, fabric
			)
			ModelGeometry.cylinder(
				root, Vector3(0, 1.23, 0), Vector3(0, 1.81, 0), 0.23, fabric, 0.025
			)
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
		&"top_hat":
			ModelGeometry.ellipsoid(root, Vector3(0, 1.21, 0), Vector3(0.35, 0.028, 0.30), fabric)
			ModelGeometry.cylinder(root, Vector3(0, 1.22, 0), Vector3(0, 1.63, 0), 0.23, fabric)
			ModelGeometry.cylinder(root, Vector3(0, 1.25, 0), Vector3(0, 1.32, 0), 0.234, band)
		&"cap":
			ModelGeometry.ellipsoid(root, Vector3(0, 1.20, 0), Vector3(0.27, 0.15, 0.255), fabric)
			ModelGeometry.cushion(
				root, Vector3(0, 1.20, 0.24), Vector3(0.47, 0.04, 0.34), 0.018, fabric
			)
			ModelGeometry.ellipsoid(root, Vector3(0, 1.35, 0), Vector3(0.035, 0.02, 0.035), band)
	StaticModelBatcher.batch(root)
