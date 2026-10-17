extends RefCounted
## Real physics comparison: straight acceleration versus speed scrub during a hard turn.

const CHAIR := preload("res://game/chair/chair.tscn")


func run(tree: SceneTree, check: Callable) -> void:
	var straight := CHAIR.instantiate() as Chair
	var turning := CHAIR.instantiate() as Chair
	var arena := Node2D.new()
	tree.root.add_child(arena)
	for chair in [straight, turning]:
		chair.collision_mask = 0
		arena.add_child(chair)
		chair.configure(0, Color.WHITE, Vector2.RIGHT)
	turning.position.y = 1000
	for frame in 30:
		straight.step(1.0 / 60)
		turning.step(1.0 / 60)
		await tree.physics_frame
	var launch_speed := straight.linear_velocity.length()
	check.call(launch_speed > 450, "Continuous thrust builds speed quickly from rest")
	for frame in 30:
		turning.command.turn = 1.0
		straight.step(1.0 / 60)
		turning.step(1.0 / 60)
		await tree.physics_frame
	check.call(
		straight.linear_velocity.length() > 600, "Straight travel reaches the higher speed range"
	)
	check.call(
		turning.linear_velocity.length() < straight.linear_velocity.length() * 0.7,
		"A hard turn sheds substantial speed without snapping its velocity"
	)
	turning.command.turn = 0.0
	var minimum_speed := turning.linear_velocity.length()
	for frame in 60:
		turning.step(1.0 / 60)
		await tree.physics_frame
		minimum_speed = minf(minimum_speed, turning.linear_velocity.length())
	check.call(
		turning.linear_velocity.length() > minimum_speed + 200,
		"Releasing the turn rebuilds speed with continuous propulsion"
	)
	arena.queue_free()
	await tree.process_frame
