extends RefCounted
## Authored map and skin definitions stay separate from mutable match state.


func run(tree: SceneTree, check: Callable) -> void:
	var first := MatchConfig.default_stage().duplicate() as StageDefinition
	var second := first.duplicate() as StageDefinition
	second.id = &"test_second"
	second.display_name = "Second stage"
	var config := MatchConfig.new()
	config.stages = [first, second]
	var snapshot := config.validated_copy()
	seed(77431)
	var picks: Array[StringName] = []
	for number in range(1, 41):
		picks.append(snapshot.stage_for_round(number).id)
	check.call(
		picks.has(first.id) and picks.has(second.id), "Random selection can choose either map"
	)
	var repeated := false
	for index in range(1, picks.size()):
		if picks[index] == picks[index - 1]:
			repeated = true
	check.call(repeated, "Map selection is random rather than alternating")
	check.call(
		config.stages[0] == first and config.stages[1] == second,
		"Random selection preserves authored map list"
	)
	second.display_name = "Edited after start"
	check.call(
		snapshot.stages[1].display_name == "Second stage",
		"Live map metadata is isolated from setup edits"
	)
	config.stages = [null, StageDefinition.new()]
	check.call(
		config.validated_copy().stages[0].id == first.id,
		"Invalid or empty map rotations use the default map"
	)
	var wrong_root := Node2D.new()
	var wrong_scene := PackedScene.new()
	wrong_scene.pack(wrong_root)
	wrong_root.free()
	var invalid := first.duplicate() as StageDefinition
	invalid.scene = wrong_scene
	check.call(
		not invalid.validation_errors().is_empty(), "Maps must implement the ArenaStage contract"
	)
	var controller := MatchController.new()
	tree.root.add_child(controller)
	config.stages = [first, snapshot.stages[1]]
	controller.start(config)
	controller.round.set_physics_process(false)
	controller.round.phase = RoundController.Phase.FINISHED
	controller._on_completed(controller.round.round_id, -1)
	controller.continue_round()
	await tree.process_frame
	check.call(
		controller.round.get("_definition").id in [first.id, &"test_second"],
		"Live controller selects from configured maps"
	)
	controller.queue_free()
	await tree.process_frame
	var appearance := CharacterAppearance.new()
	appearance.body_id = SkinCatalog.default_definition().id
	var skin := appearance.resolved_skin()
	check.call(skin.is_valid(), "Registered default skin validates its mesh and shader")
	var model := ChairModel.new()
	model.build(Color.WHITE, skin)
	var torso := model.body.get_node("ContinuousBody") as MeshInstance3D
	check.call(
		torso.mesh == skin.body_mesh and torso.material_override.shader == skin.body_shader,
		"Body rendering consumes the authored skin resource"
	)
	model.free()
	var state := MatchState.new()
	config.appearance = appearance
	state.configure(config)
	check.call(
		state.participants[0].skin.id == skin.id,
		"Match roster carries the selected skin into portraits and gameplay"
	)
	check.call(state.participants[0].skin != skin, "Running match owns its skin metadata snapshot")
	var path := "user://skin_test_%d.cfg" % Time.get_ticks_usec()
	appearance.save_profile(path)
	check.call(
		CharacterAppearance.load_profile(path).body_id == skin.id,
		"Only registered skin IDs survive profile reload"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
