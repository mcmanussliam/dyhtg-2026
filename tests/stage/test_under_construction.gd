extends RefCounted
## Wall openings, telegraphed diggers, swept hits, furniture smashing and round lifetime.

const DEFINITION = preload("res://game/stage/under_construction/under_construction.tres")
const STEP := 1.0 / 60


func run(tree: SceneTree, check: Callable) -> void:
	var stage := DEFINITION.scene.instantiate() as UnderConstructionStage
	tree.root.add_child(stage)
	var world := Node3D.new()
	tree.root.add_child(world)
	stage.create_presentation(world, 1.0 / RenderStyle.PIXELS_PER_UNIT)
	await tree.physics_frame
	await tree.physics_frame
	check.call(
		stage.has_support(stage.to_global(stage.center)), "Construction office has a solid floor"
	)
	check.call(
		stage.get_node("Furniture/ToolTrolley").is_movable(), "Tool trolley yields to chairs"
	)
	check.call(
		(
			stage.get_node("Furniture/RearSiteFence").rotation == 0
			and is_equal_approx(stage.get_node("Furniture/SideSiteFence").rotation, PI / 2)
		),
		"Construction fences align with room walls rather than creating diagonal pockets"
	)
	for side in 4:
		check.call(
			stage.wall_sections(side).size() == 3,
			"Every wall has two smashed openings between solid sections"
		)
	for lane in 4:
		var ends := stage.lane_endpoints(lane)
		check.call(
			(
				(is_equal_approx(ends[0].y, ends[1].y) and lane < 2)
				or (is_equal_approx(ends[0].x, ends[1].x) and lane >= 2)
			),
			"Lanes 0-1 run horizontally and lanes 2-3 vertically"
		)
		for point in ends:
			var direction := (ends[1] - ends[0]).normalized()
			var query := PhysicsRayQueryParameters2D.create(
				point - direction * 40, point + direction * 40, 1
			)
			check.call(
				not stage.get_world_2d().direct_space_state.intersect_ray(query).is_empty(),
				"Chairs cannot leave through an opening"
			)
	check.call(
		world.get_node_or_null("WallOpenings") != null, "Each opening has a black cut backing"
	)
	_test_clear_openings(stage, check)
	var vehicle := stage.vehicles[0]
	stage.tick_hazards(30)
	check.call(
		vehicle.phase == ConstructionVehicle.Phase.DORMANT, "Black intro never sends diggers"
	)
	stage.set_render_warmup(true)
	stage.set_render_warmup(false)
	check.call(
		vehicle.phase == ConstructionVehicle.Phase.DORMANT, "Warmup leaves inactive diggers dormant"
	)
	stage.start_round()
	stage.tick_hazards(stage.first_warning + 0.01)
	var active: ConstructionVehicle
	for actor in stage.vehicles:
		if actor.phase == ConstructionVehicle.Phase.WARNING:
			active = actor
	check.call(active != null, "A digger announces its lane after the opening delay")
	var ends := stage.lane_endpoints(active.lane)
	var lane_middle := (ends[0] + ends[1]) * 0.5
	check.call(not stage.is_safe(lane_middle), "AI sees the announced path")
	check.call(stage.is_safe(stage.safe_target(lane_middle)), "AI receives a safe lateral escape")
	check.call(
		active.get("_lane").visible and not active.get("_model").visible,
		"The path is highlighted while the digger waits out of sight"
	)
	stage.tick_hazards(active.warning_seconds - 0.05)
	check.call(active.phase == ConstructionVehicle.Phase.WARNING, "Entire path warning is honoured")
	stage.tick_hazards(0.1)
	check.call(
		active.phase == ConstructionVehicle.Phase.CHARGING and active.get("_model").visible,
		"The digger drives in once the warning ends"
	)
	var start := active.position
	var crossed := 0.0
	var lane_visible := true
	for frame in 150:
		stage.tick_hazards(STEP)
		if active.phase == ConstructionVehicle.Phase.CHARGING:
			crossed = maxf(crossed, active.position.distance_to(start))
			lane_visible = lane_visible and active.get("_lane").visible
	check.call(
		crossed > stage.half_size.x * 2 and lane_visible,
		"The digger crosses the room with its path marked throughout"
	)
	check.call(
		active.phase == ConstructionVehicle.Phase.DORMANT and not active.get("_lane").visible,
		"A digger that has driven out returns to the pool"
	)
	_test_lane_rotation(stage, check)
	var travelled := active.position
	stage.stop_round()
	stage.tick_hazards(10)
	check.call(active.position == travelled, "Round results freeze diggers")
	world.queue_free()
	stage.queue_free()
	await tree.process_frame
	await _test_knockout(tree, check)


