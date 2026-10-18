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
	&"construction_helmet",
	&"beanie",
	&"bucket_hat",
	&"crown",
	&"party_hat",
	&"wizard_hat",
	&"chef_hat",
	&"propeller_cap",
	&"headphones",
	&"bunny_ears",
	&"halo",
	&"sunglasses",
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
	"Construction Helmet",
	"Beanie",
	"Bucket Hat",
	"Crown",
	"Party Hat",
	"Wizard Hat",
	"Chef Hat",
	"Propeller Cap",
	"Headphones",
	"Bunny Ears",
	"Halo",
	"Sunglasses",
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
		&"beanie":
			_beanie(root, fabric, band)
		&"bucket_hat":
			_bucket_hat(root, fabric, band)
		&"crown":
			_crown(root, fabric)
		&"party_hat":
			_party_hat(root, fabric, band)
		&"wizard_hat":
			_wizard_hat(root, fabric, band)
		&"chef_hat":
			_chef_hat(root, fabric)
		&"propeller_cap":
			_propeller_cap(root, fabric, band)
		&"headphones":
			_headphones(root, fabric, hair)
		&"bunny_ears":
			_bunny_ears(root, fabric, band)
		&"halo":
			var gold := ModelGeometry.material(Color("f6dc72"), 0.2, 0.4)
			# Tilted forward so its front edge stays inside the fixed portrait framing.
			var halo := ModelGeometry.ring(root, Vector3(0, 1.345, 0), 0.15, 0.19, gold)
			halo.rotation = Vector3(0.35, 0, 0)
		&"sunglasses":
			_sunglasses(root, fabric, colour)
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


static func _beanie(root: Node3D, fabric: Material, band: Material) -> void:
	ModelGeometry.ellipsoid(root, Vector3(0, 1.17, 0), Vector3(0.276, 0.175, 0.262), fabric)
	ModelGeometry.cylinder(root, Vector3(0, 1.10, 0), Vector3(0, 1.18, 0), 0.272, band, 0.268)
	ModelGeometry.ellipsoid(root, Vector3(0, 1.36, 0), Vector3(0.065, 0.06, 0.065), band)


static func _bucket_hat(root: Node3D, fabric: Material, band: Material) -> void:
	ModelGeometry.cylinder(root, Vector3(0, 1.14, 0), Vector3(0, 1.20, 0), 0.37, fabric, 0.26)
	ModelGeometry.cylinder(root, Vector3(0, 1.19, 0), Vector3(0, 1.34, 0), 0.252, fabric, 0.225)
	ModelGeometry.ellipsoid(root, Vector3(0, 1.34, 0), Vector3(0.225, 0.04, 0.225), fabric)
	ModelGeometry.cylinder(root, Vector3(0, 1.20, 0), Vector3(0, 1.245, 0), 0.256, band, 0.250)


static func _crown(root: Node3D, velvet: Material) -> void:
	var gold := ModelGeometry.material(Color("e9b949"), 0.3, 0.42)
	ModelGeometry.ellipsoid(root, Vector3(0, 1.23, 0), Vector3(0.205, 0.13, 0.195), velvet)
	ModelGeometry.cylinder(root, Vector3(0, 1.19, 0), Vector3(0, 1.29, 0), 0.215, gold, 0.225)
	for index in 6:
		var angle := TAU * index / 6.0
		var base := Vector3(sin(angle) * 0.214, 1.285, cos(angle) * 0.214)
		ModelGeometry.cylinder(root, base, base + Vector3(0, 0.09, 0), 0.04, gold, 0.004)
		ModelGeometry.ellipsoid(root, base + Vector3(0, 0.1, 0), Vector3.ONE * 0.016, gold)
	ModelGeometry.ellipsoid(root, Vector3(0, 1.24, 0.225), Vector3(0.03, 0.03, 0.012), velvet)


static func _party_hat(root: Node3D, fabric: Material, band: Material) -> void:
	ModelGeometry.cylinder(root, Vector3(0, 1.20, 0), Vector3(0, 1.64, 0), 0.17, fabric, 0.008)
	for height in [1.27, 1.40, 1.53]:
		var radius := lerpf(0.17, 0.008, (height - 1.20) / 0.44)
		ModelGeometry.cylinder(
			root,
			Vector3(0, height, 0),
			Vector3(0, height + 0.05, 0),
			radius + 0.003,
			band,
			radius - 0.015
		)
	ModelGeometry.ellipsoid(root, Vector3(0, 1.645, 0), Vector3.ONE * 0.045, band)


static func _wizard_hat(root: Node3D, fabric: Material, band: Material) -> void:
	var star := ModelGeometry.material(Color("f6dc72"), 0.1, 0.5)
	ModelGeometry.ellipsoid(root, Vector3(0, 1.19, 0), Vector3(0.38, 0.022, 0.36), fabric)
	ModelGeometry.cylinder(root, Vector3(0, 1.19, 0), Vector3(0, 1.52, 0), 0.23, fabric, 0.10)
	ModelGeometry.cylinder(root, Vector3(0, 1.20, 0), Vector3(0, 1.26, 0), 0.234, band, 0.216)
	ModelGeometry.ellipsoid(root, Vector3(0, 1.52, 0), Vector3.ONE * 0.10, fabric)
	ModelGeometry.cylinder(root, Vector3(0, 1.52, 0), Vector3(0, 1.70, -0.12), 0.10, fabric, 0.01)
	for point in [Vector3(0.10, 1.36, 0.17), Vector3(-0.12, 1.43, 0.11), Vector3(0.03, 1.47, 0.13)]:
		ModelGeometry.ellipsoid(root, point, Vector3(0.022, 0.022, 0.012), star)


