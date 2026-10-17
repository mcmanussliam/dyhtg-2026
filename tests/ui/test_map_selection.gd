extends RefCounted
## The actual two-key app path, including an empty pool and a single-map match.


func run(tree: SceneTree, check: Callable) -> void:
	var app := GameApp.new()
	app.appearance_path = ""
	app.settings_path = ""
	tree.root.add_child(app)
	app.show_setup()
	await tree.process_frame
	check.call(
		app.config.stages.size() == MatchConfig.STAGE_PATHS.size(),
		"Every testing map starts selected"
	)
	await _tap(tree, KEY_LEFT)
	await _tap(tree, KEY_LEFT)
	check.call(
		app.current_menu._items[app.current_menu.chosen] == "Select maps",
		"Setup exposes Maps through two-key navigation"
	)
	await _tap(tree, KEY_RIGHT)
	await tree.process_frame
	var menu := app.current_menu as MapSelectionMenu
	check.call(
		menu != null and menu._items[0] == "Back", "Map selection opens with Back at the top"
	)
	var names := PackedStringArray(["Back"])
	for definition in MatchConfig.available_stages():
		names.append(definition.display_name)
	check.call(
		menu._items == names, "The map page lists every authored map name without extra copy"
	)
	for row in range(1, names.size()):
		check.call(
			(
				menu._rows[row].text.ends_with("✓")
				and menu._rows[row].get_theme_color("font_color") == Color.WHITE
			),
			"Enabled maps display white text and a tick"
		)
	for step in names.size() - 1:
		await _tap(tree, KEY_LEFT)
	await tree.process_frame
	check.call(
		menu.get_global_rect().encloses(menu._rows[menu.chosen].get_global_rect()),
		"Keyboard navigation scrolls the final map fully into view"
	)
	check.call(menu._scroll.scroll_vertical > 0, "Overflowing map list scrolls inside its bounds")
	await _tap(tree, KEY_RIGHT)
	check.call(not menu._rows[-1].text.contains("✓"), "Last visible map can be toggled off")
	await _tap(tree, KEY_RIGHT)
	await _tap(tree, KEY_LEFT)
	await tree.process_frame
	check.call(
		menu.chosen == 0 and menu._scroll.scroll_vertical == 0,
		"Wrapping to Back returns the list to the top"
	)
	await _tap(tree, KEY_LEFT)
	await _tap(tree, KEY_RIGHT)
	check.call(
		(
			not menu._rows[1].text.contains("✓")
			and menu._rows[1].get_theme_color("font_color") == Color(0.45, 0.45, 0.45)
		),
		"Right deselects a map and shows grey text without a tick"
	)
	await _tap(tree, KEY_RIGHT)
	check.call(menu._rows[1].text.ends_with("✓"), "Unchecked maps remain selectable")
	await _tap(tree, KEY_RIGHT)
	for row in range(2, names.size()):
		await _tap(tree, KEY_LEFT)
		await _tap(tree, KEY_RIGHT)
	check.call(app.config.stages.is_empty(), "All maps can be unchecked")
	await _tap(tree, KEY_LEFT)
	await _tap(tree, KEY_RIGHT)
	await tree.process_frame
	check.call(
		not app.current_menu is MapSelectionMenu and app.current_menu._items[2] == "Select maps",
		"Back returns to game setup"
	)
	for step in 3:
		await _tap(tree, KEY_LEFT)
	await _tap(tree, KEY_RIGHT)
	check.call(
		not is_instance_valid(app.match_controller),
		"An empty map pool cannot start or silently use a fallback"
	)
	check.call(
		app.current_menu._rows[3].get_theme_color("font_color") == Color(0.45, 0.45, 0.45),
		"Start match is visibly inactive with no maps selected"
	)
	while app.current_menu.chosen != 2:
		await _tap(tree, KEY_LEFT)
	await _tap(tree, KEY_RIGHT)
	await tree.process_frame
	menu = app.current_menu as MapSelectionMenu
	check.call(
		menu._rows.slice(1).all(func(row: Label) -> bool: return not row.text.contains("✓")),
		"Map selections survive leaving and reopening the list"
	)
	for step in 4:
		await _tap(tree, KEY_LEFT)
	await _tap(tree, KEY_RIGHT)
	check.call(
		app.config.stages.size() == 1 and app.config.stages[0].id == &"hr_training",
		"A single testing map can be enabled independently"
	)
	while menu.chosen != 0:
		await _tap(tree, KEY_LEFT)
	await _tap(tree, KEY_RIGHT)
	await tree.process_frame
	for step in 3:
		await _tap(tree, KEY_LEFT)
	await _tap(tree, KEY_RIGHT)
	await tree.process_frame
	check.call(
		is_instance_valid(app.match_controller), "Re-enabling a map makes Start match work again"
	)
	var match_config := app.match_controller.config
	var selected_only := true
	for number in range(1, 21):
		selected_only = selected_only and match_config.stage_for_round(number).id == &"hr_training"
	check.call(
		selected_only and app.match_controller.round.stage.name == "HRTraining",
		"Both the live round and later random draws exclude unchecked maps"
	)
	app.queue_free()
	await tree.process_frame


func _tap(tree: SceneTree, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await tree.process_frame
	event = InputEventKey.new()
	event.physical_keycode = key
	Input.parse_input_event(event)
	await tree.process_frame
