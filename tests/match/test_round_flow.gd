extends RefCounted
## Deterministic round lifecycle checks using real stage and chair scenes.

const ROUND = preload("res://game/round/round.tscn")
const CHAIR = preload("res://game/chair/chair.tscn")
const STAGE = preload("res://game/stage/a_floor_in_the_crack/a_floor_in_the_crack.tres")


func run(tree: SceneTree, check: Callable) -> void:
	var config := MatchConfig.new()
	config.wins_needed = 5
	config.player_count = 3
	var state := MatchState.new()
	state.configure(config)
	var round_scene := ROUND.instantiate() as RoundController
	round_scene.configure(state.participants, STAGE, 7, 5)
	tree.root.add_child(round_scene)
	round_scene.set_physics_process(false)
	var completions: Array[Vector2i] = []
	round_scene.completed.connect(
		func(id: int, winner: int) -> void: completions.append(Vector2i(id, winner))
	)
	check.call(
		(
			round_scene.get("_intro_background").color == Color.BLACK
			and round_scene.get("_intro_background").visible
		),
		"Introduction is opaque plain black behind text"
	)
	check.call(
		round_scene.get("_title").text == STAGE.display_name, "Round intro shows only the map name"
	)
	var indicators := round_scene.get("_indicators") as RoundRoster
	check.call(not indicators.visible, "Round introduction hides the character roster")
	check.call(indicators.get_child_count() == 3, "Roster contains every participant model")
	var intro_ready := true
	for chair in round_scene.chairs:
		intro_ready = intro_ready and chair.freeze and not chair.spraying
	check.call(intro_ready, "Intro freezes every chair and disables every extinguisher")
	check.call(not round_scene.stage.round_running, "Stage hazards are stopped during intro")
	round_scene.stage.elimination_requested.emit(0, &"fire")
	round_scene.begin_live()
	check.call(
		not round_scene.get("_intro_background").visible,
		"Black introduction reveals stage only when live"
	)
	check.call(indicators.visible, "Live play shows the bottom character roster")
	var live_ready := true
	for chair in round_scene.chairs:
		live_ready = live_ready and not chair.freeze and chair.spraying and chair.active
	check.call(live_ready, "Round begins all chairs and extinguishers together")
	check.call(round_scene.stage.round_running, "Round starts stage hazards")
	round_scene.begin_live()
	round_scene._physics_process(0.016)
	check.call(round_scene.chairs[0].active, "Intro hazard requests cannot leak into live play")
	round_scene.request_elimination(-1, &"fall")
	round_scene.request_elimination(9, &"fall")
	round_scene.stage.elimination_requested.emit(1, &"fire")
	round_scene.request_elimination(1, &"fire")
	round_scene._physics_process(0.016)
	check.call(not round_scene.chairs[1].active, "Stage hazard eliminates its requested seat")
	check.call(indicators.is_eliminated(1), "Eliminated player portrait is greyed out")
	check.call(not indicators.is_eliminated(0), "Surviving player portrait retains its colour")
	check.call(round_scene.chairs[0].active, "Invalid and duplicate requests preserve other seats")
	check.call(round_scene.phase == RoundController.Phase.LIVE, "Two survivors keep round live")
	# Both remaining chairs leave the platform in the same physics batch.
	round_scene.chairs[0].global_position = Vector2(-1000, -1000)
	round_scene.chairs[2].global_position = Vector2(-1000, -1000)
	round_scene._physics_process(0.016)
	check.call(
		round_scene.chairs[0].active and round_scene.chairs[2].active,
		"Unsupported chairs remain alive while native falling starts"
	)
	round_scene.chairs[0].confirm_fall()
	round_scene.chairs[2].confirm_fall()
	round_scene._physics_process(0.016)
	check.call(
		round_scene.phase == RoundController.Phase.RESOLVING,
		"Confirmed simultaneous falls enter one resolving phase"
	)
	check.call(not round_scene.stage.round_running, "Resolution stops stage hazards")
	check.call(
		indicators.is_eliminated(0) and indicators.is_eliminated(2),
		"Simultaneous deaths update every affected portrait"
	)
	round_scene._physics_process(round_scene.resolve_duration)
	round_scene._physics_process(round_scene.resolve_duration)
	check.call(completions == [Vector2i(7, -1)], "Simultaneous final falls emit exactly one draw")
	check.call(not indicators.visible, "Finished round hides the roster before scores")
	round_scene.begin_live()
	check.call(round_scene.phase == RoundController.Phase.FINISHED, "Finished round cannot restart")
	round_scene.queue_free()
	await tree.process_frame
	await _test_match_lifetime(tree, check)
	await _test_cancelled_transitions(tree, check)
	await _test_startup_ramp(tree, check)
	await _test_ramped_push(tree, check)


