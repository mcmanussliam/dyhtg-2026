extends SceneTree
## Native frame-time probe for the arena reveal, first foam and first bull windup.
## Run with --path . --script tools/profile_round_start.gd [-- --players=10].
## Wall-clock frames include rendering/OS scheduling; tick time measures script work.


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Use a graphical run to measure first-use rendering stalls.")
		quit(1)
		return
	var app := GameApp.new()
	app.appearance_path = ""
	app.settings_path = ""
	root.add_child(app)
	app.config.appearance.colour_id = &"yellow"
	app.config.stages = [load("res://game/stage/bull_office/bull_office.tres")]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--players="):
			app.config.player_count = clampi(int(argument.trim_prefix("--players=")), 2, 10)
	app._start_match()
	var arena := app.match_controller.round
	arena.set_physics_process(false)
	var previous := Time.get_ticks_usec()
	var old_phase := -1
	var tick_ms := 0.0
	var live_frames := PackedFloat64Array()
	for frame in 660:
		var now := Time.get_ticks_usec()
		var frame_ms := (now - previous) / 1000.0
		previous = now
		var bull: OfficeBull = arena.stage.bull
		if arena.phase == RoundController.Phase.LIVE:
			live_frames.append(frame_ms)
		if frame_ms > 40 or bull.phase != old_phase:
			print(
				JSON.stringify(
					{
						"frame": frame,
						"frame_ms": frame_ms,
						"tick_ms": tick_ms,
						"round_phase": arena.phase,
						"bull_phase": bull.phase
					}
				)
			)
		old_phase = bull.phase
		var started := Time.get_ticks_usec()
		arena._physics_process(1.0 / 60)
		tick_ms = (Time.get_ticks_usec() - started) / 1000.0
		await process_frame
		if arena.phase == RoundController.Phase.FINISHED:
			break
	live_frames.sort()
	if not live_frames.is_empty():
		print(
			JSON.stringify(
				{
					"players": app.config.player_count,
					"live_max_ms": live_frames[-1],
					"live_p95_ms": live_frames[int((live_frames.size() - 1) * 0.95)]
				}
			)
		)
	quit()
