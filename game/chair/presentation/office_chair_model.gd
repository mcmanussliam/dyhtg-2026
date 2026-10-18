class_name OfficeChairModel
extends Node3D
## Five dual-wheel casters, a gas lift, and an upholstered suspended seat.
## The casters share one MultiMesh: three draw calls rather than fifteen per chair.

static var _caster_mesh: ArrayMesh

var seat_rig: Node3D
var _feet := PackedVector3Array()
var _caster_angles := PackedFloat32Array()  # Float32, like Node3D.rotation.
var _casters: MultiMesh


func build(tint: Color) -> void:
	var frame := ModelGeometry.material(Color("35474d"), 0.15)
	var rubber := ModelGeometry.material(Color("26353a"), 0, 0.9)
	var metal := ModelGeometry.material(Color("a8b6b7"), 0.7, 0.3)
	var upholstery := ModelGeometry.material(tint.darkened(0.53), 0, 0.88)
	var piping := ModelGeometry.material(tint.darkened(0.64), 0, 0.85)
	for index in 5:
		var angle := TAU * float(index) / 5.0
		var foot := Vector3(cos(angle) * 0.57, 0.13, sin(angle) * 0.57)
		ModelGeometry.capsule(self, Vector3(0, 0.21, 0), foot, 0.045, frame)
		_feet.append(foot)
		_caster_angles.append(-angle)
	ModelGeometry.cylinder(self, Vector3(0, 0.18, 0), Vector3(0, 0.39, 0), 0.075, frame)
	ModelGeometry.cylinder(self, Vector3(0, 0.32, 0), Vector3(0, 0.50, 0), 0.047, metal)
	seat_rig = Node3D.new()
	seat_rig.name = "SuspendedSeat"
	seat_rig.position.y = 0.49
	add_child(seat_rig)
	ModelGeometry.cushion(seat_rig, Vector3(0, -0.025, 0), Vector3(0.77, 0.10, 0.65), 0.035, frame)
	ModelGeometry.cushion(seat_rig, Vector3(0, 0.035, 0), Vector3(0.88, 0.14, 0.78), 0.06, piping)
	ModelGeometry.cushion(
		seat_rig, Vector3(0, 0.064, 0), Vector3(0.85, 0.12, 0.75), 0.05, upholstery
	)
	# Shaped shell, separate upholstery and a visible rear support structure.
	var back := ModelGeometry.curved_cushion(
		seat_rig, Vector3(0, 0.46, -0.36), Vector3(0.78, 0.70, 0.17), 0.075, frame
	)
	back.rotation.x = -0.10
	var pad := ModelGeometry.curved_cushion(
		seat_rig, Vector3(0, 0.47, -0.265), Vector3(0.70, 0.60, 0.115), 0.05, upholstery
	)
	pad.rotation.x = -0.10
	ModelGeometry.curved_cushion(
		seat_rig, Vector3(0, 0.25, -0.21), Vector3(0.58, 0.14, 0.08), 0.035, piping
	)
	ModelGeometry.capsule(seat_rig, Vector3(0, 0.08, -0.45), Vector3(0, 0.67, -0.47), 0.034, metal)
	ModelGeometry.cushion(
		seat_rig, Vector3(0, 0.70, -0.44), Vector3(0.25, 0.052, 0.035), 0.016, rubber
	)
	for side in [-1.0, 1.0]:
		ModelGeometry.capsule(
			seat_rig,
			Vector3(side * 0.43, 0, -0.08),
			Vector3(side * 0.48, 0.27, -0.06),
			0.025,
			metal
		)
		ModelGeometry.cushion(
			seat_rig, Vector3(side * 0.48, 0.29, 0.03), Vector3(0.13, 0.085, 0.43), 0.035, frame
		)
	ModelGeometry.capsule(
		seat_rig, Vector3(0.18, -0.06, 0), Vector3(0.48, -0.07, 0.10), 0.022, metal
	)

	# Each caster and the suspended seat retain their own animated pivot.
	StaticModelBatcher.merge_direct(self, [&"chair_base"])
	StaticModelBatcher.merge_direct(seat_rig, [&"chair_seat", tint])
	if _caster_mesh == null:
		_caster_mesh = _bake_caster(frame, rubber, metal)
	_casters = MultiMesh.new()
	_casters.transform_format = MultiMesh.TRANSFORM_3D
	_casters.mesh = _caster_mesh
	_casters.instance_count = _feet.size()
	for index in _feet.size():
		_place_caster(index)
	var renderer := MultiMeshInstance3D.new()
	renderer.name = "Casters"
	renderer.multimesh = _casters
	add_child(renderer)


static func _bake_caster(frame: Material, rubber: Material, metal: Material) -> ArrayMesh:
	var caster := Node3D.new()
	ModelGeometry.cushion(caster, Vector3(0, 0.015, 0), Vector3(0.14, 0.11, 0.08), 0.025, frame)
	for side in [-1.0, 1.0]:
		ModelGeometry.cylinder(
			caster,
			Vector3(side * 0.045, -0.035, 0),
			Vector3(side * 0.080, -0.035, 0),
			0.095,
			rubber
		)
	ModelGeometry.cylinder(
		caster, Vector3(-0.086, -0.035, 0), Vector3(0.086, -0.035, 0), 0.025, metal
	)
	var mesh := StaticModelBatcher.bake_direct(caster)
	caster.free()
	return mesh


func _place_caster(index: int) -> void:
	var basis := Basis.from_euler(Vector3(0, _caster_angles[index], 0))
	_casters.set_instance_transform(index, Transform3D(basis, _feet[index]))


func animate(
	delta: float, speed: float, local_motion: Vector2, compression: float, tilt: Vector2
) -> void:
	seat_rig.position.y = 0.49 - compression
	seat_rig.rotation.x = tilt.x
	seat_rig.rotation.z = tilt.y
	if speed > 0.03:
		var direction := atan2(local_motion.x, local_motion.y)
		for index in _caster_angles.size():
			_caster_angles[index] = lerp_angle(
				_caster_angles[index], direction, 1.0 - exp(-delta * 9.0)
			)
			_place_caster(index)