func _test_match_lifetime(tree: SceneTree, check: Callable) -> void:
	var match_controller := MatchController.new()
	tree.root.add_child(match_controller)
	var config := MatchConfig.new()
	config.player_count = 2
	config.wins_needed = 2
	match_controller.start(config)
	var first := match_controller.round
	first.set_physics_process(false)
	var result_count: Array[int] = [0]
	match_controller.results_ready.connect(
		func(_roster, _winner, _target, _final, _number) -> void: result_count[0] += 1
	)
	first.begin_live()
	first.request_elimination(1, &"fall")
	first._physics_process(0.016)
	first.request_elimination(0, &"fall")
	first._physics_process(first.resolve_duration)
	check.call(
		match_controller.state.participants[0].wins == 1, "Sole survivor earns one round win"
	)
	check.call(first.chairs[0].active, "Late hazard cannot eliminate winner during resolution")
	first.completed.emit(first.round_id, 0)
	check.call(result_count[0] == 1, "Repeated completion cannot emit duplicate results")
	match_controller.continue_round()
	match_controller.continue_round()
	await tree.process_frame
	var next := match_controller.round
	next.set_physics_process(false)
	check.call(next != first, "Continue replaces the completed round")
	check.call(
		match_controller.state.round_number == 2, "Repeated continue advances only one round"
	)
	check.call(match_controller.state.participants[0].wins == 1, "Fresh round preserves scores")
	check.call(next.phase == RoundController.Phase.INTRO, "Fresh round returns to disabled intro")
	next.begin_live()
	next.request_elimination(1, &"fall")
	next._physics_process(0.016)
	next._physics_process(next.resolve_duration)
	check.call(match_controller.state.winner_id == 0, "Target round win finishes first-to-N match")
	match_controller.continue_round()
	await tree.process_frame
	check.call(match_controller.round == next, "Final match cannot continue another round")
	match_controller.start(config)
	match_controller.round.set_physics_process(false)
	check.call(match_controller.state.winner_id == -1, "Rematch clears match winner")
	check.call(match_controller.state.participants[0].wins == 0, "Rematch clears scores")
	check.call(match_controller.state.round_number == 1, "Rematch starts at round one")
	match_controller.queue_free()
	await tree.process_frame


func _test_cancelled_transitions(tree: SceneTree, check: Callable) -> void:
	var controller := MatchController.new()
	tree.root.add_child(controller)
	var config := MatchConfig.new()
	config.player_count = 2
	config.wins_needed = 5
	controller.start(config)
	_finish_round(controller.round)
	controller.continue_round()
	controller.start(config)
	var restarted := controller.round
	restarted.set_physics_process(false)
	await tree.process_frame
	check.call(controller.round == restarted, "Restart cancels queued round replacement")
	check.call(controller.state.round_number == 1, "Cancelled continue cannot advance rematch")
	check.call(
		controller.state.participants[0].wins == 0, "Cancelled continue preserves reset scores"
	)
	_finish_round(restarted)
	controller.continue_round()
	tree.root.remove_child(controller)
	await tree.process_frame
	check.call(controller.round == restarted, "Removed match cannot execute queued continuation")
	check.call(controller.state.round_number == 1, "Removed match cannot advance its round counter")
	controller.free()
	await tree.process_frame


func _test_startup_ramp(tree: SceneTree, check: Callable) -> void:
	var config := MatchConfig.new()
	config.player_count = 2
	config.wins_needed = 5
	var state := MatchState.new()
	state.configure(config)
	for definition in config.stages:
		var round_scene := ROUND.instantiate() as RoundController
		round_scene.configure(state.participants, definition, 1, 5)
		tree.root.add_child(round_scene)
		round_scene.set_physics_process(false)
		round_scene._physics_process(round_scene.intro_duration)
		var immediate := (
			round_scene.phase == RoundController.Phase.LIVE and round_scene.stage.round_running
		)
		for chair in round_scene.chairs:
			immediate = (
				immediate and not chair.freeze and chair.spraying and chair.jet_strength == 0
			)
		check.call(
			immediate,
			"Every map starts steering immediately with an unpressurized jet: %s" % definition.id
		)
		var chair := round_scene.chairs[0]
		chair.command.turn = 1
		for frame in 30:
			chair.step(1.0 / 60)
			await tree.physics_frame
		check.call(
			chair.angular_velocity > 0.5 and chair.jet_strength > 0 and chair.jet_strength < 0.25,
			"Steering remains responsive while thrust builds: %s" % definition.id
		)
		check.call(
			chair.linear_velocity.length() > 1,
			"Startup produces gradual movement rather than a pause: %s" % definition.id
		)
		round_scene.queue_free()
		await tree.process_frame


func _finish_round(round_scene: RoundController) -> void:
	round_scene.set_physics_process(false)
	round_scene.begin_live()
	round_scene.request_elimination(1, &"fall")
	round_scene._physics_process(0.016)
	round_scene._physics_process(round_scene.resolve_duration)


func _test_ramped_push(tree: SceneTree, check: Callable) -> void:
	var source := CHAIR.instantiate() as Chair
	var target := CHAIR.instantiate() as Chair
	source.get_node("Visuals").free()
	target.get_node("Visuals").free()
	tree.root.add_child(source)
	tree.root.add_child(target)
	source.position = Vector2(4000, 4000)
	source.rotation = 0
	source.freeze = true
	source.start_extinguisher_ramp(2.0)
	var spray := SpraySystem.new()
	var speeds: Array[float] = []
	for elapsed in [0.0, 1.0, 1.0]:
		target.position = source.position + Vector2(100, 0)
		target.linear_velocity = Vector2.ZERO
		await tree.physics_frame
		source.step(elapsed)
		spray.apply(source, [source, target], 1.0 / 60)
		await tree.physics_frame
		speeds.append(target.linear_velocity.x)
	check.call(is_zero_approx(speeds[0]), "Unpressurized startup spray cannot shove opponents")
	check.call(
		speeds[1] > 0 and speeds[2] > speeds[1] * 1.9,
		"Opponent knockback builds with extinguisher pressure"
	)
	check.call(source.jet_strength == 1, "Startup reaches and retains full power after two seconds")
	source.prepare_round()
	check.call(
		source.jet_strength == 0 and not source.spraying,
		"Reset clears startup pressure and switches spray off"
	)
	source.queue_free()
	target.queue_free()
	await tree.process_frame
