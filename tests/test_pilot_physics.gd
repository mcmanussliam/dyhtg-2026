extends RefCounted
## Seeded real rigid-body playtests; no rendering or direction-setting shortcuts.

const CHAIR = preload("res://game/chair/chair.tscn")
const CIRCLE = preload("res://game/stage/a_floor_in_the_crack.tscn")
const STEP = 1.0 / 60.0
const FRAMES = 1200


func run(tree: SceneTree, check: Callable) -> void:
	await _simulate(tree, check, 4107, 1)
	for scenario in [{"seed": 71431, "count": 3}, {"seed": 9827, "count": 4}]:
		await _simulate(tree, check, scenario.seed, scenario.count)


func _simulate(tree: SceneTree, check: Callable, random_seed: int, count: int) -> void:
	var arena := Node2D.new()
	tree.root.add_child(arena)
	var stage := CIRCLE.instantiate() as ArenaStage
	arena.add_child(stage)
	stage.start_round()
	var chairs: Array[Chair] = []
	var pilots: Array[PracticePilot] = []
	var metrics := {
		"contacts": 0,
		"spray_hits": 0,
		"ringouts": 0,
		"rounds": 1,
		"first_ringout_seconds": -1.0,
		"mean_round_seconds": 0.0,
		"longest_round_seconds": 0.0,
		"impact_impulse": 0.0,
	}
	var round_start_frame := 0
	var completed_round_frames := 0
	var travel: Array[float] = []
	var displacement: Array[float] = []
	var spin_arc: Array[float] = []
	var max_spin: Array[float] = []
	var bounded := true
	var targets := {}
	for index in count:
		var chair := CHAIR.instantiate() as Chair
		chair.get_node("Visuals").free()
		chair.configure(index, Color.WHITE, Vector2.RIGHT)
		arena.add_child(chair)
		chairs.append(chair)
		pilots.append(PracticePilot.new(random_seed + index * 31))
		travel.append(0.0)
		displacement.append(0.0)
		spin_arc.append(0.0)
		max_spin.append(0.0)
		chair.body_entered.connect(
			func(other: Node) -> void:
				if other is Chair:
					metrics.contacts += 1
		)
		chair.bumped.connect(
			func(impulse: Vector2) -> void: metrics.impact_impulse += impulse.length()
		)
	_reset_poses(chairs, stage)
	await tree.physics_frame
	var spray := SpraySystem.new()
	for frame in FRAMES:
		var previous_positions: Array[Vector2] = []
		var previous_angles: Array[float] = []
		for index in count:
			var chair := chairs[index]
			previous_positions.append(chair.position)
			previous_angles.append(chair.rotation)
			if chair.active:
				chair.command = pilots[index].sample_on_stage(chair, chairs, stage, STEP)
				var chosen = pilots[index].get("target_seat")
				if chosen is int and chosen >= 0 and chosen != index:
					targets[Vector2i(index, chosen)] = true
				chair.step(STEP)
		for source in chairs:
			spray.apply(source, chairs, STEP)
			for target in chairs:
				var offset := target.position - source.position
				if (
					source.active
					and target.active
					and source != target
					and offset.length() > 0.01
					and offset.length() <= source.spray_reach
					and (
						Vector2.from_angle(source.aim_angle).dot(offset.normalized())
						>= cos(deg_to_rad(source.tuning.half_angle_degrees))
					)
				):
					metrics.spray_hits += 1
		await tree.physics_frame
		var alive := 0
		for index in count:
			var chair := chairs[index]
			if not chair.active:
				continue
			travel[index] += previous_positions[index].distance_to(chair.position)
			displacement[index] = maxf(
				displacement[index],
				chair.position.distance_to(stage.spawn_pose(index, count).origin)
			)
			var turn := wrapf(chair.rotation - previous_angles[index], -PI, PI)
			if absf(chair.angular_velocity) < 0.45 or turn * spin_arc[index] < 0.0:
				spin_arc[index] = 0.0
			spin_arc[index] += turn
			max_spin[index] = maxf(max_spin[index], absf(spin_arc[index]))
			bounded = bounded and chair.linear_velocity.length() <= chair.tuning.maximum_speed + 1.0
			bounded = bounded and absf(chair.angular_velocity) <= chair.tuning.maximum_spin + 0.1
			if not stage.has_support(chair.global_position):
				chair.eliminate(&"fall")
				metrics.ringouts += 1
				if metrics.first_ringout_seconds < 0.0:
					metrics.first_ringout_seconds = (frame + 1) * STEP
			else:
				alive += 1
		if alive < 2 and count > 1:
			metrics.longest_round_seconds = maxf(
				metrics.longest_round_seconds, (frame + 1 - round_start_frame) * STEP
			)
			completed_round_frames += frame + 1 - round_start_frame
			round_start_frame = frame + 1
			metrics.rounds += 1
			_reset_poses(chairs, stage)
			for index in count:
				pilots[index] = PracticePilot.new(random_seed + index * 31 + metrics.rounds * 1009)
			spin_arc.fill(0.0)
	metrics.mean_round_seconds = (
		float(completed_round_frames) * STEP / float(metrics.rounds - 1)
		if metrics.rounds > 1
		else FRAMES * STEP
	)
	metrics.longest_round_seconds = maxf(
		metrics.longest_round_seconds, (FRAMES - round_start_frame) * STEP
	)
	print(
		(
			"AI physics seed=%d seats=%d %s travel=%s displacement=%s spin_turns=%s targets=%d"
			% [
				random_seed,
				count,
				metrics,
				travel,
				displacement,
				max_spin.map(func(value: float) -> float: return snappedf(value / TAU, 0.01)),
				targets.size()
			]
		)
	)
	check.call(bounded, "AI physics obeys linear and angular speed limits (%d)" % random_seed)
	for index in count:
		check.call(
			travel[index] > 350.0,
			"AI seat %d travels through real physics (%d)" % [index, random_seed]
		)
		check.call(
			displacement[index] > 95.0,
			"AI seat %d leaves its spawn area (%d)" % [index, random_seed]
		)
		check.call(
			max_spin[index] < TAU * 1.5,
			"AI seat %d avoids prolonged continuous spinning (%d)" % [index, random_seed]
		)
	if count == 1:
		check.call(metrics.ringouts == 0, "Unopposed AI survives twenty seconds on stage")
	else:
		check.call(
			metrics.first_ringout_seconds < 0.0 or metrics.first_ringout_seconds >= 3.0,
			"AI combat avoids immediate opening ring-outs (%d)" % random_seed
		)
		check.call(
			metrics.mean_round_seconds >= 4.0,
			"AI fights last beyond the opening approach (%d)" % random_seed
		)
		check.call(
			metrics.contacts + metrics.spray_hits > 0,
			"AI players physically interact (%d)" % random_seed
		)
		check.call(
			metrics.impact_impulse > 0.0,
			"AI chair collisions generate real impact impulse (%d)" % random_seed
		)
		check.call(
			targets.size() >= count, "AI players select other AI opponents (%d)" % random_seed
		)
	arena.queue_free()
	await tree.process_frame


func _reset_poses(chairs: Array[Chair], stage: ArenaStage) -> void:
	for index in chairs.size():
		var chair := chairs[index]
		chair.global_transform = stage.spawn_pose(index, chairs.size())
		chair.prepare_round()
		chair.falling = false
		chair.collision_layer = 2
		chair.collision_mask = 3
		chair.get_node("CollisionShape2D").set_deferred("disabled", false)
		chair.begin_round()
