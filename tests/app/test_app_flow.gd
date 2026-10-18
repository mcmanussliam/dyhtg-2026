extends RefCounted
## Exercise the real app and keyboard-only paths without touching live scoring.


func run(tree: SceneTree, check: Callable) -> void:
	var app := GameApp.new()
	app.appearance_path = ""
	app.settings_path = ""
	tree.root.add_child(app)
	await tree.process_frame
	check.call(
		is_instance_valid(app.current_menu) and app.current_menu.chosen == 0,
		"App boots into focused home menu"
	)
	check.call(
		_shown_text(app.screen) == [">", "Play", "Customise", "Settings", "Quit"],
		"Home displays Play, Customise, Settings and Quit"
	)
	await _tap(tree, &"menu_next")
	await _tap(tree, &"menu_activate")
	await tree.process_frame
	check.call(
		app.current_menu._items == PackedStringArray(["Hat", "Top", "Colour", "Back"]),
		"Customisation contains three categories and two-key Back navigation"
	)
	var original_colour := app.config.player_colour
	for index in 2:
		await _tap(tree, &"menu_activate")
		check.call(
			app.config.player_colour == original_colour,
			"Body selection does not alter the character colour (%d)" % index
		)
		await _tap(tree, &"menu_next")
	check.call(
		(
			app.config.appearance.body_id == &"jpmorgan_tshirt"
			and app.get("_backdrop").skin.id == &"jpmorgan_tshirt"
		),
		"Body selection equips the T-shirt in the live preview"
	)
	check.call(
		(
			app.config.appearance.hat_id == &"traffic_cone"
			and app.get("_backdrop").hat_id == &"traffic_cone"
		),
		"Hat selection updates the live preview independently of the top"
	)
	for index in CharacterAppearance.COLOUR_IDS.size():
		await _tap(tree, &"menu_activate")
	check.call(
		(
			app.current_menu.get("_values")[2] == "Random"
			and app.config.player_colour in CharacterAppearance.PALETTE
		),
		"Colour cycles through the palette and includes Random"
	)
	var chosen_colour := app.config.player_colour
	var backdrop := app.get("_backdrop") as HomeBackdrop
	check.call(
		backdrop.character_colour == chosen_colour, "Colour updates the live character preview"
	)
	await _tap(tree, &"menu_next")
	await _tap(tree, &"menu_activate")
	await tree.process_frame
	check.call(app.config.player_colour == chosen_colour, "Selected colour survives returning home")
	await _tap(tree, &"menu_activate")
	await tree.process_frame
	check.call(
		_shown_text(app.screen).size() == 6, "Setup displays only its five options and a marker"
	)
	check.call(app.current_menu._items.size() == 5, "Right opens match setup")
	check.call(app.current_menu._items[0] == "Players 2", "Setup counts all players")
	for index in 9:
		await _tap(tree, &"menu_activate")
	check.call(app.config.player_count == 2, "Player setup value wraps from ten to two")
	await _tap(tree, &"menu_next")
	await _tap(tree, &"menu_activate")
	check.call(app.config.wins_needed == 1, "First-to target wraps from five to one")
	await _tap(tree, &"menu_next")
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
	check.call(
		app.match_controller.state.participants[0].colour == chosen_colour,
		"The match roster uses the previewed player colour"
	)
	var colours := {}
	for participant in app.match_controller.state.participants:
		colours[participant.colour] = true
	check.call(
		colours.size() == app.match_controller.state.participants.size(),
		"AI colours avoid the selected player colour"
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
		not is_instance_valid(app.match_controller) and is_instance_valid(app.current_menu),
		"Confirming final scores returns to main menu instead of starting a rematch"
	)
	await tree.process_frame
	check.call(not is_instance_valid(old_match), "Returning home frees the finished match")
	check.call(not tree.paused, "Home clears pause state")
	app.show_setup()
	await tree.process_frame
	app.current_menu.chosen = 4
	await _tap(tree, &"menu_activate")
	await tree.process_frame
	check.call(app.current_menu._items.size() == 4, "Setup Back returns to home using two keys")
	app.current_menu.chosen = 2
	await _tap(tree, &"menu_activate")
	await tree.process_frame
	check.call(app.current_menu is SettingsMenu, "Home opens Settings using two keys")
	check.call(
		app.current_menu._items == PackedStringArray(["Anti-aliasing", "Shadow quality", "Back"]),
		"Settings contains only the two graphics options and Back"
	)
	var original_aa: int = app.settings.values.aa
	app.current_menu.chosen = 0
	await _tap(tree, &"menu_activate")
	check.call(app.settings.values.aa != original_aa, "Right changes the selected setting")
	app.current_menu.chosen = 2
	await _tap(tree, &"menu_activate")
	await tree.process_frame
	check.call(app.current_menu._items[2] == "Settings", "Settings Back returns home")
	check.call(
		app.config.player_colour == chosen_colour, "Settings never alter character appearance"
	)
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


## Non-empty label text on screen, in tree order: each menu row's marker then its option.
func _shown_text(screen: Control) -> Array:
	return (
		screen
		. find_children("*", "Label", true, false)
		. map(func(label: Label): return label.text)
		. filter(func(text: String): return not text.is_empty())
	)
