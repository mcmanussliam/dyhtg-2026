extends RefCounted
## Exercise the real app and keyboard-only paths without touching live scoring.


func run(tree: SceneTree, check: Callable) -> void:
	var app := GameApp.new()
	tree.root.add_child(app)
	await tree.process_frame
	check.call(
		is_instance_valid(app.current_menu) and app.current_menu.chosen == 0,
		"App boots into focused home menu"
	)
	check.call(
		app.screen.find_children("*", "Label", true, false).size() == 2,
		"Home displays only Play and Quit text"
	)
	await _tap(tree, &"menu_activate")
	await tree.process_frame
	check.call(
		app.screen.find_children("*", "Label", true, false).size() == 4,
		"Setup displays only its four options"
	)
	check.call(app.current_menu._items.size() == 4, "Right opens match setup")
	for index in 3:
		await _tap(tree, &"menu_activate")
	check.call(app.config.ai_count == 1, "AI setup value wraps from three to one")
	await _tap(tree, &"menu_next")
	await _tap(tree, &"menu_activate")
	check.call(app.config.wins_needed == 1, "First-to target wraps from five to one")
	await _tap(tree, &"menu_next")
	var held := InputEventKey.new()
	held.physical_keycode = KEY_RIGHT
	held.pressed = true
	Input.parse_input_event(held)
	await tree.process_frame
	await tree.process_frame
	check.call(
		not is_instance_valid(app.match_controller), "Held confirmation does not begin gameplay"
	)
	var released := held.duplicate() as InputEventKey
	released.pressed = false
	Input.parse_input_event(released)
	await tree.process_frame
	await tree.process_frame
	check.call(
		is_instance_valid(app.match_controller) and not is_instance_valid(app.screen),
		"Start replaces office menus with a match"
	)
	var pause := InputEventKey.new()
	pause.physical_keycode = KEY_ESCAPE
	pause.pressed = true
	Input.parse_input_event(pause)
	await tree.process_frame
	check.call(tree.paused, "Escape pauses normal match")
	Input.parse_input_event(pause.duplicate())
	await tree.process_frame
	check.call(not tree.paused, "Escape resumes normal match")
	var previous_round := app.match_controller.round
	previous_round.phase = RoundController.Phase.FINISHED
	app.match_controller._on_completed(previous_round.round_id, -1)
	await tree.process_frame
	check.call(app.screen is ResultsScreen, "Round result presents score screen")
	await _tap(tree, &"menu_activate")
	await tree.process_frame
	check.call(
		(
			app.match_controller.round != previous_round
			and app.match_controller.state.round_number == 2
		),
		"Continue replaces round and preserves match"
	)
	await tree.process_frame
	check.call(not is_instance_valid(previous_round), "Continue frees previous round nodes")
	app.match_controller.round.phase = RoundController.Phase.FINISHED
	app.match_controller._on_completed(app.match_controller.round.round_id, 0)
	await tree.process_frame
	check.call(
		app.match_controller.state.winner_id == 0 and app.screen is ResultsScreen,
		"Winning round opens final scores"
	)
	var old_match := app.match_controller
	await _tap(tree, &"menu_activate")
	await tree.process_frame
	check.call(
		app.match_controller != old_match and app.match_controller.state.participants[0].wins == 0,
		"Rematch resets scores in a fresh match"
	)
	await tree.process_frame
	check.call(not is_instance_valid(old_match), "Rematch frees previous match nodes")
	app.match_controller.round.phase = RoundController.Phase.FINISHED
	app.match_controller._on_completed(app.match_controller.round.round_id, 0)
	await tree.process_frame
	await _tap(tree, &"menu_next")
	await tree.process_frame
	check.call(
		not is_instance_valid(app.match_controller) and not tree.paused,
		"Home cleans match and pause state"
	)
	app.show_setup()
	await tree.process_frame
	app.current_menu.chosen = 3
	await _tap(tree, &"menu_activate")
	await tree.process_frame
	check.call(app.current_menu._items.size() == 2, "Setup Back returns to home using two keys")
	app.queue_free()
	await tree.process_frame


func _tap(tree: SceneTree, action: StringName) -> void:
	var press := InputEventKey.new()
	press.physical_keycode = KEY_LEFT if action == &"menu_next" else KEY_RIGHT
	press.pressed = true
	Input.parse_input_event(press)
	await tree.process_frame
	var release := InputEventKey.new()
	release.physical_keycode = press.physical_keycode
	Input.parse_input_event(release)
	await tree.process_frame
