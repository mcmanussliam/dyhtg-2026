extends RefCounted
## Unsupported chairs transfer momentum into native gravity-driven 3D bodies.


func run(tree: SceneTree, check: Callable) -> void:
	var chair := preload("res://game/chair/chair.tscn").instantiate() as Chair
	tree.root.add_child(chair)
	chair.configure(0, Color.WHITE, Vector2.RIGHT)
	chair.linear_velocity = Vector2(129, -86)
	chair.angular_velocity = 2.5
	chair.eliminate(&"fall")
	await tree.process_frame
	await tree.process_frame
	var view := chair.get_node("Visuals")
	var body := view.get("_fall_body") as RigidBody3D
	check.call(is_instance_valid(body), "A falling chair uses a native 3D rigid body")
	check.call(
		Vector2(body.linear_velocity.x, body.linear_velocity.z).is_equal_approx(Vector2(3, -2)),
		"Fall starts with the exact planar velocity at the shared world scale"
	)
	check.call(
		is_equal_approx(body.angular_velocity.y, -2.5),
		"Fall inherits existing angular momentum without adding spin"
	)
	var start := body.position
	for tick in 20:
		await tree.physics_frame
	await tree.process_frame
	check.call(body.position.y < start.y - 0.2, "Native gravity accelerates the chair downwards")
	check.call(
		body.position.x > start.x + 0.5 and body.position.z < start.z - 0.3,
		"Falling chair retains horizontal inertia"
	)
	check.call(
		view.scale == Vector2.ONE and is_equal_approx(view.modulate.a, 1.0),
		"Falling chair never shrinks or fades"
	)
	check.call(not view.get("_spray").visible, "Eliminated chair stops spraying during its fall")
	view.freeze_visuals()
	check.call(body.freeze, "Finished round freezes its fall physics behind results")
	chair.queue_free()
	await tree.process_frame
