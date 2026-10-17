extends RefCounted
## Fractures change one authoritative boundary, rendered floor and native collisions together.


func run(tree: SceneTree, check: Callable) -> void:
	for path in [
		"res://game/stage/a_floor_in_the_crack.tscn", "res://game/stage/a_crack_in_the_floor.tscn"
	]:
		var stage := load(path).instantiate() as ArenaStage
		tree.root.add_child(stage)
		var world := Node3D.new()
		tree.root.add_child(world)
		stage.create_presentation(world, 1.0 / RenderStyle.PIXELS_PER_UNIT)
		var edge: CrumblingEdge = stage.get("_erosion")
		var initial := edge.outline.duplicate()
		stage.tick_hazards(30)
		check.call(
			edge.elapsed == 0 and edge.outline == initial,
			"Title never advances crumbling: %s" % stage.name
		)
		stage.start_round()
		for frame in 156:
			stage.tick_hazards(0.1)
		check.call(
			edge.revision == 0 and not edge.warning.is_empty(),
			"Fracture is telegraphed before support disappears: %s" % stage.name
		)
		check.call(
			world.get_node("FractureWarning").visible,
			"Warning appears on the actual floor: %s" % stage.name
		)
		for frame in 8:
			stage.tick_hazards(0.1)
		check.call(
			edge.revision == 1,
			"First chipped section detaches after the grace period: %s" % stage.name
		)
		var expanding := stage is PitOfficeStage
		var monotonic := true
		var smallest := INF
		var largest := -INF
		var deepest := 0.0
		for index in initial.size():
			var change := edge.outline[index].length() - initial[index].length()
			monotonic = monotonic and (change >= -0.01 if expanding else change <= 0.01)
			var scale: float = edge.outline[index].length() / ColumnGeometry.RIM[index].length()
			smallest = minf(smallest, scale)
			largest = maxf(largest, scale)
			deepest = maxf(deepest, absf(change))
		check.call(
			monotonic and edge.outline != initial,
			"Floor only recedes with asymmetric chips: %s" % stage.name
		)
		check.call(
			deepest > 30 and deepest <= 55.1 and largest - smallest <= 55.1,
			"Larger sections retain a bounded rough-circle silhouette: %s" % stage.name
		)
		var floor: MeshInstance3D = (
			world.get_node("OfficeFloor/Surface")
			if expanding
			else world.get_node("CirclePlatform/FloorSurface")
		)
		var collider: CollisionShape3D = (
			world.get_node("OfficeFloor/SurfaceCollision")
			if expanding
			else world.get_node("CirclePlatform/ColumnCollision")
		)
		check.call(
			collider.shape != null and floor.mesh.get_surface_count() > 0,
			"Changed floor retains native collision: %s" % stage.name
		)
		var supported := true
		var vertices := floor.mesh.get_faces()
		for index in range(0, vertices.size(), 3):
			var center := (vertices[index] + vertices[index + 1] + vertices[index + 2]) / 3
			center = floor.to_global(center)
			supported = (
				supported
				and stage.has_support(Vector2(center.x, center.z) * RenderStyle.PIXELS_PER_UNIT)
			)
		check.call(supported, "Every rendered floor triangle agrees with support: %s" % stage.name)
		var pieces := world.find_children("FallingFloorChunk*", "RigidBody3D", false, false)
		check.call(
			not pieces.is_empty(), "Detached chips become native falling debris: %s" % stage.name
		)
		var piece := pieces[0] as RigidBody3D
		var mesh := piece.get_child(0) as MeshInstance3D
		check.call(
			mesh.mesh.get_aabb().size.y >= (3.99 if expanding else 23.99),
			"Detached section includes the full visible foundation: %s" % stage.name
		)
		var top := mesh.mesh.surface_get_material(0) as ShaderMaterial
		var sides := mesh.mesh.surface_get_material(1) as ShaderMaterial
		check.call(
			(
				top != null
				and sides != null
				and top.shader == sides.shader
				and (
					top.get_shader_parameter("fade_start")
					== sides.get_shader_parameter("fade_start")
				)
				and top.get_shader_parameter("fade_end") == sides.get_shader_parameter("fade_end")
				and top.get_shader_parameter("wall_colour") == Color("2e4055")
			),
			"Blue tops use the same void fade as the column sides: %s" % stage.name
		)
		var height := piece.position.y
		for frame in 20:
			await tree.physics_frame
		check.call(piece.position.y < height - 0.1, "Detached debris really falls: %s" % stage.name)
		stage.stop_round()
		var stopped := edge.elapsed
		stage.tick_hazards(20)
		check.call(
			edge.elapsed == stopped and piece.freeze,
			"Results stop fracture clocks and debris: %s" % stage.name
		)
		stage.start_round()
		for frame in 1100:
			stage.tick_hazards(0.1)
		check.call(
			edge.revision > 30, "Fractures keep progressing through long rounds: %s" % stage.name
		)
		check.call(
			world.find_children("FallingFloorChunk*", "RigidBody3D", false, false).size() <= 36,
			"Debris count stays bounded during long rounds: %s" % stage.name
		)
		stage.queue_free()
		world.queue_free()
		await tree.process_frame

	await _test_partial_furniture_release(tree, check)


func _test_partial_furniture_release(tree: SceneTree, check: Callable) -> void:
	var stage := preload("res://game/stage/a_floor_in_the_crack.tscn").instantiate() as ArenaStage
	tree.root.add_child(stage)
	var world := Node3D.new()
	tree.root.add_child(world)
	stage.create_presentation(world, 1.0 / RenderStyle.PIXELS_PER_UNIT)
	stage.start_round()
	for path in ["office_bookshelf", "office_task_chair"]:
		var prop := load("res://game/props/%s.tscn" % path).instantiate() as OfficeProp
		stage.add_child(prop)
		prop.position = Vector2(640, 422)
		prop.create_presentation(world, 1.0 / RenderStyle.PIXELS_PER_UNIT)
		var source := prop.get_node("CollisionShape2D") as CollisionShape2D
		var width := source.shape.get_rect().size.x
		var empty_chip: Array[PackedVector2Array] = [
			PackedVector2Array([Vector2(200, 200), Vector2(220, 200), Vector2(220, 220)])
		]
		prop.release_for_fracture(stage, empty_chip, Vector2(640, 422))
		check.call(prop.collision_layer != 0, "Distant floor chips leave %s supported" % path)
		if prop.is_movable():
			prop.set("sleeping", true)
		# Touch only a small side of the footprint; its centre still has solid floor.
		var touching: Array[PackedVector2Array] = [
			PackedVector2Array(
				[
					Vector2(width * 0.4, -2),
					Vector2(width, -2),
					Vector2(width, 2),
					Vector2(width * 0.4, 2)
				]
			)
		]
		prop.release_for_fracture(stage, touching, Vector2(640, 422))
		var body: Node3D = prop.get("_presentation")
		if prop.is_movable():
			body = prop.get("_motion").get("_model")
		check.call(
			body is RigidBody3D and prop.collision_layer == 0,
			"Partial edge contact releases even sleeping %s into native 3D" % path
		)
		if body is RigidBody3D:
			check.call(
				not body.find_children("*", "CollisionShape3D", true, false).is_empty(),
				"Released %s retains real support colliders" % path
			)
			for frame in 20:
				await tree.physics_frame
			check.call(
				body.position.y > -0.2, "Remaining floor can still support released %s" % path
			)
		body.queue_free()
		prop.queue_free()
		await tree.process_frame
	stage.queue_free()
	world.queue_free()
	await tree.process_frame
