extends RefCounted
## The maximum roster must fit every map and both gameplay and score UI.


func run(tree: SceneTree, check: Callable) -> void:
	var config := MatchConfig.new()
	check.call(
		config.player_count == 6 and config.wins_needed == 3,
		"Default match is one human and five AI, first to three"
	)
	config.player_count = MatchConfig.MAX_PLAYERS
	var state := MatchState.new()
	state.configure(config)
	check.call(state.participants.size() == 10, "Maximum roster contains ten total players")
	for definition in config.stages:
		var round_scene := RoundController.new()
		round_scene.configure(state.participants, definition, 1, 5)
		tree.root.add_child(round_scene)
		round_scene.set_physics_process(false)
		await tree.physics_frame
		_check_counts(round_scene.stage, check)
		var clear := true
		var support := true
		for chair in round_scene.chairs:
			support = (
				support and round_scene.stage.is_spawn_safe(chair.position, 30 * chair.size_scale)
			)
			var query := PhysicsShapeQueryParameters2D.new()
			var collision := chair.get_node("CollisionShape2D") as CollisionShape2D
			query.shape = collision.shape
			query.transform = collision.global_transform
			query.collision_mask = 3
			query.exclude = [chair.get_rid()]
			clear = (
				clear and chair.get_world_2d().direct_space_state.intersect_shape(query).is_empty()
			)
		check.call(clear, "Ten chairs spawn clear of furniture and one another: %s" % definition.id)
		check.call(
			support, "Ten spawns have safe support and entrance clearance: %s" % definition.id
		)
		var portraits := round_scene.get("_indicators") as RoundRoster
		check.call(portraits.get_child_count() == 10, "HUD includes all ten participants")
		round_scene.queue_free()
		await tree.process_frame
	var results := ResultsScreen.new()
	tree.root.add_child(results)
	results.present(state.participants, -1, 5, false, 1)
	await tree.process_frame
	await tree.process_frame
	var characters := results.find_children("*", "TextureRect", true, false)
	var all_visible := true
	var count := 0
	for character in characters:
		if character is ScoreCharacter:
			count += 1
			var rect: Rect2 = character.get_global_rect()
			all_visible = all_visible and Rect2(0, 0, 1280, 800).encloses(rect)
	check.call(count == 10 and all_visible, "All ten score characters fit within the screen")
	results.queue_free()
	await tree.process_frame


func _check_counts(stage: ArenaStage, check: Callable) -> void:
	var shape := CapsuleShape2D.new()
	shape.radius = 23 * stage.content_scale
	shape.height = 60 * stage.content_scale
	for count in range(MatchConfig.MIN_PLAYERS, MatchConfig.MAX_PLAYERS + 1):
		var poses := SpawnLayout.poses(stage, count)
		var clear := true
		for pose in poses:
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = shape
			query.transform = pose * Transform2D(PI / 2, Vector2.ZERO)
			query.collision_mask = 1
			clear = (
				clear and stage.get_world_2d().direct_space_state.intersect_shape(query).is_empty()
			)
		check.call(clear, "Roster of %d fits authored furniture on %s" % [count, stage.name])
