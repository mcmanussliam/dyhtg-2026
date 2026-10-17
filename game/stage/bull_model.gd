class_name BullModel
extends Node3D
## Original smooth bull, assembled from shared native meshes with flat materials.

var _rig: Node3D
var _legs: Array[Node3D] = []
var _stars: Array[MeshInstance3D] = []


func build() -> void:
	_rig = Node3D.new()
	add_child(_rig)
	var fixed := Node3D.new()
	_rig.add_child(fixed)
	var coat := ModelGeometry.material(Color("754d3b"), 0, 0.9)
	var dark := ModelGeometry.material(Color("382a27"), 0, 0.92)
	var muzzle := ModelGeometry.material(Color("a57964"), 0, 0.95)
	var horn := ModelGeometry.material(Color("e6dcc3"), 0, 0.8)
	var black := ModelGeometry.material(Color("111817"), 0, 0.8)
	ModelGeometry.ellipsoid(fixed, Vector3(0, 1.0, -0.12), Vector3(0.63, 0.62, 1.06), coat)
	ModelGeometry.ellipsoid(fixed, Vector3(0, 1.13, 0.48), Vector3(0.65, 0.67, 0.60), coat)
	ModelGeometry.ellipsoid(fixed, Vector3(0, 1.02, 0.96), Vector3(0.51, 0.48, 0.50), coat)
	ModelGeometry.ellipsoid(fixed, Vector3(0, 0.85, 1.34), Vector3(0.44, 0.26, 0.24), muzzle)
	ModelGeometry.ellipsoid(fixed, Vector3(0, 1.42, 0.99), Vector3(0.35, 0.17, 0.29), dark)
	for side in [-1.0, 1.0]:
		ModelGeometry.ellipsoid(
			fixed, Vector3(side * 0.35, 1.17, 1.26), Vector3(0.065, 0.07, 0.045), black
		)
		ModelGeometry.ellipsoid(
			fixed, Vector3(side * 0.17, 0.91, 1.555), Vector3(0.06, 0.045, 0.025), dark
		)
		ModelGeometry.ellipsoid(
			fixed, Vector3(side * 0.57, 1.29, 0.83), Vector3(0.27, 0.09, 0.16), coat
		)
		var points := [
			Vector3(side * 0.40, 1.42, 0.99),
			Vector3(side * 0.73, 1.51, 1.01),
			Vector3(side * 0.85, 1.78, 1.12),
			Vector3(side * 0.77, 1.94, 1.24)
		]
		for index in 3:
			ModelGeometry.cylinder(
				fixed,
				points[index],
				points[index + 1],
				0.12 - index * 0.035,
				horn,
				maxf(0.012, 0.085 - index * 0.035)
			)
		for z in [-0.75, 0.48]:
			var leg := Node3D.new()
			leg.position = Vector3(side * 0.43, 0.65, z)
			_rig.add_child(leg)
			ModelGeometry.capsule(leg, Vector3.ZERO, Vector3(0, -0.45, 0), 0.16, coat)
			ModelGeometry.cushion(
				leg, Vector3(0, -0.51, 0.035), Vector3(0.33, 0.24, 0.40), 0.07, dark
			)
			_legs.append(leg)
			StaticModelBatcher.batch(leg)
	ModelGeometry.capsule(fixed, Vector3(0, 1.1, -1.05), Vector3(0.16, 0.65, -1.55), 0.055, coat)
	ModelGeometry.ellipsoid(fixed, Vector3(0.16, 0.62, -1.55), Vector3(0.10, 0.16, 0.10), dark)
	StaticModelBatcher.batch(fixed)
	var gold := ModelGeometry.material(Color("eac76f"), 0.15)
	for index in 3:
		var star := ModelGeometry.ellipsoid(self, Vector3.ZERO, Vector3(0.11, 0.06, 0.11), gold)
		star.visible = false
		_stars.append(star)


func animate(_delta: float, time: float, charging: bool, stunned: bool, winding: bool) -> void:
	_rig.rotation.x = 0.12 if charging else (0.06 if winding else 0.0)
	_rig.rotation.z = sin(time * 12) * 0.07 if stunned else 0.0
	_rig.position.y = absf(sin(time * 17)) * 0.06 if charging else 0.0
	for index in _legs.size():
		_legs[index].rotation.x = sin(time * 17 + index * PI) * 0.48 if charging else 0.0
	if winding:
		_legs[1].rotation.x = sin(time * 11) * 0.22
	for index in _stars.size():
		var angle := time * 3 + index * TAU / 3
		_stars[index].visible = stunned
		_stars[index].position = Vector3(
			cos(angle) * 0.48, 2.15 + sin(time * 6) * 0.05, sin(angle) * 0.48 + 0.6
		)
