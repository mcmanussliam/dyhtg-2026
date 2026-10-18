extends RefCounted
## Zones, infection spread, the slow technician, elimination and round lifetime.

const DEFINITION = preload("res://game/stage/computer_bugs/computer_bugs.tres")
const STEP := 1.0 / 60


func run(tree: SceneTree, check: Callable) -> void:
	check.call(DEFINITION.validation_errors().is_empty(), "Computer Bugs validates")
	check.call(
		DEFINITION.display_name == "Computer Bugs" and DEFINITION.hint == "THE BUGS NEVER SLEEP",
		"Computer Bugs has its authored headline and subheading"
	)
	check.call(
		MatchConfig.available_stages().any(
			func(item: StageDefinition) -> bool: return item.id == &"computer_bugs"
		),
		"Random pool and map selector include Computer Bugs"
	)
	var stage := DEFINITION.scene.instantiate() as ComputerBugsStage
	tree.root.add_child(stage)
	var world := Node3D.new()
	tree.root.add_child(world)
	stage.create_presentation(world, 1.0 / RenderStyle.PIXELS_PER_UNIT)
	await tree.physics_frame
	check.call(stage.computers.size() == 16, "Sixteen workstations cover the whole office floor")
	var columns := {}
	var rows := {}
	var tidy := true
	for computer in stage.computers:
		columns[snappedf(computer.position.x, 1.0)] = true
		rows[snappedf(computer.position.y, 1.0)] = true
		tidy = (
			tidy
			and (is_zero_approx(computer.rotation) or is_equal_approx(absf(computer.rotation), PI))
		)
	check.call(
		columns.size() == 4 and rows.size() == 4 and tidy,
		"Workstations form tidy back-to-back benches on a grid"
	)
	check.call(
		stage.has_support(stage.to_global(stage.center)), "Computer Bugs office has a solid floor"
	)
	stage.tick_hazards(30)
	check.call(
		stage.infected_count() == 0 and stage.fixer_state == ComputerBugsStage.Fixer.HIDDEN,
		"Black intro never infects a computer"
	)
	stage.set_render_warmup(true)
	stage.set_render_warmup(false)
	check.call(stage.infected_count() == 0, "Warmup leaves every computer clean")
	stage.start_round()
	stage.tick_hazards(stage.first_infection - 0.1)
	check.call(stage.infected_count() == 0, "The first infection waits for its opening delay")
	stage.tick_hazards(0.2)
	check.call(stage.infected_count() == 1, "Exactly one computer is infected first")
	var first := stage.infected.find(true)
	check.call(
		stage.get("_screens")[first].visible and stage.get("_zone_data")[first].w > 0.5,
		"The broken monitor and its danger zone are shown"
	)
	check.call(not stage.is_armed(first), "A new infection is announced before it turns lethal")
	check.call(
		not stage.is_safe(stage.computer_position(first)),
		"AI avoids an infected computer straight away"
	)
	stage.tick_hazards(stage.warning_seconds)
	check.call(stage.is_armed(first), "The zone turns lethal after its warning")
	# Bugs never roam: the colony is exactly the same a second later.
	var before: Vector3 = stage.get("_view").multimesh.get_instance_transform(0).origin
	stage.tick_hazards(1.0)
	var after: Vector3 = stage.get("_view").multimesh.get_instance_transform(0).origin
	check.call(before.is_equal_approx(after), "Colony bugs stay put instead of wandering")
	var spread_seen := 0
	var fixer_arrived := false
	for frame in 60 * 90:
		stage.tick_hazards(STEP)
		spread_seen = maxi(spread_seen, stage.infected_count())
		fixer_arrived = fixer_arrived or stage.fixer_state == ComputerBugsStage.Fixer.REPAIRING
	check.call(spread_seen >= 3, "Infection spreads computer to computer: %d" % spread_seen)
	check.call(fixer_arrived, "The bug fixer walks over and repairs a computer")
	check.call(stage.repairs_total >= 1, "The bug fixer finishes at least one repair")
	check.call(
		stage.repairs_total < stage.infections_total - 1,
		(
			"The fixer is slower than the infection: %d fixed of %d"
			% [stage.repairs_total, stage.infections_total]
		)
	)
	check.call(
		stage.current_spread() < stage.spread_interval * 0.5,
		"Infection quickens as the round goes on"
	)
	_test_ramp(stage, check)
	var seen := stage.infections_total
	stage.stop_round()
	stage.tick_hazards(10)
	check.call(stage.infections_total == seen, "Round results freeze the infection")
	world.queue_free()
	stage.queue_free()
	await tree.process_frame
	await _test_zones(tree, check)
	await _test_fixer(tree, check)


