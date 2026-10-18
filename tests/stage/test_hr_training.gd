extends RefCounted
## Crossing timing, actual wall gaps, high-speed hits and shared round lifetime.

const DEFINITION = preload("res://game/stage/hr_training/hr_training.tres")


func run(tree: SceneTree, check: Callable) -> void:
	var stage := DEFINITION.scene.instantiate() as OfficeStage
	tree.root.add_child(stage)
	check.call(stage.has_support(stage.to_global(stage.center)), "HR Training has a solid floor")
	var poses := SpawnLayout.poses(stage, 10)
	var safe_spawns := poses.size() == 10
	for pose in poses:
		safe_spawns = safe_spawns and stage.is_spawn_safe(pose.origin, 34 * stage.content_scale + 5)
	check.call(safe_spawns, "Ten seats fit in furniture-free bays outside the rails")
	await tree.physics_frame
	await tree.physics_frame
	for side in 4:
		var sections: Array[Rect2] = stage.wall_sections(side)
		var horizontal := side % 2 == 0
		check.call(
			sections.size() == (1 if horizontal else 4), "Only side walls have train openings"
		)
		if not horizontal:
			for lane in 3:
				var ends: PackedVector2Array = stage.lane_endpoints(lane)
				check.call(is_equal_approx(ends[0].y, ends[1].y), "Every train route is horizontal")
				var point := ends[1 if side == 1 else 0]
				var query := PhysicsRayQueryParameters2D.create(
					point - Vector2(40, 0), point + Vector2(40, 0), 1
				)
				check.call(
					not stage.get_world_2d().direct_space_state.intersect_ray(query).is_empty(),
					"Players cannot camp inside a tunnel mouth"
				)
		var solid := stage.to_global(sections[1 if not horizontal else 0].get_center())
		var normal := Vector2.DOWN if horizontal else Vector2.RIGHT
		var wall_query := PhysicsRayQueryParameters2D.create(
			solid - normal * 40, solid + normal * 40, 1
		)
		check.call(
			not stage.get_world_2d().direct_space_state.intersect_ray(wall_query).is_empty(),
			"Office walls remain solid"
		)
	for lane in [0, 2]:
		var reachable_edge := stage.half_size.y - 12 - 23 * stage.content_scale
		var outer_gap: float = reachable_edge - absf(stage.TRACK_OFFSETS[lane])
		check.call(
			outer_gap < TrainingTrain.WIDTH * 0.5 + 23 * stage.content_scale,
			"Outer trains catch even a chair pressed against the wall"
		)
	var clear_tracks := true
	for polygon in SpawnLayout._blockers(stage):
		var low := INF
		var high := -INF
		for point in polygon:
			low = minf(low, point.y)
			high = maxf(high, point.y)
		for lane in 3:
			var track_y: float = stage.lane_endpoints(lane)[0].y
			if (
				low <= track_y + TrainingTrain.WIDTH * 0.5
				and high >= track_y - TrainingTrain.WIDTH * 0.5
			):
				clear_tracks = false
	check.call(
		clear_tracks and stage.get_node("Furniture").get_child_count() >= 20,
		"Expanded office dressing stays outside every train envelope"
	)
	var world := Node3D.new()
	tree.root.add_child(world)
	stage.create_presentation(world, 1.0 / RenderStyle.PIXELS_PER_UNIT)
	var lights: Array = stage.get("_signals")
	check.call(lights.size() == 6, "All six side entrances have warning lights")
	var train: TrainingTrain = stage.trains[0]
	stage.tick_hazards(60)
	check.call(
		train.phase == TrainingTrain.Phase.COOLDOWN and is_zero_approx(stage.get("_elapsed")),
		"Black intro never advances the train schedule"
	)
	stage.set_render_warmup(true)
	stage.set_render_warmup(false)
	check.call(
		is_zero_approx(stage.get("_elapsed")) and not train.get("_model").visible,
		"Train GPU warmup leaves hazard time and visibility unchanged"
	)
	stage.start_round()
	for lane in [0, 2]:
		train.warn(lane, true)
		var wall_side := -1 if lane == 0 else 1
		var corner := stage.to_global(
			stage.center + Vector2(0, wall_side * (stage.half_size.y - 13))
		)
		check.call(
			stage.is_safe(stage.safe_target(corner, 0)),
			"AI escapes an outer train towards the room rather than into the wall"
		)
	train.phase = TrainingTrain.Phase.COOLDOWN
	stage.set("_next_arrival", 3.5)
	stage.tick_hazards(3.51)
	check.call(
		train.phase == TrainingTrain.Phase.WARNING and train.lane == 0,
		"First train warns after a safe startup interval"
	)
	var on: StandardMaterial3D = stage.get("_signal_on")
	check.call(
		(
			lights[0].material_override == on
			and lights[1].material_override == on
			and lights[2].material_override != on
		),
		"Both ends of the announced track flash, unrelated tracks stay dark"
	)
	stage.tick_hazards(0.20)
	check.call(lights[0].material_override != on, "Red warning flashes rather than remaining solid")
	var danger: Vector2 = (stage.lane_endpoints(0)[0] + stage.lane_endpoints(0)[1]) * 0.5
	check.call(
		not stage.is_safe(danger) and stage.is_safe(stage.safe_target(danger)),
		"AI receives the telegraphed lane and a safe lateral escape"
	)
	stage.tick_hazards(1.61)
	check.call(
		train.phase == TrainingTrain.Phase.CROSSING and train.get("_model").visible,
		"Train enters only after the complete warning"
	)
	var chair := load("res://game/chair/chair.tscn").instantiate() as Chair
	chair.configure(0, Color.WHITE, Vector2.RIGHT)
	tree.root.add_child(chair)
	chair.prepare_round()
	chair.position = danger - Vector2(340, 0)
	chair.freeze = true
	var roster: Array[Chair] = [chair]
	stage.bind_participants(roster)
	var hits: Array[StringName] = []
	stage.elimination_requested.connect(
		func(_seat: int, reason: StringName) -> void: hits.append(reason)
	)
	stage.tick_hazards(0.8)
	check.call(hits == [&"train"], "Train sweeps detect a chair passed between physics endpoints")
	stage.tick_hazards(0.05)
	check.call(hits.size() == 1, "One crossing cannot repeatedly eliminate a seat")
	check.call(
		chair.knockout_velocity.x > 50 and chair.knockout_velocity.y >= 15,
		"Train prepares a physical flying knockout"
	)
	chair.eliminate(&"train")
	check.call(
		not chair.active and chair.falling, "Train kills use the shared native falling presentation"
	)
	var frozen_position := train.position
	var frozen_clock: float = stage.get("_elapsed")
	stage.stop_round()
	stage.tick_hazards(30)
	check.call(
		train.position == frozen_position and is_equal_approx(stage.get("_elapsed"), frozen_clock),
		"Results stop train motion and escalation"
	)
	check.call(
		train.get("_model").collision_layer == 0 and lights[0].material_override != on,
		"Stopped hazards disable collision and warning lights"
	)
	stage.start_round()
	train.tick(3)
	check.call(
		train.phase == TrainingTrain.Phase.COOLDOWN,
		"Exited trains become reusable independently of other tracks"
	)
	check.call(train.length >= 1000, "Long trains retain their full crossing length")
	stage.set("_elapsed", 0.0)
	var early: float = stage.crossing_interval()
	stage.set("_elapsed", stage.escalation_seconds * 0.5)
	var middle: float = stage.crossing_interval()
	stage.set("_elapsed", stage.escalation_seconds * 10)
	var late: float = stage.crossing_interval()
	check.call(
		early > middle and middle > late and is_equal_approx(late, stage.minimum_interval),
		"Intervals shorten gradually and stay bounded"
	)
	check.call(
		is_equal_approx(train.warning_seconds, 1.8), "Escalation preserves the full dodge warning"
	)
	chair.free()
	stage.free()
	world.free()
	await tree.process_frame
	var fresh := DEFINITION.scene.instantiate() as OfficeStage
	tree.root.add_child(fresh)
	check.call(
		(
			fresh.trains[0].lane == -1
			and fresh.trains[0].phase == TrainingTrain.Phase.COOLDOWN
			and is_zero_approx(fresh.get("_elapsed"))
		),
		"New rounds reset the complete crossing state"
	)
	fresh.free()
	await tree.process_frame
	await _check_concurrency(tree, check)
	await _check_round(tree, check)
	await _check_furniture_launch(tree, check)


