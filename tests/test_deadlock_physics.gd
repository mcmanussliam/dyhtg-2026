extends RefCounted
## Prolonged furniture and wall stalemates must resolve through ordinary steering physics.

const CHAIR = preload("res://game/chair/chair.tscn")
const STEP := 1.0 / 60


func run(tree: SceneTree, check: Callable) -> void:
	for scenario in [
		["res://game/stage/bull_office.tscn", Vector2(80, 420), Vector2(150, 420), 1381],
		[
			"res://game/stage/a_crack_in_the_floor.tscn",
			Vector2(1000, -100),
			Vector2(1105, -113),
			2319
		],
		["res://game/stage/a_floor_in_the_crack.tscn", Vector2(755, 630), Vector2(810, 650), 4421],
		["res://game/stage/bull_office.tscn", Vector2.ZERO, Vector2.ZERO, 7913, 10],
	]:
		await _simulate(tree, check, scenario)


func _simulate(tree: SceneTree, check: Callable, scenario: Array) -> void:
	var arena := Node2D.new()
	tree.root.add_child(arena)
	var stage := load(scenario[0]).instantiate() as ArenaStage
	arena.add_child(stage)
	stage.start_round()
	var count: int = scenario[4] if scenario.size() > 4 else 2
	var poses := SpawnLayout.poses(stage, count)
	var chairs: Array[Chair] = []
	var pilots: Array[PracticePilot] = []
	for index in count:
		var chair := CHAIR.instantiate() as Chair
		chair.get_node("Visuals").free()
		chair.resize_for_stage(stage.content_scale)
		chair.configure(index, Color.WHITE, Vector2.RIGHT)
		arena.add_child(chair)
		if count == 2:
			chair.position = scenario[index + 1]
		else:
			chair.global_transform = poses[index]
		chairs.append(chair)
		pilots.append(PracticePilot.new(scenario[3] + index * 31))
	await tree.physics_frame
	var spray := SpraySystem.new()
	var anchors: Array[Vector2] = []
	var stationary: Array[float] = []
	var longest: Array[float] = []
	var escaped: Array[bool] = []
	for chair in chairs:
		anchors.append(chair.position)
		stationary.append(0.0)
		longest.append(0.0)
		escaped.append(false)
	var interventions := 0
	for frame in 1500:
		for index in count:
			var chair := chairs[index]
			if not chair.active:
				continue
			chair.command = pilots[index].sample_on_stage(chair, chairs, stage, STEP)
			if pilots[index].get("_unstuck").started:
				interventions += 1
			chair.step(STEP)
		for chair in chairs:
			spray.apply(chair, chairs, STEP)
		await tree.physics_frame
		for index in count:
			var chair := chairs[index]
			if not chair.active:
				continue
			if not stage.has_support_near(
				chair.position, 0.15 * RenderStyle.PIXELS_PER_UNIT * chair.size_scale
			):
				chair.eliminate(&"fall")
				continue
			if chair.position.distance_to(anchors[index]) > 100 * chair.size_scale:
				escaped[index] = true
				anchors[index] = chair.position
				stationary[index] = 0.0
			else:
				stationary[index] += STEP
				longest[index] = maxf(longest[index], stationary[index])
	print(
		"DEADLOCK ",
		stage.name,
		" longest=",
		longest,
		" escaped=",
		escaped,
		" interventions=",
		interventions
	)
	check.call(
		escaped.all(func(value: bool): return value),
		"Every rival leaves its initial area: %s" % stage.name
	)
	check.call(longest.max() < 6.5, "No prolonged stationary AI deadlock: %s" % stage.name)
	if stage is PitOfficeStage:
		check.call(interventions > 0, "Reproduced furniture stalemate activates committed escape")
	else:
		check.call(interventions == 0, "Brief physical contests do not trigger unnecessary escape")
	arena.queue_free()
	await tree.process_frame
