extends RefCounted
## Collisions must move office clutter instead of creating an immovable chair trap.

const PROP := preload("res://game/props/office_task_chair.tscn")


func run(tree: SceneTree, check: Callable) -> void:
	var arena := Node2D.new()
	tree.root.add_child(arena)
	var props: Array[OfficeProp] = []
	for side in [-1, 1]:
		var prop := PROP.instantiate() as OfficeProp
		prop.position = Vector2(2000, 2000 + side * 42)
		arena.add_child(prop)
		prop.set_simulation_active(true)
		props.append(prop)
	var player := preload("res://game/chair/chair.tscn").instantiate() as Chair
	player.get_node("Visuals").free()
	player.position = Vector2(1880, 2000)
	player.configure(0, Color.WHITE, Vector2.LEFT)
	arena.add_child(player)
	for frame in 180:
		player.step(1.0 / 60.0)
		await tree.physics_frame
	check.call(player.position.x > 2140, "A player can push through a gap between two loose chairs")
	check.call(
		absf(props[0].position.y - 1958) > 6 and absf(props[1].position.y - 2042) > 6,
		"Both loose chair footprints yield to real collision impulses"
	)
	arena.queue_free()
	await tree.process_frame
	await _test_prop_fall(tree, check)


func _test_prop_fall(tree: SceneTree, check: Callable) -> void:
	var stage := preload("res://game/stage/a_floor_in_the_crack.tscn").instantiate() as ArenaStage
	tree.root.add_child(stage)
	var world := Node3D.new()
	tree.root.add_child(world)
	stage.create_presentation(world, 1.0 / RenderStyle.PIXELS_PER_UNIT)
	var prop := stage.get_node("Furniture/DeskChair1") as OfficeProp
	check.call(prop.scale == Vector2.ONE, "Loose rigid bodies remain unscaled after stage sizing")
	stage.start_round()
	prop.global_position = Vector2(1800, 422)
	prop.set("linear_velocity", Vector2(129, 0))
	for frame in 6:
		await tree.physics_frame
	var motion := prop.get("_motion") as PropMotion
	var falling := motion.get("_model") as RigidBody3D
	check.call(
		is_instance_valid(falling), "Unsupported loose furniture transfers to native 3D gravity"
	)
	if is_instance_valid(falling):
		check.call(
			falling.scale.is_equal_approx(Vector3.ONE),
			"Falling furniture uses an unscaled native body"
		)
		var height := falling.position.y
		for frame in 30:
			await tree.physics_frame
		check.call(
			falling.position.y < height - 0.5, "Loose furniture actually falls below the floor"
		)
	check.call(prop.collision_layer == 0, "Fallen furniture leaves no invisible 2D obstacle")
	if is_instance_valid(falling):
		falling.global_position.y = -40
		await tree.physics_frame
		await tree.process_frame
		await tree.process_frame
		stage.stop_round()
		check.call(
			not is_instance_valid(falling),
			"Offscreen prop cleanup remains safe when the round stops"
		)
	stage.queue_free()
	world.queue_free()
	await tree.process_frame
