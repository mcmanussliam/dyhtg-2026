extends RefCounted
## Fast-forward is confined to spectating and never leaks engine timing across screens.


func run(tree: SceneTree, check: Callable) -> void:
	var normal_scale := Engine.time_scale
	var normal_rate := Engine.physics_ticks_per_second
	var normal_steps := Engine.max_physics_steps_per_frame
	var config := MatchConfig.new()
	config.player_count = 4
	var state := MatchState.new()
	state.configure(config)
	var round_scene := preload("res://game/round/round.tscn").instantiate() as RoundController
	round_scene.configure(
		state.participants,
		preload("res://game/stage/a_floor_in_the_crack/a_floor_in_the_crack.tres"),
		1,
		5
	)
	tree.root.add_child(round_scene)
	round_scene.set_physics_process(false)
	var speed := round_scene.get("_spectator") as SpectatorSpeed
	Input.action_press("spectator_fast_forward")
	speed.refresh()
	check.call(Engine.time_scale == normal_scale, "Cannot fast-forward introduction")
	round_scene.begin_live()
	speed.refresh()
	check.call(Engine.time_scale == normal_scale, "Cannot fast-forward while the human is alive")
	check.call(
		not speed.get("_instruction").visible, "No instruction is shown while the human is alive"
	)
	round_scene.request_elimination(0, &"fall")
	round_scene._commit_eliminations()
	speed.refresh()
	check.call(
		not speed.get("_hint").visible, "Fast-forward indicator is hidden until accelerating"
	)
	check.call(
		speed.get("_instruction").visible,
		"After elimination a visible instruction explains how to fast forward"
	)
	check.call(
		Engine.time_scale == normal_scale,
		"Held steering at elimination does not trigger acceleration"
	)
	Input.action_release("spectator_fast_forward")
	speed.refresh()
	Input.action_press("spectator_fast_forward")
	speed.refresh()
	check.call(
		Engine.time_scale == normal_scale * 3, "Holding Right accelerates remaining AI combat"
	)
	check.call(speed.get("_hint").visible, "Fast-forward indicator shows while accelerating")
	check.call(
		not speed.get("_instruction").visible,
		"The instruction gives way to the 3x badge while holding"
	)
	var instruction_box: PanelContainer = speed.get("_instruction")
	var badge_box: PanelContainer = speed.get("_hint")
	await tree.process_frame
	var window := speed.get_viewport().get_visible_rect()
	var box := instruction_box.get_global_rect()
	check.call(
		absf(box.get_center().x - window.get_center().x) < 2.0,
		"The box is centred horizontally above the faces"
	)
	check.call(
		box.end.y <= window.end.y - 120.0 and box.end.y >= window.end.y - 160.0,
		"The box sits just above the row of character faces"
	)
	instruction_box.show()
	badge_box.show()
	await tree.process_frame
	for panel in [instruction_box, badge_box]:
		var content: Rect2
		var started := false
		for node in panel.find_children("*", "Control", true, false):
			if node is HBoxContainer:
				continue
			var rect: Rect2 = node.get_global_rect()
			content = rect if not started else content.merge(rect)
			started = true
		check.call(
			absf(content.get_center().x - panel.get_global_rect().get_center().x) < 2.0,
			"Symbol and text are centred inside the box in both states"
		)
	instruction_box.hide()
	badge_box.hide()
	var square: StyleBoxFlat = instruction_box.get_theme_stylebox("panel")
	check.call(
		square.corner_radius_top_left == 0 and square.bg_color.a < 1.0,
		"The box is square-cornered and transparent"
	)
	check.call(
		(
			instruction_box.position == badge_box.position
			and instruction_box.custom_minimum_size == badge_box.custom_minimum_size
			and instruction_box.custom_minimum_size.x > 200.0
		),
		"The instruction and the fast-forward badge share one fixed box size and spot"
	)
	var line_count := 0
	for node in instruction_box.find_children("*", "Label", true, false):
		line_count += 1
		check.call(
			node.text.find("\n") < 0 and node.get_theme_color("font_color") == Color.WHITE,
			"The instruction is a single line of white text"
		)
	check.call(line_count == 1, "The instruction has exactly one text line")

	check.call(
		Engine.physics_ticks_per_second == normal_rate * 3,
		"Fast-forward increases physics frequency to retain simulation step size"
	)
	Input.action_release("spectator_fast_forward")
	speed.refresh()
	check.call(
		Engine.time_scale == normal_scale and Engine.physics_ticks_per_second == normal_rate,
		"Releasing fast-forward restores normal timing"
	)
	Input.action_press("spectator_fast_forward")
	speed.refresh()
	speed.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check.call(Engine.time_scale == normal_scale, "Losing application focus stops fast-forward")
	speed.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	Input.action_release("spectator_fast_forward")
	speed.refresh()
	Input.action_press("spectator_fast_forward")
	speed.refresh()
	round_scene.request_elimination(1, &"fall")
	round_scene.request_elimination(2, &"fall")
	round_scene._physics_process(0.0)
	check.call(
		Engine.time_scale == normal_scale and not speed.get("_hint").visible,
		"Winner resolution stops fast-forward and removes its prompt"
	)
	check.call(
		not speed.get("_instruction").visible,
		"The instruction disappears once the round is decided"
	)
	# A round removed while accelerated must also release ownership of engine timing.
	var owner := SpectatorSpeed.new()
	owner.can_fast_forward = func(): return true
	tree.root.add_child(owner)
	Input.action_release("spectator_fast_forward")
	owner.refresh()
	Input.action_press("spectator_fast_forward")
	owner.refresh()
	owner.free()
	check.call(
		(
			Engine.time_scale == normal_scale
			and Engine.physics_ticks_per_second == normal_rate
			and Engine.max_physics_steps_per_frame == normal_steps
		),
		"Removing a fast-forward owner restores all engine timing settings"
	)
	Input.action_release("spectator_fast_forward")
	round_scene.queue_free()
	await tree.process_frame
