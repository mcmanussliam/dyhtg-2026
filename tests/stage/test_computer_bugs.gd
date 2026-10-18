extends RefCounted
## Announced drops, falling strikes, expanding black mush, fusion and round lifetime.

const DEFINITION = preload("res://game/stage/computer_bugs/computer_bugs.tres")
const STEP := 1.0 / 60


func run(tree: SceneTree, check: Callable) -> void:
	await _test_drop_cycle(tree, check)
	await _test_infection(tree, check)
	await _test_strikes(tree, check)


func _stage(tree: SceneTree) -> Array:
	var stage := DEFINITION.scene.instantiate() as ComputerBugsStage
	tree.root.add_child(stage)
	var world := Node3D.new()
	tree.root.add_child(world)
	stage.create_presentation(world, 1.0 / RenderStyle.PIXELS_PER_UNIT)
	return [stage, world]


func _test_drop_cycle(tree: SceneTree, check: Callable) -> void:
	var made := _stage(tree)
	var stage: ComputerBugsStage = made[0]
	var world: Node3D = made[1]
	await tree.physics_frame
	check.call(
		stage.has_support(stage.to_global(stage.center)),
		"Bug or a feature? office has a solid floor"
	)
	var benches := {}
	for prop in stage.get_node("Furniture").get_children():
		if String(prop.name).begins_with("Desk") and not String(prop.name).begins_with("DeskChair"):
			benches[snappedf(prop.position.x, 1.0)] = true
	check.call(benches.size() == 4, "The office keeps its tidy desk benches")
	stage.tick_hazards(30)
	check.call(stage.clumps.is_empty(), "Black intro never drops bugs")
	stage.set_render_warmup(true)
	stage.set_render_warmup(false)
	check.call(stage.clumps.is_empty(), "Warmup leaves the room clean")
	check.call(not world.get_node("BugMush").visible, "No pass is drawn while the room is clean")
	stage.start_round()
	stage.tick_hazards(stage.first_drop - 0.1)
	check.call(stage.clumps.is_empty(), "The first drop waits for its opening delay")
	stage.tick_hazards(0.2)
	check.call(stage.clumps.size() == 1, "A clump is announced")
	var clump: Dictionary = stage.clumps[0]
	check.call(
		(
			clump.phase == ComputerBugsStage.Phase.WARNING
			and stage.get("_markers")[clump.slot].visible
		),
		"The landing spot is marked in red before anything falls"
	)
	check.call(
		not stage.get("_falling")[clump.slot].visible,
		"Nothing is visible falling during the warning"
	)
	check.call(not stage.is_safe(clump.position), "AI avoids the marked landing spot")
	check.call(stage.safe_target(clump.position) != clump.position, "AI retreats from the marker")
	stage.tick_hazards(clump.warning - clump.timer - 0.05)
	check.call(
		clump.phase == ComputerBugsStage.Phase.WARNING,
		"The whole warning is honoured before the drop"
	)
	stage.tick_hazards(0.1)
	check.call(
		(
			clump.phase == ComputerBugsStage.Phase.FALLING
			and stage.get("_falling")[clump.slot].visible
		),
		"The clump then falls from the ceiling"
	)
	var started: float = clump.height
	stage.tick_hazards(STEP)
	check.call(clump.height < started, "A falling clump descends")
	var frames := 0
	while clump.phase == ComputerBugsStage.Phase.FALLING and frames < 120:
		stage.tick_hazards(STEP)
		frames += 1
	var model: MeshInstance3D = stage.get("_falling")[clump.slot]
	check.call(
		clump.phase == ComputerBugsStage.Phase.MUSH and model.visible,
		"The clump is still on screen at the moment it lands"
	)
	for frame in 8:
		stage.tick_hazards(STEP)
	check.call(
		model.visible and model.scale.y < 1.0 and model.scale.x > 1.0,
		"The clump splats: it squashes flat and spreads where it lands"
	)
	check.call(
		stage.mush_radius(clump) < ComputerBugsStage.IMPACT_RADIUS,
		"The mush bursts outward from a small core during the splat"
	)
	for frame in 40:
		stage.tick_hazards(STEP)
	check.call(
		(
			not model.visible
			and clump.freed
			and stage.mush_radius(clump) >= ComputerBugsStage.IMPACT_RADIUS
		),
		"After the splat the model is gone and the mush has its full footprint"
	)
	# A later announcement may reuse the freed pool slot; only this clump's marker clears.
	var reused := stage.clumps.any(
		func(other: Dictionary) -> bool: return other != clump and other.slot == clump.slot
	)
	check.call(
		(
			clump.phase == ComputerBugsStage.Phase.MUSH
			and (reused or not stage.get("_markers")[clump.slot].visible)
		),
		"It lands as mush and its marker clears"
	)
	check.call(
		stage.get("_blob_material").get_shader_parameter("zone_count") >= 1,
		"The landed mush is drawn by the black decal"
	)
	var mush: MeshInstance3D = world.get_node("BugMush")
	check.call(
		mush.visible and mush.position.y < 0.05, "The floor decal appears once mush has landed"
	)
	check.call(
		stage.get("_blob_material").render_priority < 0,
		"Mush is drawn before spray and characters, so they always sit on top"
	)
	check.call(
		stage.get("_zone_data")[0].z > 0.0, "Each landed clump hands the shader a precomputed reach"
	)
	stage.stop_round()
	var seen := stage.drops_total
	stage.tick_hazards(10)
	check.call(stage.drops_total == seen, "Round results freeze the drops")
	world.queue_free()
	stage.queue_free()
	await tree.process_frame