static func _chef_hat(root: Node3D, band: Material) -> void:
	var white := ModelGeometry.material(Color("f2efe6"), 0, 0.95)
	ModelGeometry.cylinder(root, Vector3(0, 1.15, 0), Vector3(0, 1.31, 0), 0.25, white, 0.262)
	ModelGeometry.cylinder(root, Vector3(0, 1.16, 0), Vector3(0, 1.205, 0), 0.254, band, 0.257)
	ModelGeometry.ellipsoid(root, Vector3(0, 1.40, 0), Vector3(0.27, 0.15, 0.26), white)
	for index in 5:
		var angle := TAU * index / 5.0 + 0.3
		ModelGeometry.ellipsoid(
			root,
			Vector3(sin(angle) * 0.15, 1.44, cos(angle) * 0.14),
			Vector3(0.14, 0.12, 0.14),
			white
		)


static func _propeller_cap(root: Node3D, fabric: Material, band: Material) -> void:
	ModelGeometry.ellipsoid(root, Vector3(0, 1.20, 0), Vector3(0.26, 0.15, 0.25), fabric)
	ModelGeometry.cushion(root, Vector3(0, 1.20, 0.23), Vector3(0.40, 0.032, 0.28), 0.015, fabric)
	for index in 4:
		var angle := TAU * index / 4.0
		ModelGeometry.capsule(
			root,
			Vector3(sin(angle) * 0.03, 1.348, cos(angle) * 0.03),
			Vector3(sin(angle) * 0.215, 1.255, cos(angle) * 0.205),
			0.012,
			band
		)
	ModelGeometry.cylinder(root, Vector3(0, 1.34, 0), Vector3(0, 1.42, 0), 0.012, band)
	var blade := ModelGeometry.material(Color("e86a5c"), 0, 0.7)
	for side in [-1.0, 1.0]:
		var part := ModelGeometry.ellipsoid(
			root, Vector3(side * 0.10, 1.425, 0), Vector3(0.10, 0.008, 0.03), blade
		)
		part.rotation.x = side * 0.3
	ModelGeometry.ellipsoid(root, Vector3(0, 1.43, 0), Vector3.ONE * 0.022, band)


static func _headphones(root: Node3D, fabric: Material, cushion: Material) -> void:
	var points := PackedVector3Array()
	for index in 9:
		var angle := PI * index / 8.0
		points.append(Vector3(cos(angle) * 0.29, 1.03 + sin(angle) * 0.285, -0.01))
	for index in points.size() - 1:
		ModelGeometry.capsule(root, points[index], points[index + 1], 0.024, fabric)
	for side in [-1.0, 1.0]:
		ModelGeometry.cylinder(
			root,
			Vector3(side * 0.255, 1.01, -0.01),
			Vector3(side * 0.30, 1.01, -0.01),
			0.09,
			cushion
		)
		ModelGeometry.cylinder(
			root,
			Vector3(side * 0.295, 1.01, -0.01),
			Vector3(side * 0.335, 1.01, -0.01),
			0.098,
			fabric
		)


static func _bunny_ears(root: Node3D, fabric: Material, inner: Material) -> void:
	var points := PackedVector3Array()
	for index in 7:
		var angle := PI * (0.12 + 0.76 * index / 6.0)
		points.append(Vector3(cos(angle) * 0.275, 1.005 + sin(angle) * 0.285, 0.03))
	for index in points.size() - 1:
		ModelGeometry.capsule(root, points[index], points[index + 1], 0.016, fabric)
	for side in [-1.0, 1.0]:
		var ear := ModelGeometry.ellipsoid(
			root, Vector3(side * 0.10, 1.45, 0.02), Vector3(0.06, 0.18, 0.032), fabric
		)
		ear.rotation.z = -side * 0.2
		var lining := ModelGeometry.ellipsoid(
			root, Vector3(side * 0.104, 1.45, 0.044), Vector3(0.034, 0.13, 0.014), inner
		)
		lining.rotation.z = -side * 0.2


static func _sunglasses(root: Node3D, frame: Material, colour: Color) -> void:
	var lens := ModelGeometry.material(CosmeticColours.fabric(colour).darkened(0.85), 0.2, 0.25)
	for side in [-1.0, 1.0]:
		ModelGeometry.ellipsoid(
			root, Vector3(side * 0.072, 1.04, 0.262), Vector3(0.058, 0.042, 0.014), lens
		)
		ModelGeometry.ring(root, Vector3(side * 0.072, 1.04, 0.266), 0.05, 0.062, frame).scale = (Vector3(
			1.05, 1, 0.8
		))
		ModelGeometry.capsule(
			root,
			Vector3(side * 0.13, 1.045, 0.262),
			Vector3(side * 0.237, 1.05, 0.07),
			0.009,
			frame
		)
		ModelGeometry.capsule(
			root,
			Vector3(side * 0.237, 1.05, 0.07),
			Vector3(side * 0.245, 1.045, -0.06),
			0.009,
			frame
		)
	ModelGeometry.capsule(
		root, Vector3(-0.024, 1.045, 0.27), Vector3(0.024, 1.045, 0.27), 0.009, frame
	)
