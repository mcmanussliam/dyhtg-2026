extends RefCounted
## Shared render resources must preserve geometry, materials and instance transforms.


func run(tree: SceneTree, check: Callable) -> void:
	var model := Node3D.new()
	tree.root.add_child(model)
	var red := ModelGeometry.material(Color.RED)
	var blue := ModelGeometry.material(Color.BLUE)
	var size := Vector3(0.6, 0.4, 0.2)
	var first := ModelGeometry.cushion(model, Vector3.ZERO, size, 0.03, red)
	var second := ModelGeometry.cushion(model, Vector3.RIGHT, size, 0.03, blue)
	check.call(first.mesh == second.mesh, "Identical cushions share immutable geometry")
	check.call(
		first.material_override == red and second.material_override == blue,
		"Shared meshes retain independent instance materials"
	)
	var flat_vertices: PackedVector3Array = first.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var curved := ModelGeometry.curved_cushion(model, Vector3.ZERO, size, 0.03, red)
	var repeated := ModelGeometry.curved_cushion(model, Vector3.UP, size, 0.03, red)
	check.call(curved.mesh == repeated.mesh, "Curved cushions reuse their own geometry")
	check.call(
		(
			curved.mesh != first.mesh
			and flat_vertices == first.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		),
		"Curving a shared mesh never mutates the flat source"
	)
	var first_extinguisher := ExtinguisherModel.new()
	var second_extinguisher := ExtinguisherModel.new()
	model.add_child(first_extinguisher)
	model.add_child(second_extinguisher)
	first_extinguisher.build()
	second_extinguisher.build()
	var first_parts := first_extinguisher.find_children("*", "MeshInstance3D", true, false)
	var second_parts := second_extinguisher.find_children("*", "MeshInstance3D", true, false)
	check.call(
		first_parts.size() == 1 and first_parts[0].mesh == second_parts[0].mesh,
		"All extinguishers reuse a single immutable assembled mesh"
	)
	check.call(
		first_parts[0].mesh.get_surface_count() == 5,
		"Extinguisher batching retains all five materials"
	)
	check.call(
		first_extinguisher.nozzle.position == Vector3(0, 0.405, 0.36),
		"Baked extinguisher retains its precise nozzle anchor"
	)
	model.free()
	_check_batch(tree, check)
	await _check_spray(tree, check)
	var empty := WinTokens.new()
	tree.root.add_child(empty)
	check.call(
		empty.get_child_count() == 0 and not empty.is_processing(),
		"Empty score rows allocate no render viewport or animation loop"
	)
	empty.free()
	await _check_warmup(tree, check)


func _check_batch(tree: SceneTree, check: Callable) -> void:
	var model := Node3D.new()
	tree.root.add_child(model)
	model.transform = Transform3D(
		Basis(Vector3.UP, 0.7).scaled(Vector3(1.3, 1, 0.9)), Vector3(8, 2, -3)
	)
	var material := ModelGeometry.material(Color.WHITE)
	var poses: Array[Transform3D] = []
	for index in 3:
		var part := ModelGeometry.cushion(
			model, Vector3(index, 0.2, -0.4), Vector3(0.3, 0.2, 0.1), 0.01, material
		)
		part.rotation.z = index * 0.2
		poses.append(part.global_transform)
	var collider := CollisionShape3D.new()
	collider.shape = BoxShape3D.new()
	model.add_child(collider)
	StaticModelBatcher.batch(model)
	var batches := model.find_children("*", "MultiMeshInstance3D", true, false)
	check.call(
		batches.size() == 1 and model.find_children("*", "MeshInstance3D", true, false).is_empty(),
		"Repeated static parts become one instanced draw"
	)
	var transforms_match := batches.size() == 1
	if transforms_match:
		var renderer := batches[0] as MultiMeshInstance3D
		for index in poses.size():
			transforms_match = (
				transforms_match
				and poses[index].is_equal_approx(
					renderer.global_transform * renderer.multimesh.get_instance_transform(index)
				)
			)
	if DisplayServer.get_name() != "headless":
		check.call(transforms_match, "Batching preserves rotated and scaled world transforms")
	check.call(is_instance_valid(collider), "Render batching leaves physics colliders intact")
	model.free()


