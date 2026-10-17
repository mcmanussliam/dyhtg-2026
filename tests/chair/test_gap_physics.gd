extends RefCounted


## Real gravity and landing contacts decide whether carried speed clears a gap.
class GapStage:
	extends ArenaStage
	var half_gap := 40.0

	func has_support(point: Vector2) -> bool:
		return absf(point.x) >= half_gap


func run(tree: SceneTree, check: Callable) -> void:
	for scenario in [Vector2(40, 40), Vector2(650, 40), Vector2(650, 220), Vector2(0, 40)]:
		var speed: float = scenario.x
		var stage = GapStage.new()
		stage.half_gap = scenario.y
		tree.root.add_child(stage)
		stage.start_round()
		var world = Node3D.new()
		tree.root.add_child(world)
		for side in [-1, 1]:
			var floor_body = StaticBody3D.new()
			floor_body.add_to_group("stage_floor")
			floor_body.position = Vector3(
				side * (scenario.y + 200) / RenderStyle.PIXELS_PER_UNIT, -0.5, 0
			)
			world.add_child(floor_body)
			var shape = CollisionShape3D.new()
			shape.shape = BoxShape3D.new()
			shape.shape.size = Vector3(400 / RenderStyle.PIXELS_PER_UNIT, 1, 10)
			floor_body.add_child(shape)
		var chair = load("res://game/chair/chair.tscn").instantiate()
		chair.position = Vector2(-150 if speed == 0 else -scenario.y + 8, 0)
		chair.configure(0, Color.WHITE, Vector2.LEFT)
		chair.get_node("Visuals").configure_world(tree.root, world, stage)
		tree.root.add_child(chair)
		chair.linear_velocity = Vector2(speed, 0)
		chair.begin_fall()
		var view = chair.get_node("Visuals")
		view._physics_process(0)
		if speed == 0:
			var inverted := view.get("_fall_body") as RigidBody3D
			inverted.rotation.z = PI
			inverted.position.y = 1.25
		var landed = false
		for frame in 300:
			await tree.physics_frame
			if not chair.falling:
				landed = true
				break
		var body = view.get("_fall_body")
		if speed == 0:
			check.call(
				landed and chair.active,
				"An upside-down chair on the floor rights itself and resumes play"
			)
		elif speed == 40:
			check.call(
				not landed and body.global_position.y < -1,
				"Slow chair falls into a gap under gravity"
			)
		elif scenario.y == 40:
			check.call(
				landed and chair.position.x > scenario.y,
				"Fast chair can cross a narrow gap and physically land"
			)
			check.call(
				chair.linear_velocity.x > 0 and chair.active,
				"Landing preserves carried momentum and the player"
			)
		else:
			check.call(
				not landed and body.global_position.y < -1,
				"Speed cannot carry a chair over an excessively wide gap"
			)

		chair.queue_free()
		world.queue_free()
		stage.queue_free()
		await tree.process_frame