func _test_knockout(tree: SceneTree, check: Callable) -> void:
	var state := MatchState.new()
	state.configure(MatchConfig.new())
	var round_scene := RoundController.new()
	round_scene.configure(state.participants, DEFINITION, 1, 5)
	tree.root.add_child(round_scene)
	round_scene.set_physics_process(false)
	round_scene.begin_live()
	var stage := round_scene.stage as UnderConstructionStage
	var vehicle := stage.vehicles[0]
	var chair := round_scene.chairs[0]
	chair.stop_drive()
	vehicle.warn(0, true, 1000.0)
	vehicle.phase = ConstructionVehicle.Phase.CHARGING
	var ends := stage.lane_endpoints(0)
	chair.position = (ends[0] + ends[1]) * 0.5 + Vector2(0, 400)
	vehicle.position = (ends[0] + ends[1]) * 0.5 - vehicle.direction * 200
	vehicle.call("_sweep_chairs", vehicle.position - vehicle.direction * 40, STEP)
	check.call(chair.knockout_velocity == Vector3.ZERO, "A chair outside the lane is not hit")
	chair.position = vehicle.position + vehicle.direction * 40
	vehicle.call("_sweep_chairs", vehicle.position - vehicle.direction * 40, STEP)
	check.call(
		chair.knockout_velocity.y == 16 and chair.knockout_velocity.x > 40,
		"Swept envelope catches a player and prepares a massive launch"
	)
	var hits: Array[int] = []
	stage.elimination_requested.connect(func(seat: int, _reason: StringName): hits.append(seat))
	vehicle.call("_sweep_chairs", vehicle.position - vehicle.direction * 40, STEP)
	check.call(hits.is_empty(), "One digger cannot repeatedly eliminate the same seat")
	round_scene._commit_eliminations()
	check.call(
		not chair.active and chair.falling and round_scene.phase == RoundController.Phase.RESOLVING,
		"Digger knockout uses shared elimination and last-survivor rules"
	)
	var fixed: OfficeProp
	for prop in stage.get_node("Furniture").get_children():
		if prop is OfficeProp and not prop.is_movable():
			fixed = prop
			break
	check.call(fixed != null, "The map has fixed furniture to flatten")
	vehicle.position = fixed.global_position - vehicle.direction * 100
	vehicle.call("_sweep_props", vehicle.position - vehicle.direction * 20)
	check.call(fixed.collision_layer == 0, "A digger flattens fixed furniture out of its footprint")
	round_scene.queue_free()
	await tree.process_frame


func _test_clear_openings(stage: UnderConstructionStage, check: Callable) -> void:
	var obstructed := ""
	for lane in 4:
		var ends := stage.lane_endpoints(lane)
		for end in 2:
			var mouth := stage.to_local(ends[end])
			var inward := (stage.to_local(ends[1 - end]) - mouth).normalized()
			var across := inward.orthogonal()
			var half_width := UnderConstructionStage.WALL_CUT * 0.5 + 6
			for prop in stage.get_node("Furniture").get_children():
				if not prop is OfficeProp:
					continue
				var shape := prop.get_node("CollisionShape2D") as CollisionShape2D
				if not shape.shape is RectangleShape2D:
					continue
				for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					var local := stage.to_local(shape.to_global(shape.shape.size * 0.5 * corner))
					var forward := (local - mouth).dot(inward)
					var lateral := (local - mouth).dot(across)
					if forward < 110 and absf(lateral) < half_width:
						# Corners alone can miss a long prop spanning the mouth.
						obstructed = "%s at lane %d" % [prop.name, lane]
				var centre := stage.to_local(prop.global_position)
				var extent: float = shape.shape.size.length() * 0.35
				if (
					(centre - mouth).dot(inward) < 110
					and (centre - mouth).dot(inward) > -extent
					and absf((centre - mouth).dot(across)) < half_width - extent * 0.5
				):
					obstructed = "%s at lane %d" % [prop.name, lane]
	check.call(obstructed == "", "No furniture stands in front of an opening: " + obstructed)
	var blocked := ""
	for slot in stage.wall_detail_slots():
		var reach := 70.0 if slot[3] == &"window" else (45.0 if slot[3] == &"door" else 20.0)
		for lane in [2, 3]:
			var hole_x: float = stage.center.x + UnderConstructionStage.LANE_OFFSETS[lane]
			if absf(slot[1] - hole_x) < UnderConstructionStage.WALL_CUT * 0.5 + reach:
				blocked = "%s over lane %d" % [slot[0], lane]
	check.call(blocked == "", "No window, door or clock sits over an opening: " + blocked)


func _test_lane_rotation(stage: UnderConstructionStage, check: Callable) -> void:
	var lanes := {}
	var headings := {}
	for index in 24:
		for actor in stage.vehicles:
			actor.phase = ConstructionVehicle.Phase.DORMANT
		stage.call("_dispatch")
		for actor in stage.vehicles:
			if actor.phase == ConstructionVehicle.Phase.WARNING:
				lanes[actor.lane] = true
				headings[actor.forward] = true
	check.call(lanes.size() >= 3, "Digger paths are heavily randomised across the lanes")
	check.call(headings.size() == 2, "Diggers come from both ends of a lane")
	for actor in stage.vehicles:
		actor.phase = ConstructionVehicle.Phase.DORMANT
	stage.set("_elapsed", 0.0)
	var early: float = stage.current_interval()
	stage.set("_elapsed", stage.escalation_seconds * 0.4)
	var middle: float = stage.current_interval()
	stage.set("_elapsed", stage.escalation_seconds)
	var late: float = stage.current_interval()
	check.call(late <= 0.4 and late < early * 0.15, "Arrivals end up close to the trains' pace")
	check.call(middle < early * 0.45, "Arrivals speed up quickly early on")
	# Several diggers may share a lane only in one direction.
	for actor in stage.vehicles:
		actor.phase = ConstructionVehicle.Phase.DORMANT
	var ready := true
	for index in 8:
		stage.call("_dispatch")
		for actor in stage.vehicles:
			if actor.phase == ConstructionVehicle.Phase.WARNING:
				actor.phase = ConstructionVehicle.Phase.CHARGING
	var by_lane := {}
	for actor in stage.vehicles:
		if actor.phase == ConstructionVehicle.Phase.CHARGING:
			if by_lane.has(actor.lane) and by_lane[actor.lane] != actor.forward:
				ready = false
			by_lane[actor.lane] = actor.forward
	check.call(ready, "Diggers sharing a lane never head towards each other")
