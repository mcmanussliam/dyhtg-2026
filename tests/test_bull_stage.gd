extends RefCounted
## Real movement sweeps, wall stops and stage-owned hazard lifecycle.


func run(tree: SceneTree, check: Callable) -> void:
	var definition := load("res://game/stage/bull_office.tres") as StageDefinition
	check.call(definition.validation_errors().is_empty(), "Bull map validates")
	check.call(
		definition.hint == "Mess with the bull and you get the horns",
		"Bull map has its authored hint"
	)
	var config := MatchConfig.new()
	check.call(
		config.stages.any(func(item: StageDefinition) -> bool: return item.id == definition.id),
		"Random map pool includes the bull office"
	)
	var stage := definition.scene.instantiate() as OfficeStage
	tree.root.add_child(stage)
	var bull := stage.get("bull") as OfficeBull
	var end := stage.boundary_in_direction(Vector2(640, 422), Vector2.RIGHT)
	check.call(
		end.is_equal_approx(Vector2(1284, 422)),
		"Charge guide reaches the inner wall rather than the selected target"
	)
	var diagonal := stage.boundary_in_direction(Vector2(640, 422), Vector2(1, 1).normalized())
	check.call(
		is_equal_approx(diagonal.y, 1050) and stage.has_support(diagonal),
		"Diagonal charge guide stops at the first room edge"
	)
	check.call(stage.has_support(Vector2(640, 422)), "Bull office has a solid center without a pit")
	var original := bull.position
	stage.tick_hazards(10)
	check.call(
		bull.position == original and bull.phase == OfficeBull.Phase.RECOVERY,
		"Intro never advances bull attacks"
	)
	var chair := load("res://game/chair/chair.tscn").instantiate() as Chair
	chair.configure(0, Color.WHITE, Vector2.RIGHT)
	tree.root.add_child(chair)
	chair.prepare_round()
	chair.position = Vector2(820, 422)
	var roster: Array[Chair] = [chair]
	stage.bind_participants(roster)
	var hits: Array[int] = []
	stage.elimination_requested.connect(
		func(seat: int, _reason: StringName) -> void: hits.append(seat)
	)
	await tree.physics_frame
	stage.start_round()
	bull.phase = OfficeBull.Phase.RECOVERY
	bull.position = Vector2(640, 422)
	bull.collision_layer = 1
	bull.collision_mask = 1
	bull.set("_random", RandomNumberGenerator.new())
	bull.get("_random").seed = 5293
	stage.tick_hazards(1.3)
	check.call(bull.phase == OfficeBull.Phase.WINDUP, "Bull telegraphs before charging")
	var locked: Vector2 = bull.get("_direction")
	chair.position = Vector2(400, 700)
	stage.tick_hazards(0.2)
	check.call(bull.get("_direction") == locked, "Windup locks aim so players can dodge")
	# A single high-speed step must still register a chair in the middle of its path.
	bull.global_position = Vector2(600, 422)
	bull.set("_direction", Vector2.RIGHT)
	bull.rotation = 0
	bull.phase = OfficeBull.Phase.CHARGE
	bull.velocity = Vector2(1000, 0)
	chair.position = Vector2(760, 422)
	await tree.physics_frame
	stage.tick_hazards(0.25)
	check.call(hits == [0], "Swept charge hits a player between physics endpoints")
	check.call(
		chair.knockout_velocity.x > 45 and chair.knockout_velocity.y >= 15,
		"Bull prepares a huge upward and forward knockout launch"
	)
	check.call(chair.knockout_spin.length() > 8, "Bull knockout includes a full tumbling impulse")
	check.call(bull.phase == OfficeBull.Phase.STUNNED, "Player impact stuns the bull")
	var stun := bull.get("_remaining") as float
	stage.stop_round()
	stage.tick_hazards(10)
	check.call(is_equal_approx(stun, bull.get("_remaining")), "Results freeze hazard recovery")
	stage.start_round()
	stage.tick_hazards(stun + 0.01)
	check.call(bull.phase == OfficeBull.Phase.RECOVERY, "Stunned bull recovers after a short delay")
	# An actual perimeter collider stops a charge and triggers the same stun phase.
	bull.position = Vector2(1200, 422)
	bull.phase = OfficeBull.Phase.CHARGE
	bull.velocity = Vector2(1000, 0)
	bull.set("_direction", Vector2.RIGHT)
	bull.rotation = 0
	chair.position = Vector2(640, 900)
	await tree.physics_frame
	stage.tick_hazards(0.2)
	check.call(
		bull.position.x < 1296 and bull.phase == OfficeBull.Phase.STUNNED,
		"Wall collision stops and stuns the bull"
	)
	check.call(hits.size() == 1, "Stun and wall impacts do not create extra kills")
	var cover := StaticBody2D.new()
	cover.position = Vector2(700, 422)
	cover.collision_layer = 1
	var blocker := CollisionShape2D.new()
	blocker.shape = RectangleShape2D.new()
	blocker.shape.size = Vector2(30, 200)
	cover.add_child(blocker)
	tree.root.add_child(cover)
	bull.position = Vector2(600, 422)
	bull.phase = OfficeBull.Phase.CHARGE
	bull.velocity = Vector2(1000, 0)
	bull.set("_direction", Vector2.RIGHT)
	chair.position = Vector2(840, 422)
	bull.get("_hit_seats").clear()
	await tree.physics_frame
	stage.tick_hazards(0.3)
	check.call(
		hits.size() == 1 and bull.position.x < 700,
		"Solid cover blocks a charge from hitting players behind it"
	)
	cover.queue_free()
	chair.queue_free()
	stage.queue_free()
	await tree.process_frame
	# Exercise the complete round's existing scoring and ragdoll path.
	var state := MatchState.new()
	state.configure(config)
	var round_scene := load("res://game/round/round.tscn").instantiate() as RoundController
	round_scene.configure(state.participants, definition, 1, 5)
	tree.root.add_child(round_scene)
	round_scene.set_physics_process(false)
	round_scene._physics_process(round_scene.intro_duration)
	check.call(
		round_scene.phase == RoundController.Phase.LIVE,
		"Bull round starts immediately after its title"
	)
	check.call(
		round_scene.stage.bull.position.is_equal_approx(round_scene.stage.center),
		"First bull remains at the center during the reveal"
	)
	check.call(
		not round_scene.chairs[0].freeze and round_scene.chairs[0].jet_strength == 0,
		"Players can steer immediately while extinguishers spool up"
	)
	check.call(
		is_zero_approx(round_scene.stage.get("_elapsed")), "Hazard clock begins with live gameplay"
	)

	var victim := round_scene.chairs[0]
	victim.set_knockout_launch(Vector3(55, 15, 0), Vector3(0, 3.5, -9))
	round_scene.request_elimination(0, &"bull")
	round_scene._commit_eliminations()
	check.call(
		not round_scene.chairs[0].active and round_scene.chairs[0].falling,
		"Bull kills commit immediately with native ragdoll presentation"
	)
	check.call(
		round_scene.phase == RoundController.Phase.RESOLVING,
		"Last survivor wins through the shared match rules"
	)
	var view := victim.get_node("Visuals")
	view.call("_physics_process", 0)
	var body := view.get("_fall_body") as RigidBody3D
	check.call(
		body.linear_velocity.is_equal_approx(Vector3(55, 15, 0)),
		"Native knockout receives the uncapped launch velocity"
	)
	check.call(
		body.angular_velocity.is_equal_approx(Vector3(0, 3.5, -9)),
		"Native knockout receives the full tumble"
	)
	check.call(
		body.collision_mask == 0 and body.collision_layer == 0,
		"Eliminated flight cannot be trapped by office boundaries"
	)
	var start := body.global_position
	for frame in 60:
		await tree.physics_frame
	check.call(
		body.global_position.x > (640 + 656) / RenderStyle.PIXELS_PER_UNIT,
		"Bull launch carries the victim outside the office"
	)
	check.call(
		body.global_position.y > start.y + 8 and body.linear_velocity.y < 15,
		"Native gravity bends the soaring knockout trajectory"
	)
	check.call(not victim.active, "Flying victims remain eliminated throughout the animation")
	victim.prepare_round()
	check.call(
		victim.knockout_velocity == Vector3.ZERO and victim.knockout_spin == Vector3.ZERO,
		"Round preparation clears the previous knockout impulse"
	)
	round_scene.queue_free()
	await tree.process_frame
	await _check_arrivals(tree, check)


