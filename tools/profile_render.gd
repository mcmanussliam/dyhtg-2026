extends SceneTree
## Native four-seat rendering microbenchmark; frozen physics keeps runs comparable.
## Run with --path . --script tools/profile_render.gd [-- --capture=/tmp/frame.png].
## CPU timing covers scripted visual updates, not GPU frame time or full gameplay.


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var config := MatchConfig.new()
	config.ai_count = 3
	var state := MatchState.new()
	state.configure(config)
	var round_scene := load("res://game/round/round.tscn").instantiate() as RoundController
	round_scene.configure(
		state.participants, load("res://game/stage/a_floor_in_the_crack.tres"), 1, 5
	)
	var started := Time.get_ticks_usec()
	root.add_child(round_scene)
	var build_ms := (Time.get_ticks_usec() - started) / 1000.0
	round_scene.set_physics_process(false)
	round_scene.begin_live()
	for chair in round_scene.chairs:
		chair.freeze = true
		chair.get_node("Visuals").set_process(false)
	await process_frame
	for frame in 24:
		for chair in round_scene.chairs:
			chair.get_node("Visuals")._process(1.0 / 60.0)
		await process_frame
	var started_plume := Time.get_ticks_usec()
	for frame in 120:
		for chair in round_scene.chairs:
			chair.get_node("Visuals")._process(1.0 / 60.0)
	var frame_cpu_ms := (Time.get_ticks_usec() - started_plume) / 120000.0
	await RenderingServer.frame_post_draw
	var meshes := {}
	var instances := round_scene.presentation.world.find_children(
		"*", "MeshInstance3D", true, false
	)
	for instance in instances:
		meshes[instance.mesh.get_instance_id()] = true
	var rid := root.get_viewport_rid()
	print(
		JSON.stringify(
			{
				"engine": Engine.get_version_info().string,
				"build_ms": build_ms,
				"four_chair_visual_cpu_ms": frame_cpu_ms,
				"mesh_nodes": instances.size(),
				"unique_meshes": meshes.size(),
				"draw_calls":
				RenderingServer.viewport_get_render_info(
					rid,
					RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
					RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
				),
				"primitives":
				RenderingServer.viewport_get_render_info(
					rid,
					RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,
					RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
				)
			}
		)
	)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			root.get_texture().get_image().save_png(argument.trim_prefix("--capture="))
	quit()