func _test_infection(tree: SceneTree, check: Callable) -> void:
	var made := _stage(tree)
	var stage: ComputerBugsStage = made[0]
	var world: Node3D = made[1]
	await tree.physics_frame
	stage.start_round()
	check.call(stage.coverage() == 0.0, "A fresh round has no bugs on the floor")
	var samples: Array[float] = []
	var radius_before := 0.0
	for second in 90:
		for frame in 60:
			stage.tick_hazards(STEP)
		if second == 12:
			for clump in stage.clumps:
				if clump.phase == ComputerBugsStage.Phase.MUSH:
					radius_before = stage.mush_radius(clump)
					break
		if second % 15 == 14:
			samples.append(stage.coverage())
	check.call(
		samples[0] < samples[-1] and samples[2] >= samples[1] and samples[1] >= samples[0],
		"The infection only ever spreads: %s" % [samples]
	)
	check.call(samples[-1] > 0.7, "Gradually the whole room is infected: %.2f" % samples[-1])
	check.call(
		radius_before > ComputerBugsStage.IMPACT_RADIUS, "Landed mush keeps expanding after impact"
	)
	check.call(
		(
			stage.current_interval() < stage.drop_interval * 0.5
			and stage.current_warning() < stage.warning_seconds
		),
		"Drops come faster as the round goes on"
	)
	check.call(
		stage.mush_count() <= ComputerBugsStage.MAX_MUSH,
		"The mush is bounded to what the decal draws"
	)
	for clump in stage.clumps:
		if clump.phase == ComputerBugsStage.Phase.MUSH:
			check.call(
				stage.mush_radius(clump) <= ComputerBugsStage.MAX_RADIUS + 0.01,
				"No clump swells beyond its cap"
			)
	var covered := 0
	for entry in stage.get("_coverables"):
		covered += 1 if entry.node.visible else 0
	var shells: int = stage.get("_coverables").size()
	check.call(
		shells >= 40 and shells <= 140, "Every prop and wall piece has one cover shell: %d" % shells
	)
	check.call(
		covered > shells * 0.6, "The mush climbs furniture and walls: %d of %d" % [covered, shells]
	)
	var missing := ""
	for prop in stage.get_node("Furniture").get_children():
		var model := prop.get("_presentation") as Node3D
		if model != null and model.get_node_or_null("MushCover") == null:
			missing = String(prop.name)
	check.call(missing == "", "Chairs and every other prop can be covered: %s" % missing)
	var beetles: BugMassView = world.get_node("BugMass")
	var bug_count: int = beetles.multimesh.visible_instance_count
	check.call(
		(
			bug_count >= 20 * BugMassView.BUGS_PER_BLOCK / 4
			and bug_count <= beetles.multimesh.instance_count
		),
		"Thousands of beetles are drawn from one multimesh: %d" % bug_count
	)
	var triangles := 0
	var arrays := beetles.multimesh.mesh.surface_get_arrays(0)
	triangles = arrays[Mesh.ARRAY_VERTEX].size() / 3
	check.call(triangles < 600, "Each beetle is low-poly: %d triangles" % triangles)
	_test_beetle_layout(check)
	var characters := 0
	for child in world.get_children():
		if child.name.begins_with("Chair") or child.name.begins_with("Character"):
			characters += 1
	check.call(
		stage.get("_blob_material").render_priority < 0 and characters == 0,
		"Mush never touches the characters"
	)
	_test_fusion(stage, check)
	world.queue_free()
	stage.queue_free()
	await tree.process_frame


func _test_fusion(stage: ComputerBugsStage, check: Callable) -> void:
	stage.clumps.clear()
	stage.set("_elapsed", 100.0)
	var a := stage.to_global(Vector2(400, 420))
	var gap := 330.0
	var b := a + Vector2(gap, 0)
	var radius := gap / 2.1
	# Pick the landing time that gives each clump the radius for a near-touch.
	var landed := 100.0 - stage.growth_seconds
	for step in 400:
		landed = 100.0 - step * stage.growth_seconds / 400.0
		var probe := {"landed": landed}
		if stage.mush_radius(probe) >= radius:
			break
	for point in [a, b]:
		stage.clumps.append(
			{
				"position": point,
				"phase": ComputerBugsStage.Phase.MUSH,
				"landed": landed,
				"seed": 0.3
			}
		)
	var middle := (a + b) * 0.5
	check.call(
		stage.mush_radius(stage.clumps[0]) < gap * 0.5 and stage.in_mush(middle),
		"Nearly touching clumps join into one mass between them"
	)
	stage.clumps.remove_at(1)
	check.call(not stage.in_mush(middle), "A lone clump covers only its own radius")
	check.call(
		not stage.in_mush(a + Vector2(0, -stage.mush_radius(stage.clumps[0]) * 1.2)),
		"The mass stays tight around its outer edge"
	)
	stage.clumps.clear()