func _check_spray(tree: SceneTree, check: Callable) -> void:
	var chair := Chair.new()
	chair.tuning = preload("res://game/chair/default_tuning.tres")
	chair.freeze = true
	tree.root.add_child(chair)
	var spray := SprayView.new()
	tree.root.add_child(spray)
	var nozzle := Vector3(1, 0.7, 0)
	spray.warm_up_rendering(nozzle)
	spray.update_plume(chair, nozzle, 0.6)
	var balls: MultiMesh = spray.get("_balls")
	var positions: PackedVector3Array = spray.get("_positions")
	var sizes: PackedFloat32Array = spray.get("_sizes")
	var opacity: PackedFloat32Array = spray.get("_opacity")
	var keys: PackedInt64Array = spray.get("_sort_keys")
	var visible_count := balls.visible_instance_count
	var buffer: PackedFloat32Array = spray.get("_buffer")
	var matches := buffer.size() == SprayView.BALL_COUNT * 16
	for slot in visible_count:
		var index := int(keys[slot] & 255)
		var base := slot * 16
		var position := Vector3(buffer[base + 3], buffer[base + 7], buffer[base + 11])
		matches = matches and position.is_equal_approx(positions[index])
		matches = matches and is_equal_approx(buffer[base], sizes[index])
		matches = matches and is_equal_approx(buffer[base + 5], sizes[index])
		matches = matches and is_equal_approx(buffer[base + 10], sizes[index])
		matches = matches and is_equal_approx(buffer[base + 15], opacity[index])
	check.call(
		visible_count > 0 and visible_count < SprayView.BALL_COUNT,
		"Invisible foam consumes no rendered instances"
	)
	check.call(matches, "Bulk foam preserves visible sphere transforms and opacity")
	# The headless dummy renderer does not retain GPU instance buffers.
	if DisplayServer.get_name() != "headless":
		var uploaded := true
		for slot in visible_count:
			var index := int(keys[slot] & 255)
			var pose := balls.get_instance_transform(slot)
			uploaded = uploaded and pose.origin.is_equal_approx(positions[index])
			uploaded = (
				uploaded and pose.basis.get_scale().is_equal_approx(Vector3.ONE * sizes[index])
			)
			uploaded = uploaded and absf(balls.get_instance_color(slot).a - opacity[index]) < 0.005
		check.call(uploaded, "Native renderer receives all foam transforms and opacity")
	chair.spraying = false
	spray.update_plume(chair, nozzle, 0.7)
	check.call(not spray.visible, "Bulk foam hides immediately when propulsion stops")
	spray.free()
	chair.free()
	await tree.process_frame


func _check_warmup(tree: SceneTree, check: Callable) -> void:
	var config := MatchConfig.new()
	var state := MatchState.new()
	state.configure(config)
	var arena := RoundController.new()
	arena.configure(state.participants, load("res://game/stage/bull_office.tres"), 1, 5)
	tree.root.add_child(arena)
	arena.set_physics_process(false)
	for frame in 4:
		await tree.process_frame
	check.call(
		not arena.get("_warming_rendering") and not arena.presentation.world.visible,
		"Warmup finishes beneath the title and stops hidden arena rendering"
	)
	var bull: OfficeBull = arena.stage.bull
	check.call(
		(
			bull.phase == OfficeBull.Phase.RECOVERY
			and bull.position == arena.stage.center
			and is_zero_approx(arena.stage.get("_elapsed"))
		),
		"Render warmup never advances bull physics or the reinforcement clock"
	)
	check.call(
		not bull.get("_lane").visible and not bull.get("_marker").visible,
		"Warmup restores hidden charge indicators before gameplay"
	)
	var unchanged := not arena.stage.round_running
	for chair in arena.chairs:
		var view := chair.get_node("Visuals")
		unchanged = unchanged and chair.freeze and not chair.spraying and chair.jet_strength == 0
		unchanged = unchanged and not view.get("_render_warmup") and not view.get("_spray").visible
	check.call(unchanged, "Warmup never changes player inputs, thrust or opening spray state")
	# Exercise the presentation paths directly in headless checks too.
	arena.stage.set_render_warmup(true)
	check.call(
		bull.get("_lane").visible and bull.get("_marker").visible,
		"Bull warmup includes the real charge-warning draw paths"
	)
	arena.stage.set_render_warmup(false)
	check.call(
		not bull.get("_lane").visible and bull.phase == OfficeBull.Phase.RECOVERY,
		"Warning warmup restores the current combat phase"
	)
	arena.queue_free()
	await tree.process_frame