func _check_arrivals(tree: SceneTree, check: Callable) -> void:
	var scene := load("res://game/stage/bull_office.tscn") as PackedScene
	var stage := scene.instantiate() as OfficeStage
	stage.arrival_interval = 3.0
	stage.max_bulls = 3
	tree.root.add_child(stage)
	var world := Node3D.new()
	tree.root.add_child(world)
	stage.create_presentation(world, 1.0 / RenderStyle.PIXELS_PER_UNIT)
	check.call(
		world.has_node("SaloonDoor") and not world.has_node("OfficeDoor"),
		"Bull map uses its own centered saloon entrance"
	)
	check.call(
		stage.bulls.size() == 1 and stage.bull.position.is_equal_approx(stage.center),
		"First bull is already at the office center"
	)
	stage.tick_hazards(10)
	check.call(
		stage.bulls.size() == 1 and is_zero_approx(stage.get("_elapsed")),
		"Intro does not advance arrival timer"
	)
	var entry_start := stage.to_global(
		Vector2(stage.center.x, stage.center.y - stage.half_size.y - 120)
	)
	check.call(
		stage.bull.phase == OfficeBull.Phase.RECOVERY, "Centered first bull skips walking entry"
	)
	stage.start_round()
	stage.bull.phase = OfficeBull.Phase.WINDUP
	stage.bull.set("_direction", Vector2.DOWN)
	stage.bull.target = stage.bull.global_position + Vector2(0, 100)
	stage.bull.call("_sync_presentation", 0)
	var lane := stage.bull.get("_lane") as MeshInstance3D
	var expected := (
		stage.boundary_in_direction(stage.bull.global_position, Vector2.DOWN).distance_to(
			stage.bull.global_position
		)
		/ RenderStyle.PIXELS_PER_UNIT
	)
	check.call(
		(
			is_equal_approx(lane.scale.z, expected)
			and lane.scale.z > 100 / RenderStyle.PIXELS_PER_UNIT
		),
		"Visible charge guide extends past its target to the office boundary"
	)
	# Occupied doorway delays the arrival instead of stacking bulls into each other.
	stage.bull.position = Vector2(stage.center.x, stage.center.y - stage.half_size.y + 160)
	stage.bull.phase = OfficeBull.Phase.STUNNED
	stage.bull.set("_remaining", 10.0)
	stage.tick_hazards(3.1)
	check.call(stage.bulls.size() == 1, "Occupied entrance defers the next bull")
	stage.bull.position = stage.center
	stage.tick_hazards(0.01)
	check.call(
		stage.bulls.size() == 2, "Another bull arrives after the interval when the doorway clears"
	)
	check.call(
		(
			stage.bulls[1].position == entry_start
			and stage.bulls[1].phase == OfficeBull.Phase.ENTERING
		),
		"Later bulls use the same outside doorway start"
	)
	check.call(
		stage.bulls[1].get("_model") != null,
		"Later arrivals create their native model in the existing world"
	)
	for actor in stage.bulls:
		actor.position = stage.center + Vector2(0, 200)
		actor.phase = OfficeBull.Phase.STUNNED
		actor.set("_remaining", 20.0)
	stage.tick_hazards(3.1)
	check.call(stage.bulls.size() == 3, "Difficulty grows through multiple sequential arrivals")
	for actor in stage.bulls:
		actor.position = stage.center
		actor.phase = OfficeBull.Phase.STUNNED
		actor.set("_remaining", 30.0)
	stage.tick_hazards(10)
	check.call(stage.bulls.size() == 3, "Configured bull limit bounds long-round workload")
	stage.stop_round()
	var elapsed: float = stage.get("_elapsed")
	var door := world.get_node("SaloonDoor")
	var angle: float = door.get("_angle")
	stage.tick_hazards(30)
	check.call(
		(
			is_equal_approx(stage.get("_elapsed"), elapsed)
			and is_equal_approx(door.get("_angle"), angle)
		),
		"Results freeze arrivals and saloon door animation"
	)
	stage.queue_free()
	world.queue_free()
	await tree.process_frame
	var fresh := scene.instantiate() as OfficeStage
	tree.root.add_child(fresh)
	check.call(
		(
			fresh.bulls.size() == 1
			and is_zero_approx(fresh.get("_elapsed"))
			and fresh.bull.position.is_equal_approx(fresh.center)
		),
		"A new round resets to its first arrival"
	)
	fresh.queue_free()
	await tree.process_frame