func _check_concurrency(tree: SceneTree, check: Callable) -> void:
	var stage := DEFINITION.scene.instantiate() as OfficeStage
	tree.root.add_child(stage)
	var world := Node3D.new()
	tree.root.add_child(world)
	stage.create_presentation(world, 1.0 / RenderStyle.PIXELS_PER_UNIT)
	check.call(
		stage.trains.size() == stage.MAX_TRAINS,
		"Concurrent train pool is allocated once before play"
	)
	var reference_mesh: Mesh = stage.trains[0].get("_model").get_child(0).mesh
	var shared_meshes := true
	for actor: TrainingTrain in stage.trains:
		shared_meshes = shared_meshes and actor.get("_model").get_child(0).mesh == reference_mesh
	check.call(shared_meshes, "Pooled trains share immutable render geometry")
	stage.start_round()
	stage.set("_elapsed", stage.escalation_seconds)
	stage.set("_next_arrival", 0.0)
	var peak_crossings := 0
	var prepared_while_crossing := false
	var safe_spacing := true
	var full_warnings := true
	var peak_departures := 0
	var warnings: Dictionary = {}
	var crossed: Dictionary = {}
	var first_lanes: Array[int] = []
	var first_directions: Array[Vector2] = []
	for frame in 900:
		stage.tick_hazards(1.0 / 60)
		var moving := 0
		var pending := 0
		for actor: TrainingTrain in stage.trains:
			if actor.phase == TrainingTrain.Phase.WARNING and not warnings.has(actor.departure_id):
				warnings[actor.departure_id] = frame
				if first_lanes.size() < 6:
					first_lanes.append(actor.lane)
					first_directions.append(actor.direction)
			if actor.phase in [TrainingTrain.Phase.WARNING, TrainingTrain.Phase.WAITING]:
				pending += 1
			if actor.phase != TrainingTrain.Phase.CROSSING:
				continue
			moving += 1
			if not crossed.has(actor.departure_id):
				full_warnings = full_warnings and warnings.has(actor.departure_id)
				if warnings.has(actor.departure_id):
					full_warnings = (
						full_warnings
						and (
							(frame - int(warnings[actor.departure_id])) / 60.0
							>= actor.warning_seconds - 0.02
						)
					)
				crossed[actor.departure_id] = true
			for other: TrainingTrain in stage.trains:
				if (
					other == actor
					or other.phase != TrainingTrain.Phase.CROSSING
					or other.lane != actor.lane
				):
					continue
				safe_spacing = safe_spacing and actor.direction.dot(other.direction) > 0.99
				safe_spacing = (
					safe_spacing
					and (
						actor.position.distance_to(other.position)
						>= (actor.length + other.length) * 0.5 + 79
					)
				)
		peak_crossings = maxi(peak_crossings, moving)
		prepared_while_crossing = prepared_while_crossing or (moving > 0 and pending > 0)
		peak_departures = maxi(peak_departures, stage.get("_crossings"))
	check.call(peak_crossings >= 3, "Three tracks can run trains simultaneously")
	check.call(prepared_while_crossing, "New trains warn while earlier trains still cross")
	check.call(
		first_lanes == [0, 2, 1, 0, 2, 1],
		"Independent arrivals retain top, bottom, middle rotation"
	)
	check.call(
		first_directions[0].dot(first_directions[3]) < -0.99,
		"Each track alternates entrance direction"
	)
	check.call(full_warnings, "Every concurrent departure completes its full warning")
	check.call(safe_spacing, "No opposing or overlapping trains share a track")
	check.call(
		peak_departures > 20 and stage.trains.size() == stage.MAX_TRAINS,
		"Frequent arrivals reuse a bounded pool over sustained play"
	)
	var stopped_positions: Array[Vector2] = []
	for actor: TrainingTrain in stage.trains:
		stopped_positions.append(actor.position)
	stage.stop_round()
	stage.tick_hazards(60)
	var stopped := true
	for index in stage.trains.size():
		var actor: TrainingTrain = stage.trains[index]
		stopped = (
			stopped
			and actor.position == stopped_positions[index]
			and actor.get("_model").collision_layer == 0
		)
	check.call(stopped, "Results freeze every pooled train and disable every train collider")
	stage.free()
	world.free()
	await tree.process_frame


