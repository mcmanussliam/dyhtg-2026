extends RefCounted
## Pit support, routing, authored rotation and physical wall response.


func run(tree: SceneTree, check: Callable) -> void:
	var definition := load("res://game/stage/a_crack_in_the_floor.tres") as StageDefinition
	check.call(definition.validation_errors().is_empty(), "Pit map definition validates")
	check.call(definition.display_name == "A Crack in the Floor", "Pit map has its requested name")
	check.call(definition.hint == "Don’t fall", "Pit introduction has its hint")
	var config := MatchConfig.new()
	check.call(
		config.stages.any(func(map: StageDefinition) -> bool: return map.id == definition.id),
		"Default rotation includes pit map"
	)
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
