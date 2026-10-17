extends RefCounted
## Spectated crowds must keep moving and resolve as the actual supporting floor recedes.

const CHAIR := preload("res://game/chair/chair.tscn")
const STEP := 1.0 / 60


func run(tree: SceneTree, check: Callable) -> void:
	for map in ["a_crack_in_the_floor", "a_floor_in_the_crack"]:
		var arena := Node2D.new()
		tree.root.add_child(arena)
		var stage := load("res://game/stage/%s.tscn" % map).instantiate() as ArenaStage
		arena.add_child(stage)
		stage.start_round()
		var chairs: Array[Chair] = []
		var pilots: Array[PracticePilot] = []
		var anchors: Array[Vector2] = []
		var stationary: Array[float] = []
		var poses := SpawnLayout.poses(stage, 10)
		for index in 10:
			var chair := CHAIR.instantiate() as Chair
			chair.get_node("Visuals").free()
			chair.resize_for_stage(stage.content_scale)
			chair.configure(index, Color.WHITE, Vector2.RIGHT)
			arena.add_child(chair)
			chair.global_transform = poses[index]
			chairs.append(chair)
			pilots.append(PracticePilot.new(2319 + index * 31))
			anchors.append(chair.position)
			stationary.append(0.0)
		await tree.physics_frame
		var spray := SpraySystem.new()
		var longest := 0.0
		var alive := 10
		var duration := 0.0
		for frame in 9000:
			duration = (frame + 1) * STEP
			if frame == 180:
				chairs[0].eliminate(&"fall")
			stage.tick_hazards(STEP)
			for index in chairs.size():
				var chair := chairs[index]
				if chair.active:
					chair.command = pilots[index].sample_on_stage(chair, chairs, stage, STEP)
					chair.step(STEP)
			for chair in chairs:
				spray.apply(chair, chairs, STEP)
			await tree.physics_frame
			alive = 0
			for index in chairs.size():
				var chair := chairs[index]
				if not chair.active:
					continue
				if not stage.has_support_near(
					chair.position, 0.15 * RenderStyle.PIXELS_PER_UNIT * chair.size_scale
				):
					chair.eliminate(&"fall")
					continue
				alive += 1
				if chair.position.distance_to(anchors[index]) > 60 * chair.size_scale:
					anchors[index] = chair.position
					stationary[index] = 0
				else:
					# Count a slow nearby pack, not a pinned chair with rivals driving past it.
					var crowded := false
					for other in chairs:
						if (
							other != chair
							and other.active
							and chair.position.distance_to(other.position) < 110 * chair.size_scale
							and chair.linear_velocity.length() < 100
							and other.linear_velocity.length() < 100
						):
							crowded = true
					stationary[index] = stationary[index] + STEP if crowded else 0.0
					longest = maxf(longest, stationary[index])
			if alive < 2:
				break
		print(
			(
				"CRUMBLING CROWD %s duration=%.2f longest=%.2f alive=%d"
				% [map, duration, longest, alive]
			)
		)
		check.call(alive < 2, "Spectated ten-chair round resolves on %s" % map)
		check.call(longest < 7, "No prolonged stationary crowd on %s" % map)
		stage.stop_round()
		arena.queue_free()
		await tree.process_frame