func _check_round(tree: SceneTree, check: Callable) -> void:
	var state := MatchState.new()
	var duel := MatchConfig.new()
	duel.player_count = 2
	state.configure(duel)
	var round_scene := load("res://game/round/round.tscn").instantiate() as RoundController
	round_scene.configure(state.participants, DEFINITION, 1, 5)
	tree.root.add_child(round_scene)
	round_scene.set_physics_process(false)
	round_scene._physics_process(round_scene.intro_duration)
	var victim := round_scene.chairs[0]
	victim.set_knockout_launch(Vector3(57, 16, 0), Vector3(0, 4, -10))
	round_scene.stage.elimination_requested.emit(0, &"train")
	round_scene._commit_eliminations()
	check.call(
		(
			round_scene.phase == RoundController.Phase.RESOLVING
			and not victim.active
			and victim.falling
		),
		"Train eliminations resolve scores through the normal last-survivor flow"
	)
	round_scene.free()
	await tree.process_frame


func _check_furniture_launch(tree: SceneTree, check: Callable) -> void:
	for forward in [true, false]:
		var stage := DEFINITION.scene.instantiate() as OfficeStage
		tree.root.add_child(stage)
		var world := Node3D.new()
		tree.root.add_child(world)
		stage.create_presentation(world, 1.0 / RenderStyle.PIXELS_PER_UNIT)
		stage.start_round()
		var prop := stage.get_node("Furniture/UpperFrontChair4") as OfficeProp
		prop.global_position = stage.to_global(stage.center)
		for frame in 2:
			await tree.physics_frame
		var train: TrainingTrain = stage.trains[0]
		train.warn(1, forward)
		train.begin_crossing()
		train.tick(0.9)
		var native := prop.get("_motion").get("_model") as RigidBody3D
		check.call(native != null, "Train transfers loose furniture into native 3D physics")
		if native == null:
			stage.free()
			world.free()
			continue
		check.call(
			native.linear_velocity.x * train.direction.x > 50 and native.linear_velocity.y >= 15,
			"Train launches furniture upward and in its travel direction"
		)
		check.call(native.angular_velocity.length() > 5, "Launched furniture tumbles")
		check.call(
			prop.collision_layer == 0 and prop.get("freeze") == true,
			"Launched furniture leaves no frozen planar collider"
		)
		var origin := native.position
		for frame in 30:
			await tree.physics_frame
		check.call(
			(
				(native.position.x - origin.x) * train.direction.x > 10
				and native.position.y > origin.y + 2.5
			),
			"Native furniture launch clears the train and office walls"
		)
		train.tick(0.01)
		check.call(
			prop.get("_motion").get("_model") == native,
			"The same train cannot create repeated furniture launches"
		)
		stage.stop_round()
		check.call(native.freeze, "Results freeze launched furniture with the round")
		stage.free()
		world.free()
		await tree.process_frame
