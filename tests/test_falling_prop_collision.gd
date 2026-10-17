extends RefCounted
## Live 2D chairs still collide with native 3D furniture until it clears their height.

const UNITS := 1.0 / RenderStyle.PIXELS_PER_UNIT


func run(tree: SceneTree, check: Callable) -> void:
	for path in ["office_bookshelf", "office_task_chair"]:
		var arena := Node2D.new()
		tree.root.add_child(arena)
		var world := Node3D.new()
		tree.root.add_child(world)
		var prop := load("res://game/props/%s.tscn" % path).instantiate() as OfficeProp
		arena.add_child(prop)
		prop.position = Vector2(2000, 2000)
		prop.create_presentation(world, UNITS)
		var stage := ArenaStage.new()
		arena.add_child(stage)
		var floor := StaticBody3D.new()
		world.add_child(floor)
		floor.position = Vector3(2000 * UNITS, -0.5, 2000 * UNITS)
		var floor_shape := CollisionShape3D.new()
		floor_shape.shape = BoxShape3D.new()
		floor_shape.shape.size = Vector3(20, 1, 20)
		floor.add_child(floor_shape)
		prop.release_for_fracture(stage, [], Vector2.ZERO)
		var native: RigidBody3D
		if prop.is_movable():
			native = prop.get("_motion").get("_model")
		else:
			native = prop.get("_presentation")
		var bridge := arena.get_node("FallingFurnitureCollision") as PropCollisionBridge
		for frame in 2:
			await tree.physics_frame
		var space := arena.get_world_2d().direct_space_state
		var ray := PhysicsRayQueryParameters2D.create(Vector2(1850, 2000), Vector2(2150, 2000), 1)
		var hit := space.intersect_ray(ray)
		check.call(
			not hit.is_empty() and hit.collider == bridge,
			"Released %s stays solid to planar queries" % path
		)
		var chair := preload("res://game/chair/chair.tscn").instantiate() as Chair
		chair.get_node("Visuals").free()
		arena.add_child(chair)
		chair.position = Vector2(1820, 2000)
		chair.configure(0, Color.WHITE, Vector2.LEFT)
		var touched := [false]
		chair.body_entered.connect(
			func(other: Node):
				if other == bridge:
					touched[0] = true
		)
		var initial := native.position
		for frame in 120:
			chair.step(1.0 / 60)
			await tree.physics_frame
		check.call(touched[0], "A live chair physically hits released %s" % path)
		check.call(native.position.x - initial.x > 0.01, "Chair contact pushes native %s" % path)
		chair.queue_free()
		# Tilt and move it: the footprint must follow the real collider, not stay at spawn.
		native.freeze = true
		native.position.x += 4
		native.rotation.z = 0.45
		for frame in 3:
			await tree.physics_frame
		check.call(
			absf(bridge.global_position.x - native.position.x / UNITS) < 0.1,
			"Collision follows moving/tilting %s" % path
		)
		# Once fully below chair height the same geometry must leave no invisible wall.
		native.position.y = -10
		for frame in 3:
			await tree.physics_frame
		var clear := true
		for collider in bridge.get_children():
			clear = clear and collider.disabled
		check.call(clear, "Below-floor %s leaves no ghost collision" % path)
		native.queue_free()
		for frame in 3:
			await tree.process_frame
		check.call(
			not is_instance_valid(bridge),
			"Native %s cleanup also removes its collision bridge" % path
		)
		arena.queue_free()
		world.queue_free()
		await tree.process_frame
