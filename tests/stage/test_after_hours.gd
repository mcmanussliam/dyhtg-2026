extends RefCounted
## Flashlight sight, hard-furniture cover, telegraphed chases, catches and arrivals.


func run(tree: SceneTree, check: Callable) -> void:
	var definition := load("res://game/stage/after_hours/after_hours.tres") as StageDefinition
	check.call(definition.validation_errors().is_empty(), "After Hours validates")
	check.call(
		definition.display_name == "After Hours" and definition.hint == "Five nights in the office",
		"After Hours has its authored title and subheading"
	)
	check.call(
		MatchConfig.new().stages.any(
			func(item: StageDefinition) -> bool: return item.id == &"after_hours"
		),
		"Random map pool includes After Hours"
	)
	var stage := definition.scene.instantiate() as OfficeStage
	tree.root.add_child(stage)
	var chairs := 0
	for prop in stage.get_node("Furniture").get_children():
		if prop.name.contains("Chair"):
			chairs += 1
			check.call(prop is RigidBody2D, "Desk chairs are movable: %s" % prop.name)
	check.call(chairs == 16, "Every desk has a chair")
	stage.tick_hazards(30)
	check.call(stage.get("guards").is_empty(), "Intro never brings guards on duty")
	var chair := load("res://game/chair/chair.tscn").instantiate() as Chair
	chair.configure(0, Color.WHITE, Vector2.RIGHT)
	tree.root.add_child(chair)
	chair.prepare_round()
	var roster: Array[Chair] = [chair]
	stage.bind_participants(roster)
	var hits: Array = []
	stage.elimination_requested.connect(
		func(seat: int, reason: StringName) -> void: hits.append([seat, reason])
	)
	stage.start_round()
	stage.tick_hazards(stage.first_arrival + 0.01)
	var guards: Array = stage.get("guards")
	check.call(
		guards.size() == 1 and guards[0].phase == NightGuard.Phase.ENTERING,
		"The first guard enters through the door after a short delay"
	)
	var guard := guards[0] as NightGuard
	# Sight: the middle corridor is open; pod B's desks are fixed cover.
	guard.global_position = Vector2(640, 425)
	guard.rotation = 0
	guard.beam_angle = 0
	guard.phase = NightGuard.Phase.PATROL
	guard.collision_layer = 1
	guard.collision_mask = 1
	chair.global_position = Vector2(950, 425)
	await tree.physics_frame
	await tree.physics_frame
	check.call(guard.illuminates(chair.global_position), "Flashlight reaches a player in front")
	check.call(not guard.illuminates(Vector2(640, 800)), "Players outside the beam stay hidden")
	check.call(
		not guard.illuminates(Vector2(640, 125)),
		"The beam is a cone, not a radius around the guard"
	)
	guard.global_position = Vector2(912, 425)
	guard.beam_angle = -PI / 2
	check.call(
		not guard.has_line_of_sight(Vector2(912, -20)),
		"Desks block the flashlight from players hiding behind them"
	)
	var loose := stage.get_node("Furniture/PodBChairSE") as RigidBody2D
	loose.global_position = Vector2(780, 425)
	await tree.physics_frame
	await tree.physics_frame
	guard.global_position = Vector2(640, 425)
	guard.beam_angle = 0
	check.call(
		guard.has_line_of_sight(Vector2(950, 425)), "Loose chairs never hide players from guards"
	)
	loose.global_position = Vector2(1000, 860)
	await tree.physics_frame
	# A lit player triggers a telegraphed chase.
	chair.global_position = Vector2(950, 425)
	stage.tick_hazards(1.0 / 60.0)
	check.call(
		guard.phase == NightGuard.Phase.ALERT and guard.target == chair,
		"Spotting a player raises a visible alert first"
	)
	var start := guard.global_position
	stage.tick_hazards(guard.alert_seconds * 0.5)
	check.call(
		guard.global_position.is_equal_approx(start) and hits.is_empty(),
		"Guards hold still during the alert so players can react"
	)
	stage.tick_hazards(guard.alert_seconds * 0.6)
	check.call(guard.phase == NightGuard.Phase.CHASE, "The alert becomes a chase")
	check.call(not stage.is_safe(chair.global_position), "AI treats a lit position as unsafe")
	var refuge := stage.safe_target(chair.global_position)
	await tree.physics_frame
	check.call(
		not guard.illuminates(refuge, 30), "AI refuge is out of the beam, behind fixed cover"
	)
	# Hiding behind a desk breaks the chase.
	chair.global_position = Vector2(912, -20)
	guard.global_position = Vector2(912, 425)
	await tree.physics_frame
	for step in 40:
		stage.tick_hazards(1.0 / 60.0)
	check.call(
		guard.phase in [NightGuard.Phase.SEARCH, NightGuard.Phase.RETURN],
		"Breaking sight behind furniture ends the chase"
	)
	stage.tick_hazards(guard.search_seconds + 0.1)
	check.call(
		guard.phase in [NightGuard.Phase.RETURN, NightGuard.Phase.PATROL] and hits.is_empty(),
		"A guard that loses the player returns to patrol"
	)
	# A caught player receives the big knockout launch.
	guard.global_position = Vector2(640, 425)
	guard.rotation = 0
	guard.phase = NightGuard.Phase.CHASE
	guard.target = chair
	guard.last_seen = Vector2(700, 425)
	guard.velocity = Vector2(500, 0)
	chair.global_position = Vector2(700, 425)
	await tree.physics_frame
	stage.tick_hazards(1.0 / 60.0)
	check.call(hits == [[0, &"guard"]], "Catching a player requests a guard elimination")
	check.call(
		chair.knockout_velocity.x > 40 and chair.knockout_velocity.y >= 14,
		"Guards launch caught players like the bull"
	)
	check.call(chair.knockout_spin.length() > 8, "Guard launches include a tumble")
	check.call(guard.phase == NightGuard.Phase.CAUGHT, "Guards pause after a catch")
	stage.stop_round()
	var frozen := guard.global_position
	stage.tick_hazards(5)
	check.call(guard.global_position == frozen, "Results freeze guards")
	chair.queue_free()
	stage.queue_free()
	await tree.process_frame
	await _check_arrivals(tree, check)


func _check_arrivals(tree: SceneTree, check: Callable) -> void:
	var stage := (
		(load("res://game/stage/after_hours/after_hours.tscn") as PackedScene).instantiate()
		as OfficeStage
	)
	stage.first_arrival = 1.0
	stage.arrival_interval = 4.0
	stage.max_guards = 3
	tree.root.add_child(stage)
	stage.start_round()
	var counts: Array[int] = []
	for second in 20:
		for step in 10:
			stage.tick_hazards(0.1)
		counts.append(stage.get("guards").size())
	check.call(counts[1] == 1 and counts[6] == 2, "More guards come on duty as the night goes on")
	check.call(counts[-1] == 3, "Guard arrivals stop at the nightly limit")
	var routes := {}
	for guard in stage.get("guards"):
		routes[guard.route] = true
		check.call(
			guard.phase != NightGuard.Phase.ENTERING and stage.has_support(guard.global_position),
			"Arriving guards walk into the office"
		)
	check.call(routes.size() == 3, "Guards patrol different routes")
	stage.queue_free()
	await tree.process_frame
