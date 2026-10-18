extends RefCounted
## Real stage clock, swept occupancy, telegraph/support agreement and native holes.

const DEFINITION = preload("res://game/stage/faulty_floors/faulty_floors.tres")


func run(tree: SceneTree, check: Callable) -> void:
	var stage := DEFINITION.scene.instantiate() as FaultyFloorsStage
	tree.root.add_child(stage)
	stage.position = Vector2(35, -24)
	stage.rotation = 0.12
	for count in range(2, 11):
		var safe := true
		for pose in SpawnLayout.poses(stage, count):
			safe = safe and stage.is_spawn_safe(pose.origin, 34 * stage.content_scale + 5)
		check.call(safe, "Faulty Floors has safe starts for %d players" % count)
	var chair := preload("res://game/chair/chair.tscn").instantiate() as Chair
	chair.get_node("Visuals").free()
	chair.resize_for_stage(stage.content_scale)
	chair.configure(0, Color.WHITE, Vector2.RIGHT)
	chair.freeze = true
	tree.root.add_child(chair)
	var index := 5 * stage.grid.columns + 5
	var center := stage.grid.cell_rect(index).get_center()
	chair.position = stage.to_global(center)
	var actors: Array[Chair] = [chair]
	stage.bind_participants(actors)
	var world := Node3D.new()
	tree.root.add_child(world)
	stage.create_presentation(world, 1.0 / RenderStyle.PIXELS_PER_UNIT)
	await tree.physics_frame
	stage.tick_hazards(30)
	check.call(stage.grid.pending.is_empty(), "Black intro cannot damage the floor")
	stage.set_render_warmup(true)
	stage.set_render_warmup(false)
	check.call(stage.grid.revision == 0, "Render warmup leaves floor state untouched")
	stage.start_round()
	stage.tick_hazards(stage.opening_grace - 0.01)
	check.call(stage.grid.pending.is_empty(), "Opening grace protects the gradual jet startup")
	stage.tick_hazards(0.02)
	check.call(
		stage.grid.states[index] == FaultyFloorGrid.State.WARNING,
		"Occupied panel warns before collapsing"
	)
	check.call(
		stage.has_support(chair.position) and not stage.is_safe(chair.position),
		"Warning panel stays physically solid while informing AI of danger"
	)
	var exit := stage.safe_target(chair.position, 30)
	check.call(
		stage.is_safe(exit) and stage.is_path_safe(chair.position, exit, 10),
		"AI can leave its own warning panel without being vetoed by its starting point"
	)
	stage.tick_hazards(stage.warning_duration - 0.01)
	check.call(stage.has_support(chair.position), "Complete warning duration preserves support")
	stage.tick_hazards(0.02)
	check.call(not stage.has_support(chair.position), "Expired panel leaves a real hole")
	check.call(chair.active, "Stage does not eliminate before shared native fall confirmation")
	await tree.physics_frame
	check.call(not _floor_hit(world, chair.position), "Native floor collider opens with support")
	var next := stage.to_global(center + Vector2(stage.grid.cell_size.x, 0))
	check.call(
		stage.has_support(next) and _floor_hit(world, next),
		"Adjacent panel and native support remain intact after translated/rotated collapse"
	)
	var opposite := stage.to_global(center - Vector2(stage.grid.cell_size.x, 0))
	check.call(
		not stage.is_path_safe(next, opposite, 10), "Navigation rejects shortcuts through holes"
	)
	var waypoint := stage.navigation_target(next, opposite, 10)
	check.call(
		waypoint != next and stage.is_path_safe(next, waypoint, 10),
		"AI finds an adjacent-panel detour around the missing panel"
	)
	var debris := world.find_children("FallingFloorPanel*", "RigidBody3D", true, false)
	check.call(
		debris.size() == 1 and debris[0].linear_velocity.y < 0,
		"One full-depth slab drops under native gravity"
	)
	var end := center + Vector2(stage.grid.cell_size.x * 4, 0)
	chair.position = stage.to_global(end)
	stage.tick_hazards(0.02)
	var swept := true
	for step in range(1, 5):
		swept = swept and stage.grid.states[index + step] == FaultyFloorGrid.State.WARNING
	check.call(swept, "High-speed travel marks every crossed panel, not just the endpoint")
	var warnings := stage.grid.pending.duplicate()
	stage.stop_round()
	stage.tick_hazards(20)
	check.call(stage.grid.pending == warnings, "Results freeze pending collapses")
	check.call(debris[0].freeze, "Results freeze already falling panels")
	world.queue_free()
	chair.queue_free()
	stage.queue_free()
	await tree.process_frame
	var fresh := DEFINITION.scene.instantiate() as FaultyFloorsStage
	tree.root.add_child(fresh)
	check.call(
		fresh.grid.pending.is_empty() and fresh.grid.states.count(FaultyFloorGrid.State.GONE) == 0,
		"New rounds restore every panel without shared state"
	)
	fresh.queue_free()
	await tree.process_frame
	await _test_native_fall(tree, check)


func _floor_hit(world: Node3D, point: Vector2) -> bool:
	var location := Vector3(point.x, 0, point.y) / RenderStyle.PIXELS_PER_UNIT
	var query := PhysicsRayQueryParameters3D.create(location + Vector3.UP, location + Vector3.DOWN)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider.is_in_group("stage_floor")


func _test_native_fall(tree: SceneTree, check: Callable) -> void:
	var state := MatchState.new()
	var duel := MatchConfig.new()
	duel.player_count = 2
	state.configure(duel)
	var round_scene := RoundController.new()
	round_scene.configure(state.participants, DEFINITION, 1, 5)
	tree.root.add_child(round_scene)
	round_scene.set_physics_process(false)
	var stage := round_scene.stage as FaultyFloorsStage
	var chair := round_scene.chairs[0]
	var point := stage.grid.cell_rect(65).get_center()
	chair.position = stage.to_global(point)
	round_scene.chairs[1].position = stage.to_global(stage.grid.cell_rect(78).get_center())
	stage.bind_participants(round_scene.chairs)
	round_scene.begin_live()
	for actor in round_scene.chairs:
		actor.stop_drive()
	for frame in ceili((stage.opening_grace + stage.warning_duration + 2) * 60):
		round_scene._physics_process(1.0 / 60)
		await tree.physics_frame
	check.call(
		not chair.active and chair.falling,
		"Staying on a collapsing panel causes a confirmed native fall"
	)
	check.call(round_scene.phase != RoundController.Phase.LIVE, "Confirmed fall resolves the round")
	round_scene.queue_free()
	await tree.process_frame
