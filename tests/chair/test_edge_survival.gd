extends RefCounted
## Partial wheel support is playable; scoring waits for a confirmed native drop.


func run(tree: SceneTree, check: Callable) -> void:
	var state := MatchState.new()
	state.configure(MatchConfig.new())
	var round_scene := preload("res://game/round/round.tscn").instantiate() as RoundController
	round_scene.configure(state.participants, MatchConfig.default_stage(), 1, 5)
	tree.root.add_child(round_scene)
	round_scene.set_physics_process(false)
	round_scene.begin_live()
	var stage := round_scene.stage
	var outline: PackedVector2Array = stage.floor_outline()
	var point := Vector2.ZERO
	var outward := Vector2.RIGHT
	for index in outline.size():
		var first := outline[index]
		var next := outline[(index + 1) % outline.size()]
		var middle := (first + next) * 0.5
		if absf(middle.y - 422) < 100 and middle.x > point.x:
			point = middle
			var edge := next - first
			outward = Vector2(edge.y, -edge.x).normalized()
	var chair := round_scene.chairs[0]
	chair.global_position = stage.to_global(point + outward * 5)
	chair.linear_velocity = Vector2.ZERO
	round_scene._physics_process(0.0)
	check.call(
		chair.active and not chair.falling,
		"A chair with wheels still on the rim stays alive and steerable"
	)
	chair.global_position = stage.to_global(point + outward * 12)
	round_scene._physics_process(0.0)
	check.call(
		chair.active and chair.falling,
		"Losing all floor support starts a fall without awarding a death"
	)
	var view := chair.get_node("Visuals")
	view._physics_process(0.0)
	var body := view.get("_fall_body") as RigidBody3D
	body.freeze = true
	body.global_position.y = 0.1
	view._physics_process(0.0)
	round_scene._physics_process(0.0)
	check.call(chair.active, "A native body still above the rim has not been eliminated")
	body.global_position.y = -1.0
	view._physics_process(0.0)
	round_scene._physics_process(0.0)
	check.call(not chair.active, "A confirmed drop below the floor commits the elimination")
	check.call(
		round_scene.get("_indicators").is_eliminated(0),
		"The roster greys out only after the actual drop"
	)
	round_scene.queue_free()
	await tree.process_frame
