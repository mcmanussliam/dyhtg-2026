extends RefCounted
## Tactical variety must remain a bounded steering command, never a physics shortcut.


func run(tree: SceneTree, check: Callable) -> void:
	var stage := preload("res://game/stage/a_floor_in_the_crack.tscn").instantiate() as ArenaStage
	tree.root.add_child(stage)
	var chairs: Array[Chair] = []
	for index in 4:
		var chair := Chair.new()
		chair.tuning = preload("res://game/chair/default_tuning.tres")
		chair.freeze = true
		chair.seat = index
		tree.root.add_child(chair)
		chair.position = (
			Vector2(640, 422)
			+ Vector2.from_angle(index * TAU / 3.0) * (0.0 if index == 0 else 140.0)
		)
		chairs.append(chair)
	var pilot := PracticePilot.new(812)
	var other := PracticePilot.new(194)
	var same_seed := PracticePilot.new(812)
	var finite_commands := true
	var different := false
	var varied := false
	var deterministic := true
	var first := 0.0
	var original := chairs[0].global_transform
	var velocity := chairs[0].linear_velocity
	for tick in 300:
		var turn := pilot.sample_on_stage(chairs[0], chairs, stage, 0.02).turn
		var other_turn := other.sample_on_stage(chairs[0], chairs, stage, 0.02).turn
		var repeated := same_seed.sample_on_stage(chairs[0], chairs, stage, 0.02).turn
		finite_commands = finite_commands and is_finite(turn) and absf(turn) <= 1.0
		deterministic = deterministic and is_equal_approx(turn, repeated)
		different = different or not is_equal_approx(turn, other_turn)
		if tick == 0:
			first = turn
		varied = varied or absf(turn - first) > 0.1
	check.call(finite_commands, "AI tactics produce finite bounded steering")
	check.call(different, "Independent seeded pilots choose different tactics")
	check.call(varied, "AI changes tactical steering over time")
	check.call(deterministic, "Seeded AI is reproducible for regression tests")
	check.call(
		chairs[0].global_transform == original and chairs[0].linear_velocity == velocity,
		"AI sampling never mutates chair transforms or velocity"
	)
	chairs[0].position = Vector2(1000, 422)
	chairs[0].rotation = PI / 2
	chairs[0].linear_velocity = Vector2(300, 0)
	var recovery := pilot.sample_on_stage(chairs[0], chairs, stage).turn
	check.call(recovery < -0.9, "AI edge recovery overrides tactics and turns thrust inward")
	_test_blocked_engagement(chairs, stage, check)
	for chair in chairs:
		chair.queue_free()
	stage.queue_free()
	await tree.process_frame


func _test_blocked_engagement(chairs: Array[Chair], stage: ArenaStage, check: Callable) -> void:
	# A blocked pair can turn but makes no positional progress. Other rivals remain
	# available, including seat zero, so neither stale targets nor loops should stick.
	for index in chairs.size():
		chairs[index].position = Vector2(640, 422) + Vector2.from_angle(index * PI / 2) * 45.0
		chairs[index].linear_velocity = Vector2.ZERO
		chairs[index].angular_velocity = 0.0
	var pilot := PracticePilot.new(924)
	var actor := chairs[1]
	var selected := {}
	for tick in 900:
		pilot.sample_on_stage(actor, chairs, stage, 1.0 / 60.0)
		selected[pilot.target_seat] = true
	check.call(selected.size() >= 2, "Blocked AI changes opponents instead of keeping a stale duel")
	check.call(selected.has(0), "Blocked AI engagement includes the human seat")
	var loop_pilot := PracticePilot.new(497)
	var braked_loop := false
	actor.rotation = 0.0
	actor.angular_velocity = 6.0
	for tick in 90:
		actor.rotation += 0.10
		var turn := loop_pilot.sample_on_stage(actor, chairs, stage, 1.0 / 60.0).turn
		if float(loop_pilot.get("_escape_left")) > 0.0 and turn < -0.9:
			braked_loop = true
	check.call(braked_loop, "Blocked turning loop triggers a straight escape and angular braking")
	chairs[2].active = false
	chairs[3].active = false
	actor.rotation = 0.0
	actor.angular_velocity = 0.0
	var stalled_pilot := PracticePilot.new(248)
	var escaped_stall := false
	var lateral_turn := false
	for tick in 180:
		var turn := stalled_pilot.sample_on_stage(actor, chairs, stage, 1.0 / 60.0).turn
		if float(stalled_pilot.get("_escape_left")) > 0.0:
			escaped_stall = true
			lateral_turn = lateral_turn or absf(turn) > 0.9
	check.call(escaped_stall, "Stationary pushing pair triggers escape with only two players left")
	check.call(lateral_turn, "Stationary pair escape steers away from its blocked heading")
	check.call(
		stalled_pilot.target_seat == 0, "Final pair keeps the remaining human as its opponent"
	)
