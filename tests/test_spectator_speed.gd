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
		state.participants, preload("res://game/stage/a_floor_in_the_crack.tres"), 1, 5
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
	round_scene.request_elimination(0, &"fall")
	round_scene._commit_eliminations()
	speed.refresh()
	check.call(speed.get("_hint").visible, "Spectating displays the hold-to-fast-forward prompt")
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
	tree.paused = true
	await tree.process_frame
	await tree.process_frame
	check.call(
		Engine.time_scale == normal_scale, "Pause restores normal timing even under a paused parent"
	)
	tree.paused = false
	Input.action_release("spectator_fast_forward")
	speed.refresh()
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
