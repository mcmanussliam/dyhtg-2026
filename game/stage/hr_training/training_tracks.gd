class_name TrainingTracks
extends Node3D
## Decorative rails stay flush: the authoritative floor remains one smooth surface.
## Portal surrounds match the gaps shared by the 2D and 3D office walls.


func build(stage: OfficeStage, units: float) -> void:
	var rail := ModelGeometry.material(Color("718087"), 0.6, 0.55)
	var sleeper := ModelGeometry.material(Color("35434b"), 0, 0.95)
	var ties := BoxMesh.new()
	ties.size = Vector3(2.55, 0.025, 0.18)
	for lane in stage.TRACK_OFFSETS.size():
		var ends: PackedVector2Array = stage.lane_endpoints(lane)
		var distance := ends[0].distance_to(ends[1]) * units
		var direction := (ends[1] - ends[0]).normalized()
		var midpoint := (ends[0] + ends[1]) * 0.5 * units
		var track := Node3D.new()
		add_child(track)
		track.position = Vector3(midpoint.x, 0.01, midpoint.y)
		track.rotation.y = PI / 2 - direction.angle()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(0.085, 0.035, distance)
		for side in [-1.0, 1.0]:
			ModelGeometry.instance(track, rail_mesh, Vector3(side * 0.92, 0.035, 0), rail)
		var count := ceili(distance / 0.65)
		for index in count:
			ModelGeometry.instance(
				track,
				ties,
				Vector3(0, 0, (index + 0.5) * distance / count - distance * 0.5),
				sleeper
			)
	StaticModelBatcher.batch(self)


static func portal(
	parent: Node3D, point: Vector2, inward: Vector2, units: float, portal_width: float
) -> MeshInstance3D:
	var root := Node3D.new()
	root.name = "TrainPortal"
	parent.add_child(root)
	root.position = Vector3(point.x * units, 0, point.y * units)
	root.rotation.y = atan2(inward.x, inward.y)
	var surround := ModelGeometry.material(Color("697278"), 0.1)
	var trim := ModelGeometry.material(Color("c2ad68"), 0.1)
	var dark := ModelGeometry.material(Color("141b22"))
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var width := portal_width * units
	for side in [-1.0, 1.0]:
		ModelGeometry.cushion(
			root,
			Vector3(side * (width * 0.5 - 0.1), 1.85, 0),
			Vector3(0.2, 3.7, 0.6),
			0.04,
			surround
		)
		for mark in 4:
			ModelGeometry.cushion(
				root,
				Vector3(side * (width * 0.5 - 0.1), 0.35 + mark * 0.28, 0.31),
				Vector3(0.205, 0.12, 0.03),
				0.01,
				trim
			)
	ModelGeometry.cushion(
		root, Vector3(0, 3.75, 0), Vector3(width + 0.12, 0.25, 0.62), 0.05, surround
	)
	# Inward-facing black plane reads as a tunnel from inside the room, but its
	# culled back face cannot hide players when the camera views the front wall.
	var opening := PlaneMesh.new()
	opening.size = Vector2(width - 0.2, 3.6)
	var mouth := ModelGeometry.instance(root, opening, Vector3(0, 1.8, -0.32), dark)
	mouth.rotation.x = PI / 2
	mouth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bulbs := Node3D.new()
	root.add_child(bulbs)
	for side in [-1.0, 1.0]:
		ModelGeometry.cushion(
			root,
			Vector3(-width * 0.5 - 0.25, 3.0, side * 0.28),
			Vector3(0.55, 0.7, 0.3),
			0.08,
			surround
		)
		ModelGeometry.ellipsoid(
			bulbs, Vector3(-width * 0.5 - 0.25, 3.04, side * 0.47), Vector3(0.19, 0.24, 0.13), dark
		)
	# Both faces are one mesh/material so every signal stays legible from the camera.
	var light := ModelGeometry.instance(
		root, StaticModelBatcher.bake_direct(bulbs), Vector3.ZERO, dark
	)
	bulbs.free()
	light.name = "WarningLight"
	# Merge the fixed surround without consuming the animated signal mesh.
	root.remove_child(light)
	ModelGeometry.instance(root, StaticModelBatcher.bake_direct(root), Vector3.ZERO, null)
	root.add_child(light)
	return light
