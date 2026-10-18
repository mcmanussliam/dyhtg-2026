class_name BugFixer
extends Node3D
## The IT technician: a soft, round figure in blue overalls, a hi-vis vest and a yellow
## hard hat, carrying a toolbox and swinging a wrench. Limbs pivot so he strides while
## walking and hammers at the machine while repairing. Purely presentational.

var _legs: Array[Node3D] = []
var _arm_left: Node3D
var _arm_right: Node3D
var _sparks: Node3D
var _torso: Node3D


func build() -> void:
	var overalls := ModelGeometry.material(Color("2f6fb5"), 0.0, 0.7)
	var vest := ModelGeometry.material(Color("ff8a1f"), 0.0, 0.65)
	var stripe := ModelGeometry.material(Color("dfe6e8"), 0.3, 0.4)
	var skin := ModelGeometry.material(Color("ecd0b4"), 0.0, 0.8)
	var hat := ModelGeometry.material(Color("f5c518"), 0.1, 0.5)
	var boots := ModelGeometry.material(Color("2a2f35"), 0.1, 0.7)
	var black := ModelGeometry.material(Color("111418"), 0.0, 0.5)
	var steel := ModelGeometry.material(Color("aeb8c0"), 0.6, 0.4)
	var red := ModelGeometry.material(Color("d63a2d"), 0.1, 0.5)
	_torso = Node3D.new()
	_torso.name = "Torso"
	add_child(_torso)
	ModelGeometry.ellipsoid(_torso, Vector3(0, 0.80, 0), Vector3(0.30, 0.40, 0.26), overalls)
	ModelGeometry.ellipsoid(_torso, Vector3(0, 0.90, 0), Vector3(0.315, 0.30, 0.275), vest)
	ModelGeometry.cushion(_torso, Vector3(0, 0.98, 0.27), Vector3(0.5, 0.05, 0.03), 0.01, stripe)
	ModelGeometry.cushion(_torso, Vector3(0, 0.84, 0.27), Vector3(0.5, 0.05, 0.03), 0.01, stripe)
	ModelGeometry.ellipsoid(_torso, Vector3(0, 1.38, 0), Vector3(0.24, 0.25, 0.23), skin)
	for eye in [-1.0, 1.0]:
		ModelGeometry.ellipsoid(
			_torso, Vector3(eye * 0.085, 1.40, 0.205), Vector3(0.032, 0.046, 0.02), black
		)
	ModelGeometry.ellipsoid(_torso, Vector3(0, 1.58, 0), Vector3(0.27, 0.17, 0.27), hat)
	ModelGeometry.cushion(_torso, Vector3(0, 1.51, 0.1), Vector3(0.56, 0.035, 0.46), 0.015, hat)
	ModelGeometry.cushion(_torso, Vector3(0, 1.68, 0), Vector3(0.07, 0.05, 0.4), 0.02, hat)
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.14, 0.50, 0)
		add_child(leg)
		ModelGeometry.capsule(leg, Vector3.ZERO, Vector3(0, -0.36, 0), 0.115, overalls)
		ModelGeometry.ellipsoid(leg, Vector3(0, -0.46, 0.05), Vector3(0.12, 0.075, 0.17), boots)
		_legs.append(leg)
	_arm_left = _arm(-1.0, overalls, skin)
	ModelGeometry.cushion(_arm_left, Vector3(0, -0.54, 0.12), Vector3(0.32, 0.20, 0.18), 0.04, red)
	ModelGeometry.cushion(
		_arm_left, Vector3(0, -0.40, 0.12), Vector3(0.14, 0.03, 0.04), 0.012, black
	)
	_arm_right = _arm(1.0, overalls, skin)
	ModelGeometry.cylinder(_arm_right, Vector3(0, -0.38, 0.1), Vector3(0, -0.38, 0.66), 0.04, steel)
	ModelGeometry.cushion(
		_arm_right, Vector3(0, -0.38, 0.72), Vector3(0.20, 0.06, 0.14), 0.025, steel
	)
	_sparks = Node3D.new()
	_sparks.name = "Sparks"
	_sparks.position = Vector3(1, 1, 1)
	add_child(_sparks)
	var glow := ModelGeometry.material(Color("ffe45c"))
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for index in 4:
		ModelGeometry.ellipsoid(_sparks, Vector3.ZERO, Vector3.ONE * 0.05, glow)
	_sparks.hide()


func _arm(side: float, sleeve: Material, skin: Material) -> Node3D:
	var arm := Node3D.new()
	arm.position = Vector3(side * 0.36, 1.08, 0)
	add_child(arm)
	ModelGeometry.capsule(arm, Vector3.ZERO, Vector3(0, -0.34, 0.08), 0.09, sleeve)
	ModelGeometry.ellipsoid(arm, Vector3(0, -0.40, 0.1), Vector3(0.085, 0.085, 0.085), skin)
	return arm


func animate(time: float, walking: bool, fixing: bool) -> void:
	var stride := sin(time * 10.0) if walking else 0.0
	position.y = absf(stride) * 0.06
	_torso.rotation.z = stride * 0.05
	_legs[0].rotation.x = stride * 0.7
	_legs[1].rotation.x = -stride * 0.7
	_arm_left.rotation.x = -stride * 0.5
	if fixing:
		# Hammering at the machine: the wrench lifts and strikes, with sparks at the head.
		var hit := sin(time * 15.0)
		_arm_right.rotation.x = -1.35 + hit * 0.45
		_sparks.visible = true
		_sparks.position = Vector3(0.36, 0.78, 0.7)
		for index in _sparks.get_child_count():
			var spark := _sparks.get_child(index) as Node3D
			var phase := time * 9.0 + index * 1.7
			spark.position = Vector3(
				sin(phase * 1.3) * 0.16, fposmod(phase, 1.0) * 0.28, cos(phase * 1.1) * 0.12
			)
			spark.visible = hit > -0.3
	else:
		_arm_right.rotation.x = stride * 0.5
		_sparks.visible = false
