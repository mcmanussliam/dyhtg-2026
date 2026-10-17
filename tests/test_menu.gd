extends RefCounted
## Menu input and score presentation regression checks, independent of match scoring.


func run(tree: SceneTree, check: Callable) -> void:
	var menu := TwoKeyMenu.new()
	tree.root.add_child(menu)
	menu.set_items(PackedStringArray(["One", "Two", "Three"]))
	var labels := menu.find_children("*", "Label", true, false)
	check.call(labels.size() == 3, "Menus contain only their option text")
	var all_white := true
	for label in labels:
		all_white = all_white and label.get_theme_color("font_color") == Color.WHITE
	check.call(all_white, "All menu options are plain white")
	check.call(
		menu.find_children("*", "PanelContainer", true, false).is_empty(),
		"Menus have no decorative panels"
	)
	var activations: Array[int] = []
	menu.activated.connect(func(index: int) -> void: activations.append(index))
	var next := InputEventAction.new()
	next.action = &"menu_next"
	next.pressed = true
	menu._unhandled_input(next)
	check.call(menu.chosen == 1, "Left advances menu selection")
	menu._unhandled_input(next)
	menu._unhandled_input(next)
	check.call(menu.chosen == 0, "Menu selection wraps")
	var confirm := InputEventAction.new()
	confirm.action = &"menu_activate"
	confirm.pressed = true
	menu._unhandled_input(confirm)
	check.call(activations == [0], "Right activates selected menu item")
	menu.hide()
	menu._unhandled_input(confirm)
	check.call(activations.size() == 1, "Hidden menu ignores input")
	menu.queue_free()
	await tree.process_frame
	var results := ResultsScreen.new()
	tree.root.add_child(results)
	var participants: Array[Dictionary] = [
		{"id": 0, "name": "Player 1", "colour": Color.WHITE, "wins": 1},
		{"id": 1, "name": "AI 1", "colour": Color.PINK, "wins": 0},
	]
	results.present(participants, 0, 3, false, 1)
	check.call(
		results.find_children("*", "VictoryConfetti", true, false).is_empty(),
		"Ordinary result has no confetti"
	)
	var background := results.get("_content").get_child(0) as ColorRect
	check.call(background.color == Color.BLACK, "Score screen background is plain black")
	check.call(
		results.find_children("*", "Label", true, false).is_empty(),
		"Score page has no extra text or options"
	)
	var portraits := results.find_children("*", "ScoreCharacter", true, false)
	check.call(
		portraits.size() == 2 and portraits[1].colour == Color.PINK,
		"Every score row shows its participant character colour"
	)
	var tokens := results.find_children("*", "WinTokens", true, false)
	check.call(
		tokens.size() == 2 and tokens[0].token_count == 1 and tokens[1].token_count == 0,
		"3D win tokens include stable zero-score row"
	)
	await tree.process_frame
	var portrait_render := portraits[0].get_child(0) as SubViewport
	var token_render := tokens[0].get_child(0) as SubViewport
	check.call(
		(
			portrait_render.size.x >= portraits[0].size.x * 4
			and portrait_render.size.y >= portraits[0].size.y * 4
		),
		"Character portraits retain supersampling after container layout"
	)
	check.call(
		token_render.size.x >= tokens[0].size.x * 4 and token_render.size.y >= tokens[0].size.y * 4,
		"Stars retain supersampling after container layout"
	)
	var portrait_centre: float = portraits[0].global_position.y + portraits[0].size.y * 0.5
	var token_centre: float = tokens[0].global_position.y + tokens[0].size.y * 0.5
	check.call(
		absf(portrait_centre - token_centre) < 1.0, "Portrait and star score rows align vertically"
	)
	results.present(participants, 0, 1, true, 1)
	check.call(
		results.find_children("*", "VictoryConfetti", true, false).size() == 1,
		"Final result has one celebration"
	)
	results.queue_free()
	await tree.process_frame