func _test_strikes(tree: SceneTree, check: Callable) -> void:
	var state := MatchState.new()
	var duel := MatchConfig.new()
	duel.player_count = 2
	state.configure(duel)
	var round_scene := RoundController.new()
	round_scene.configure(state.participants, DEFINITION, 1, 5)
	tree.root.add_child(round_scene)
	round_scene.set_physics_process(false)
	round_scene.begin_live()
	var stage := round_scene.stage as ComputerBugsStage
	var first := round_scene.chairs[0]
	var second := round_scene.chairs[1]
	first.stop_drive()
	second.stop_drive()
	var hits: Array[int] = []
	stage.elimination_requested.connect(func(seat: int, _reason: StringName): hits.append(seat))
	var spot := stage.to_global(Vector2(700, 420))
	first.position = spot
	second.position = spot + Vector2(0, 900)
	var clump := {
		"position": spot,
		"phase": ComputerBugsStage.Phase.FALLING,
		"timer": 0.0,
		"warning": 1.0,
		"height": ComputerBugsStage.FALL_HEIGHT,
		"landed": INF,
		"slot": 0,
		"seed": 0.5,
		"block": -1,
		"freed": false
	}
	stage.set("_elapsed", 3.0)
	stage.clumps.append(clump)
	stage.call("_strike_chairs")
	check.call(hits.is_empty(), "A high clump cannot strike a chair")
	clump.height = 0.4
	stage.call("_strike_chairs")
	check.call(hits.is_empty(), "A clump still in flight never kills: it has to splat first")
	clump.phase = ComputerBugsStage.Phase.MUSH
	clump.landed = 3.0
	stage.call("_strike_chairs")
	check.call(hits.is_empty(), "A chair under a clump survives the instant it lands")
	stage.set("_elapsed", 3.0 + ComputerBugsStage.LETHAL_DELAY + 0.05)
	stage.call("_strike_chairs")
	check.call(hits == [first.seat], "The chair dies once the splat has begun")
	check.call(
		first.knockout_velocity != Vector3.ZERO, "The impact sends the chair flying, not vanishing"
	)
	round_scene._commit_eliminations()
	check.call(
		not first.active and round_scene.phase == RoundController.Phase.RESOLVING,
		"Bug elimination uses shared round rules"
	)
	hits.clear()
	stage.clumps.clear()
	var touch := stage.to_global(Vector2(300, 420))
	second.position = touch + Vector2(ComputerBugsStage.IMPACT_RADIUS + 25, 0)
	stage.set("_elapsed", 5.6)
	stage.clumps.append(
		{"position": touch, "phase": ComputerBugsStage.Phase.MUSH, "landed": 5.0, "seed": 0.1}
	)
	stage.call("_strike_chairs")
	check.call(hits.is_empty(), "A chair beside the mush is safe")
	check.call(stage.is_safe(second.position + Vector2(200, 0)), "Clean floor away from it is safe")
	check.call(not stage.is_safe(touch), "AI will not drive onto the mush")
	second.position = touch + Vector2(30, 20)
	stage.call("_strike_chairs")
	check.call(hits == [second.seat], "Touching the mush eliminates the chair")
	var escape := stage.safe_target(touch + Vector2(20, 10))
	check.call(stage.is_safe(escape), "AI receives a safe target away from the mush")
	var clear := true
	var poses := SpawnLayout.poses(stage, 10)
	for pose in poses:
		clear = clear and stage.is_spawn_safe(pose.origin, 34 * stage.content_scale + 5)
	check.call(poses.size() == 10 and clear, "Ten seats start clear of furniture")
	round_scene.queue_free()
	await tree.process_frame


func _test_beetle_layout(check: Callable) -> void:
	var bugs := BugMassView.layout(0.37)
	var rim := 0
	var inside := 0
	var farthest := 0.0
	for bug in bugs:
		var fraction: float = bug.unit.length()
		farthest = maxf(farthest, fraction)
		if bug.edge and fraction >= 0.8:
			rim += 1
		elif not bug.edge and fraction < 0.8:
			inside += 1
	check.call(
		rim >= 30 and inside >= 15 and bugs.size() == BugMassView.BUGS_PER_BLOCK,
		"Beetles line the edge and fill the middle: %d on the rim, %d inside" % [rim, inside]
	)
	check.call(farthest < 1.1, "Beetles never stray far beyond the mass's edge")
	check.call(BugMassView.layout(0.37) == bugs, "The beetle layout is deterministic")