func _test_zones(tree: SceneTree, check: Callable) -> void:
	var state := MatchState.new()
	state.configure(MatchConfig.new())
	var round_scene := RoundController.new()
	round_scene.configure(state.participants, DEFINITION, 1, 5)
	tree.root.add_child(round_scene)
	round_scene.set_physics_process(false)
	round_scene.begin_live()
	var stage := round_scene.stage as ComputerBugsStage
	var chair := round_scene.chairs[0]
	chair.stop_drive()
	var hits: Array[int] = []
	stage.elimination_requested.connect(func(seat: int, _reason: StringName): hits.append(seat))
	stage.set("_elapsed", stage.first_infection)
	stage.call("_infect", 0)
	var desk := stage.computer_position(0)
	chair.position = desk + Vector2(60, 40)
	stage.call("_sweep_chairs")
	check.call(hits.is_empty(), "Standing in a fresh zone is safe until it is armed")
	stage.set("_elapsed", stage.first_infection + stage.warning_seconds + 0.1)
	chair.position = desk + Vector2(ComputerBugsStage.ZONE_RADIUS + 25, 0)
	stage.call("_sweep_chairs")
	check.call(hits.is_empty(), "A chair outside the zone is untouched")
	check.call(
		stage.is_safe(chair.position + Vector2(260, 0)), "Open floor away from the zone is safe"
	)
	chair.position = desk + Vector2(60, 40)
	stage.call("_sweep_chairs")
	check.call(hits == [chair.seat], "Standing in an armed zone eliminates the chair")
	check.call(
		chair.knockout_velocity != Vector3.ZERO, "The bugs send the chair flying, not vanishing"
	)
	round_scene._commit_eliminations()
	check.call(
		not chair.active and round_scene.phase == RoundController.Phase.RESOLVING,
		"Bug elimination uses shared round rules"
	)
	# The zone swells over time, so a spot that was safe becomes lethal.
	var spot := desk + Vector2(ComputerBugsStage.ZONE_RADIUS + 60, 0)
	var early := stage.zone_radius(0)
	check.call(
		early < spot.distance_to(desk) and stage.is_safe(spot + Vector2(120, 0)),
		"A spot just beyond a young zone is safe"
	)
	stage.set("_elapsed", stage.first_infection + stage.zone_growth_seconds)
	var late := stage.zone_radius(0)
	check.call(
		late > early * 1.8 and late <= ComputerBugsStage.MAX_ZONE_RADIUS,
		"The bug range increases over time, up to its cap: %d to %d" % [early, late]
	)
	var second := round_scene.chairs[1]
	second.stop_drive()
	second.position = spot
	hits.clear()
	stage.call("_sweep_chairs")
	check.call(hits == [second.seat], "The grown zone now eliminates where it was once safe")
	check.call(not stage.is_safe(spot), "AI keeps clear of the grown zone")
	stage.call("_refresh")
	check.call(
		(
			stage.get("_zone_data")[0].z
			> ComputerBugsStage.ZONE_RADIUS / RenderStyle.PIXELS_PER_UNIT * 1.5
		),
		"The floor decal widens with the zone"
	)
	_test_fusion(stage, check)
	var escape := stage.safe_target(desk + Vector2(30, 20))
	check.call(stage.is_safe(escape), "AI receives a safe target away from a broken computer")
	var seats_clear := true
	var poses := SpawnLayout.poses(stage, 10)
	for pose in poses:
		seats_clear = seats_clear and stage.is_spawn_safe(pose.origin, 34 * stage.content_scale + 5)
	check.call(poses.size() == 10 and seats_clear, "Ten seats start clear of workstations")
	round_scene.queue_free()
	await tree.process_frame


