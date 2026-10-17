extends RefCounted
## Timed advancement must be single-shot, cancel with the screen and ignore held steering.


func run(tree: SceneTree, check: Callable) -> void:
	var results := ResultsScreen.new()
	tree.root.add_child(results)
	var actions: Array[StringName] = []
	results.action_requested.connect(func(action: StringName): actions.append(action))
	var roster: Array[Dictionary] = [{"id": 0, "name": "You", "colour": Color.WHITE, "wins": 1}]
	results.present(roster, 0, 5, false, 1)
	results._process(2.9)
	check.call(actions.is_empty(), "Between-round score remains visible for its display time")
	results._process(0.2)
	results._process(100)
	check.call(actions == [&"continue"], "Between-round score automatically continues exactly once")
	results.present(roster, 0, 1, true, 1)
	results._process(4.9)
	check.call(actions.size() == 1, "Final score gives confetti time to play")
	results._process(0.2)
	results._process(100)
	check.call(
		actions == [&"continue", &"home"], "Final score automatically returns home exactly once"
	)
	results.queue_free()
	await tree.process_frame
	var app := GameApp.new()
	app.appearance_path = ""
	app.settings_path = ""
	tree.root.add_child(app)
	app.config.wins_needed = 1
	app._start_match()
	var previous := app.match_controller.round
	previous.set_physics_process(false)
	previous.phase = RoundController.Phase.FINISHED
	app.match_controller._on_completed(previous.round_id, -1)
	var held := InputEventKey.new()
	held.physical_keycode = KEY_RIGHT
	held.pressed = true
	Input.parse_input_event(held)
	(app.screen as ResultsScreen)._process(3.1)
	await tree.process_frame
	await tree.process_frame
	check.call(
		app.match_controller.round != previous,
		"Held fast-forward never blocks automatic next round"
	)
	app.match_controller.round.set_physics_process(false)
	app.match_controller.round.phase = RoundController.Phase.FINISHED
	app.match_controller._on_completed(app.match_controller.round.round_id, 0)
	(app.screen as ResultsScreen)._process(5.1)
	await tree.process_frame
	await tree.process_frame
	check.call(
		not is_instance_valid(app.match_controller) and is_instance_valid(app.current_menu),
		"Timed final celebration cleans the match and opens home"
	)
	held.pressed = false
	Input.parse_input_event(held)
	app.queue_free()
	await tree.process_frame
