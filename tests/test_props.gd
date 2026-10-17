extends RefCounted
## Reusable furniture shares authored footprints across gameplay and presentation.

const DESK = preload("res://game/props/office_desk.tscn")
const CABINET = preload("res://game/props/office_cabinet.tscn")
const SOFA = preload("res://game/props/office_sofa.tscn")
const BOOKSHELF = preload("res://game/props/office_bookshelf.tscn")
const PLANT = preload("res://game/props/office_plant.tscn")
const CHAIR = preload("res://game/chair/chair.tscn")
const SCALE = 43.0


func run(tree: SceneTree, check: Callable) -> void:
	var props := Node2D.new()
	props.position = Vector2(170, 120)
	props.rotation = 0.27
	tree.root.add_child(props)
	var world := Node3D.new()
	world.position = Vector3(2.0, 0.0, -3.0)
	world.rotation.y = 0.30
	tree.root.add_child(world)
	for resource in [DESK, CABINET, SOFA, BOOKSHELF, PLANT]:
		var prop := resource.instantiate() as OfficeProp
		prop.position = Vector2(100, 80)
		prop.rotation = -0.73
		props.add_child(prop)
		var model := prop.create_presentation(world, 1.0 / SCALE) as StaticBody3D
		_check_footprint(prop, model, check)
		check.call(
			prop.collision_layer == 1 and prop.collision_mask == 2,
			"Furniture blocks gameplay chairs and spray (%s)" % prop.name
		)
		check.call(
			model.collision_layer == 1,
			"Furniture provides native falling-body collision (%s)" % prop.name
		)
		prop.queue_free()
		model.queue_free()
	await tree.process_frame
	props.queue_free()
	world.queue_free()
	await tree.process_frame
	await _test_blocking(tree, check)


func _check_footprint(prop: OfficeProp, model: StaticBody3D, check: Callable) -> void:
	var shape := (prop.get_node("CollisionShape2D") as CollisionShape2D).shape
	var spatial := (model.get_node("Footprint") as CollisionShape3D).shape
	var samples: Array[Vector2] = []
	var dimensions_match := false
	if shape is RectangleShape2D and spatial is BoxShape3D:
		dimensions_match = (
			Vector2(spatial.size.x, spatial.size.z).distance_to(shape.size / SCALE) < 0.0001
		)
		for side in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			samples.append(shape.size * 0.5 * side)
	elif shape is CircleShape2D and spatial is CylinderShape3D:
		dimensions_match = is_equal_approx(shape.radius / SCALE, spatial.radius)
		for index in 12:
			samples.append(Vector2.from_angle(float(index) * TAU / 12.0) * shape.radius)
	check.call(dimensions_match, "Furniture 2D and 3D collision footprints match (%s)" % prop.name)
	var aligned := not samples.is_empty()
	for sample in samples:
		var point := prop.to_global(sample) / SCALE
		var position := model.to_global(Vector3(sample.x / SCALE, 0.0, sample.y / SCALE))
		aligned = aligned and point.distance_to(Vector2(position.x, position.z)) < 0.0001
	check.call(
		aligned, "Furniture transforms align after translation and rotation (%s)" % prop.name
	)


func _test_blocking(tree: SceneTree, check: Callable) -> void:
	var arena := Node2D.new()
	tree.root.add_child(arena)
	var desk := DESK.instantiate() as OfficeProp
	desk.position = Vector2(800, 1500)
	arena.add_child(desk)
	var source := CHAIR.instantiate() as Chair
	var target := CHAIR.instantiate() as Chair
	for chair in [source, target]:
		chair.get_node("Visuals").free()
		chair.configure(0, Color.WHITE, Vector2.RIGHT)
		arena.add_child(chair)
	source.position = Vector2(720, 1500)
	target.position = Vector2(880, 1500)
	source.freeze = true
	target.freeze = true
	await tree.physics_frame
	var spray := SpraySystem.new()
	spray.apply(source, [source, target], 1.0 / 60.0)
	check.call(
		absf(source.spray_reach - 28.4) < 0.1, "Desk footprint clips spray to its nearest surface"
	)
	var ray := PhysicsRayQueryParameters2D.create(source.position, target.position, 1)
	var hit := source.get_world_2d().direct_space_state.intersect_ray(ray)
	check.call(
		not hit.is_empty() and hit.collider == desk, "Desk blocks the spray line to another chair"
	)
	var contacts := [0]
	source.body_entered.connect(
		func(other: Node) -> void:
			if other == desk:
				contacts[0] += 1
	)
	source.position = Vector2(650, 1500)
	source.freeze = false
	source.sleeping = false
	source.linear_velocity = Vector2(350, 0)
	var crossed := false
	for frame in 90:
		await tree.physics_frame
		crossed = crossed or source.position.x > desk.position.x
	check.call(contacts[0] > 0, "Moving rigid-body chair contacts the furniture footprint")
	check.call(not crossed, "Furniture physically prevents the chair passing through")
	arena.queue_free()
	await tree.process_frame