func _test_fixer(tree: SceneTree, check: Callable) -> void:
	var stage := DEFINITION.scene.instantiate() as ComputerBugsStage
	tree.root.add_child(stage)
	var world := Node3D.new()
	tree.root.add_child(world)
	stage.create_presentation(world, 1.0 / RenderStyle.PIXELS_PER_UNIT)
	await tree.physics_frame
	stage.start_round()
	stage.set("_elapsed", 5.0)
	stage.call("_infect", 2)
	stage.call("_infect", 5)
	stage.set("_fixer_ready_at", 5.0)
	stage.set("_next_spread", INF)
	var clear_of_desks := true
	var order: Array[int] = []
	var spans: Array[float] = []
	var started := 0.0
	for frame in 60 * 60:
		stage.tick_hazards(STEP)
		for desk in stage.computers:
			var offset: Vector2 = stage.fixer_position - desk.global_position
			if (
				stage.fixer_state != ComputerBugsStage.Fixer.HIDDEN
				and absf(offset.x) < 86.0
				and absf(offset.y) < 50.0
			):
				clear_of_desks = false
		var target: int = stage.fixer_target
		if (
			stage.fixer_state == ComputerBugsStage.Fixer.REPAIRING
			and (order.is_empty() or order[-1] != target)
		):
			order.append(target)
			started = frame * STEP
		if stage.fixer_state == ComputerBugsStage.Fixer.REPAIRING and spans.size() < order.size():
			spans.append(0.0)
		if stage.fixer_state == ComputerBugsStage.Fixer.REPAIRING:
			spans[order.size() - 1] = frame * STEP - started
	check.call(clear_of_desks, "The technician walks the aisles instead of through desks")
	check.call(order.size() == 2, "The technician repairs both computers, one after another")
	check.call(
		stage.infected_count() == 0 and stage.repairs_total == 2,
		"Repaired computers are clean again"
	)
	check.call(
		spans.size() == 2 and spans[0] >= stage.minimum_repair - 0.1,
		"Each repair takes the full repair time"
	)
	check.call(
		not stage.get("_screens")[2].visible and stage.get("_zone_data")[2].w < 0.5,
		"A repaired computer loses its glitch screen and danger zone"
	)
	world.queue_free()
	stage.queue_free()
	await tree.process_frame


func _test_ramp(stage: ComputerBugsStage, check: Callable) -> void:
	stage.set("_elapsed", 0.0)
	var slow_fixer := stage.current_fixer_speed()
	var slow_repair := stage.current_repair_seconds()
	var slow_spread := stage.current_spread()
	stage.set("_elapsed", stage.escalation_seconds)
	check.call(
		(
			stage.current_fixer_speed() > slow_fixer * 1.8
			and stage.current_repair_seconds() < slow_repair * 0.6
		),
		"The fixer walks and repairs faster as the round goes on"
	)
	check.call(stage.current_spread() < 1.0, "Infection ends up very fast")
	check.call(
		(
			stage.current_fixer_speed() <= stage.fixer_top_speed
			and (
				(
					stage.current_repair_seconds()
					+ (
						stage.computer_position(0).distance_to(stage.computer_position(7))
						/ stage.current_fixer_speed()
					)
				)
				> stage.current_spread() * 2.0
			)
		),
		"Even at its best the fixer is slower than the infection"
	)
	check.call(
		stage.columns_per_wave() > 1 and slow_spread > stage.current_spread() * 4.0,
		"Later waves send several faster columns at once"
	)
	# Targets are anywhere in the office, not just the nearest neighbour.
	for index in stage.computers.size():
		stage.infected[index] = false
		stage.get("_inbound")[index] = false
	stage.infected[0] = true
	stage.set("fixer_target", -1)
	var targets := {}
	for attempt in 40:
		stage.get("_columns").clear()
		for index in stage.computers.size():
			stage.get("_inbound")[index] = false
		stage.call("_send_column")
		for column in stage.get("_columns"):
			targets[column.target] = true
	check.call(
		targets.size() >= 4, "Infection jumps to random computers: %d targets" % targets.size()
	)
	stage.get("_columns").clear()
	for index in stage.computers.size():
		stage.get("_inbound")[index] = false


func _test_fusion(stage: ComputerBugsStage, check: Callable) -> void:
	for index in stage.computers.size():
		stage.infected[index] = false
	var a := 0
	var b := 2
	var gap := stage.computer_position(a).distance_to(stage.computer_position(b))
	stage.set("_elapsed", 10.0)
	stage.infected[a] = true
	stage.infected[b] = true
	var age := 0.0
	while age < stage.zone_growth_seconds:
		stage.get("_infected_at")[a] = 10.0 - age
		stage.get("_infected_at")[b] = 10.0 - age
		if stage.zone_radius(a) >= gap / 2.1:
			break
		age += 0.02
	var radius := stage.zone_radius(a)
	var middle := (stage.computer_position(a) + stage.computer_position(b)) * 0.5
	check.call(
		radius < gap * 0.5 and stage.in_danger(middle),
		"Nearly touching zones fuse into one flowing shape between them"
	)
	stage.infected[b] = false
	check.call(
		not stage.in_danger(middle), "A lone zone covers exactly its own radius, not the gap"
	)
	stage.infected[b] = true
	var far := stage.computer_position(a) + Vector2(0, -radius * 1.2)
	check.call(
		not stage.in_danger(far), "The fused shape is still tight around the zones' outer edge"
	)
	for index in stage.computers.size():
		stage.infected[index] = false
