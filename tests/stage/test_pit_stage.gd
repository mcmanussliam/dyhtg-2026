extends RefCounted
## Pit support, routing, authored rotation and physical wall response.


func run(tree: SceneTree, check: Callable) -> void:
	var definition := (
		load("res://game/stage/a_crack_in_the_floor/a_crack_in_the_floor.tres") as StageDefinition
	)
	var config := MatchConfig.new()
	config.player_count = 2
	config.wins_needed = 5
	var stage := definition.scene.instantiate() as ArenaStage
	tree.root.add_child(stage)
	check.call(not stage.has_support(Vector2(640, 422)), "Pit center has no floor")
	check.call(
		not stage.has_support(Vector2(640 + stage.hole_radius - 10, 422)),
		"Inside pit rim has no floor"
	)
	check.call(
		stage.has_support(Vector2(640 + stage.hole_radius + 10, 422)),
		"Outside pit rim supports chairs"
	)
	check.call(
		stage.has_support_near(Vector2(640 + stage.hole_radius - 10, 422), 30),
		"Partial rim overhang remains supported"
	)
	check.call(
		not stage.has_support_near(Vector2(640, 422), 30), "Whole chair in pit loses support"
	)
	check.call(stage.has_support(Vector2(1190, 800)), "Room corner retains its floor")
	await tree.physics_frame
	var spawn_shape := CapsuleShape2D.new()
	spawn_shape.radius = 23 * stage.content_scale
	spawn_shape.height = 60 * stage.content_scale
	for count in range(2, 5):
		for index in count:
			check.call(
				stage.is_safe(stage.spawn_pose(index, count).origin, 65),
				"Pit spawn has safe clearance"
			)
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = spawn_shape
			query.transform = stage.spawn_pose(index, count) * Transform2D(PI / 2, Vector2.ZERO)
			query.collision_mask = 1
			check.call(
				stage.get_world_2d().direct_space_state.intersect_shape(query).is_empty(),
				"Authored furniture leaves spawn footprints clear"
			)
	var goal := stage.navigation_target(Vector2(350, 422), Vector2(930, 422), 80)
	var closest := Geometry2D.get_closest_point_to_segment(
		Vector2(640, 422), Vector2(350, 422), goal
	)
	check.call(
		closest.distance_to(Vector2(640, 422)) > 170,
		"Navigation routes around pit instead of across it"
	)
	check.call(
		stage.is_safe(stage.safe_target(Vector2(640, 422), 300), 100),
		"Oversized safety inset remains feasible"
	)
	check.call(
		not stage.is_path_safe(Vector2(235, 422), Vector2(1045, 422), 40),
		"Safe endpoints do not permit a route across the pit"
	)
	var recovery := stage.recovery_target(Vector2(235, 422), Vector2(1045, 422), 300)
	check.call(recovery.x < 640, "Pit recovery stays on the chair's current bank")
	check.call(
		stage.is_path_safe(Vector2(235, 422), recovery, 40),
		"Pit recovery route remains over supported floor"
	)
	var outline: PackedVector2Array = stage.hole_outline()
	var min_radius := INF
	var max_radius := 0.0
	var consistent := true
	for point in outline:
		min_radius = minf(min_radius, point.length())
		max_radius = maxf(max_radius, point.length())
		consistent = (
			consistent and not stage.has_support(stage.to_global(Vector2(640, 422) + point * 0.98))
		)
		consistent = (
			consistent and stage.has_support(stage.to_global(Vector2(640, 422) + point * 1.02))
		)
	check.call(max_radius - min_radius > 5, "Pit has distinct fractured chips")
	check.call(consistent, "Support follows each rendered chipped rim vertex")
	check.call(
		stage.has_support(Vector2(640 + stage.half_size.x - 20, 422)),
		"Office floor reaches its authored perimeter"
	)
	var world := Node3D.new()
	tree.root.add_child(world)
	stage.create_presentation(world, 1.0 / RenderStyle.PIXELS_PER_UNIT)
	check.call(
		world.has_node("OfficeFloor/SurfaceCollision"), "Office floor has native fall collision"
	)
	check.call(world.has_node("PitWalls/SurfaceCollision"), "Pit sides have native fall collision")
	check.call(
		world.has_node("WorkWindowA") and world.has_node("WorkWindowB"),
		"Office windows mount on the back wall"
	)
	check.call(
		world.has_node("OfficeDoor") and world.has_node("OfficeClock"),
		"Office door and clock are present"
	)
	var chair := load("res://game/chair/chair.tscn").instantiate() as Chair
	tree.root.add_child(chair)
	chair.position = Vector2(640 + stage.half_size.x - 60, 420)
	chair.freeze = false
	chair.drive_enabled = false
	chair.linear_velocity = Vector2(450, 0)
	var bounced := false
	for frame in 40:
		await tree.physics_frame
		if chair.linear_velocity.x < -50:
			bounced = true
	check.call(bounced, "Outer office wall physically bounces chairs back")
	chair.queue_free()
	world.queue_free()
	stage.queue_free()
	await tree.process_frame
