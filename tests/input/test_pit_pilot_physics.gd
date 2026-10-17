extends RefCounted
## Seeded pit playtests use the same thrust, inertia, furniture and spray as gameplay.

const STEP := 1.0 / 60
const PIT := preload("res://game/stage/a_crack_in_the_floor/a_crack_in_the_floor.tscn")
const CHAIR := preload("res://game/chair/chair.tscn")


func run(tree: SceneTree, check: Callable) -> void:
	for scenario in [
		Vector2i(1521, 1),
		Vector2i(7483, 1),
		Vector2i(2319, 2),
		Vector2i(5391, 2),
		Vector2i(8419, 4)
	]:
		await _simulate(tree, check, scenario.x, scenario.y)


func _simulate(tree: SceneTree, check: Callable, seed_value: int, count: int) -> void:
	var arena := Node2D.new()
	tree.root.add_child(arena)
	var stage := PIT.instantiate() as ArenaStage
	arena.add_child(stage)
	stage.start_round()
	var chairs: Array[Chair] = []
	var pilots: Array[PracticePilot] = []
	var contacts := [0]
	for index in count:
		var chair := CHAIR.instantiate() as Chair
		chair.get_node("Visuals").free()
		chair.resize_for_stage(stage.content_scale)
		chair.configure(index, Color.WHITE, Vector2.RIGHT)
		arena.add_child(chair)
		chair.global_transform = stage.spawn_pose(index, count)
		chair.body_entered.connect(
			func(other: Node) -> void:
				if other is Chair:
					contacts[0] += 1
		)
		chairs.append(chair)
		pilots.append(PracticePilot.new(seed_value + index * 31))
	await tree.physics_frame
	var spray := SpraySystem.new()
	var first_fall := -1.0
	var falls := 0
	var travel := 0.0
	var blasts := 0
	var frames := 0
	for frame in 1200 if count == 1 else 5400:
		frames = frame + 1
		var previous: Array[Vector2] = []
		for index in count:
			var chair := chairs[index]
			previous.append(chair.position)
			if chair.active:
				chair.command = pilots[index].sample_on_stage(chair, chairs, stage, STEP)
				chair.step(STEP)
		for chair in chairs:
			spray.apply(chair, chairs, STEP)
			if chair.active:
				for other in chairs:
					var offset := other.position - chair.position
					if (
						other != chair
						and other.active
						and offset.length() < chair.spray_reach
						and (
							offset.normalized().dot(Vector2.from_angle(chair.aim_angle))
							> cos(deg_to_rad(chair.tuning.half_angle_degrees))
						)
					):
						blasts += 1
		await tree.physics_frame
		var alive := 0
		for index in count:
			var chair := chairs[index]
			if not chair.active:
				continue
			travel += previous[index].distance_to(chair.position)
			if not stage.has_support_near(
				chair.global_position, 0.15 * RenderStyle.PIXELS_PER_UNIT * chair.size_scale
			):
				chair.eliminate(&"fall")
				falls += 1
				if first_fall < 0:
					first_fall = frames * STEP
			else:
				alive += 1
		if count > 1 and alive < 2:
			break
	print(
		(
			"PIT AI seed=%d count=%d first=%.2f duration=%.2f falls=%d contacts=%d blasts=%d travel=%.0f"
			% [seed_value, count, first_fall, frames * STEP, falls, contacts[0], blasts, travel]
		)
	)
	check.call(travel > 1500, "Pit pilots actively navigate the room (%d)" % seed_value)
	if count == 1:
		check.call(falls == 0, "Unopposed pit pilot survives twenty seconds (%d)" % seed_value)
	else:
		check.call(
			first_fall < 0 or first_fall >= 5,
			"Pit combat avoids suicidal opening falls (%d)" % seed_value
		)
		check.call(
			contacts[0] + blasts > 5, "Pit pilots maintain physical aggression (%d)" % seed_value
		)
		check.call(falls == count - 1, "Pit fights still resolve through combat (%d)" % seed_value)
	stage.stop_round()
	arena.queue_free()
	await tree.process_frame
