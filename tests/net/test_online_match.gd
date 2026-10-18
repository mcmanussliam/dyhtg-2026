extends RefCounted
## A host and a client MatchController in one process, each in its own physics world,
## linked by an in-memory session: rounds, mirroring, input, events, results, leaving.

const FAKE_NET = preload("res://tests/net/online_fake_net.gd")
const DEFAULT_STAGE := &"a_floor_in_the_crack"
const HAZARD_STAGE := &"bull_in_the_chinese_office"


func run(tree: SceneTree, check: Callable) -> void:
	await _test_fast_forward(tree, check)
	await _test_snapshot_size(tree, check)
	await _test_default_map_match(tree, check)
	await _test_hazard_map_and_leaving(tree, check)


func _world(tree: SceneTree) -> SubViewport:
	var view := SubViewport.new()
	view.size = Vector2i(1280, 800)
	view.own_world_3d = true
	view.world_2d = World2D.new()
	tree.root.add_child(view)
	return view


func _roster() -> Array:
	return [
		{
			"id": 0,
			"peer": 1,
			"name": "Host Mac",
			"hat_id": CharacterHats.IDS[0],
			"top_id": SkinCatalog.definitions()[2].id,
			"colour": MatchState.COLOURS[0],
			"wins": 0,
		},
		{
			"id": 1,
			"peer": 2,
			"name": "Client Mac",
			"hat_id": &"no_such_hat",
			"top_id": &"no_such_top",
			"colour": MatchState.COLOURS[3],
			"wins": 0,
		},
		{
			"id": 2,
			"peer": 0,
			"name": "AI 2",
			"hat_id": &"none",
			"top_id": &"none",
			"colour": MatchState.COLOURS[5],
			"wins": 0,
		},
	]


## Host and client controllers linked through fakes, each in its own SubViewport world.
func _pair(
	tree: SceneTree, stage_id: StringName, wins_needed: int, extra_ai := false
) -> Dictionary:
	var host_view := _world(tree)
	var client_view := _world(tree)
	var host_net := FAKE_NET.new()
	var client_net := FAKE_NET.new()
	client_net.fake_peer = 2
	host_view.add_child(host_net)
	client_view.add_child(client_net)
	FAKE_NET.fake_link(host_net, [client_net])
	var host := MatchController.new()
	var client := MatchController.new()
	host_view.add_child(host)
	client_view.add_child(client)
	var log := {"host_results": [], "client_results": [], "finished": [], "began": []}
	for pair in [[host, "host_results"], [client, "client_results"]]:
		pair[0].results_ready.connect(
			func(roster, winner, target, final_result, number) -> void:
				log[pair[1]].append([roster, winner, target, final_result, number])
		)
		pair[0].round_began.connect(func(number: int) -> void: log.began.append(number))
	host.online_finished.connect(func() -> void: log.finished.append("host"))
	client.online_finished.connect(func() -> void: log.finished.append("client"))
	var setup := {"wins_needed": wins_needed, "stages": [stage_id, &"not_a_map"]}
	var roster := _roster()
	if extra_ai:
		var ai: Dictionary = roster[2].duplicate(true)
		ai.id = 3
		ai.name = "AI 3"
		ai.colour = MatchState.COLOURS[6]
		roster.append(ai)
	client.start_online(client_net, roster, setup)
	host.start_online(host_net, roster, setup)
	return {
		"host": host,
		"client": client,
		"host_net": host_net,
		"client_net": client_net,
		"views": [host_view, client_view],
		"log": log,
	}


func _until(tree: SceneTree, condition: Callable, limit: int) -> bool:
	for frame in limit:
		if condition.call():
			return true
		await tree.physics_frame
	return condition.call()


func _frames(tree: SceneTree, count: int) -> void:
	for frame in count:
		await tree.physics_frame


func _shorten(round_scene: RoundController) -> void:
	round_scene.intro_duration = 0.1
	round_scene.startup_duration = 0.2
	round_scene.resolve_duration = 0.2


## Worst planar and heading error between each client chair and the closest of the host's
## last few poses: clients show the host a fixed pipeline delay (capture, then delivery)
## behind, so this measures how faithfully they follow the host's path.
func _tracking_error(
	host_round: RoundController, client_round: RoundController, history: Array
) -> Vector2:
	var poses: Array = []
	for chair in host_round.chairs:
		poses.append(Vector3(chair.global_position.x, chair.global_position.y, chair.rotation))
	history.push_front(poses)
	if history.size() > 4:
		history.pop_back()
	var distance := 0.0
	var heading := 0.0
	for seat in host_round.chairs.size():
		var mirror := client_round.chairs[seat]
		if not host_round.chairs[seat].is_in_play() or not mirror.is_in_play():
			continue
		var nearest := INF
		var turn := INF
		for frame: Array in history:
			var pose: Vector3 = frame[seat]
			nearest = minf(nearest, Vector2(pose.x, pose.y).distance_to(mirror.global_position))
			turn = minf(turn, absf(angle_difference(pose.z, mirror.global_rotation)))
		distance = maxf(distance, nearest)
		heading = maxf(heading, turn)
	return Vector2(distance, heading)


func _test_snapshot_size(tree: SceneTree, check: Callable) -> void:
	var view := _world(tree)
	var config := MatchConfig.new()
	config.player_count = MatchConfig.MAX_PLAYERS
	var state := MatchState.new()
	state.configure(config)
	var round_scene := RoundController.new()
	round_scene.configure(state.participants, MatchConfig.default_stage(), 1, 3)
	view.add_child(round_scene)
	round_scene.begin_live()
	await _frames(tree, 30)
	var size := var_to_bytes(round_scene.net_snapshot()).size()
	print("Ten-seat live snapshot: %d bytes" % size)
	check.call(size < 1024, "Ten-seat snapshot stays well under 2 KB (%d bytes)" % size)
	view.queue_free()
	await tree.process_frame


func _test_default_map_match(tree: SceneTree, check: Callable) -> void:
	var pair := await _pair(tree, DEFAULT_STAGE, 2)
	var host: MatchController = pair.host
	var client: MatchController = pair.client
	var log: Dictionary = pair.log
	_shorten(host.round)
	var built := await _until(tree, func() -> bool: return client.round != null, 5)
	check.call(built, "Client builds the host's round from the reliable round message")
	if not built:
		return
	var host_round := host.round
	var client_round := client.round
	_shorten(client_round)
	check.call(
		(
			client_round.stage.scene_file_path == host_round.stage.scene_file_path
			and host_round.stage.scene_file_path.contains(String(DEFAULT_STAGE))
			and client_round.round_id == host_round.round_id
		),
		"Client round uses the host's map and round number"
	)
	check.call(client_round.mirror and not host_round.mirror, "Only the client round mirrors")
	check.call(client_round.stage.net_mirror, "Client stage is put in net mirror mode")
	check.call(log.began == [1, 1], "Both peers report the new round")
	var same_roster := client.state.participants.size() == 3
	for seat in 3:
		var a: Dictionary = host.state.participants[seat]
		var b: Dictionary = client.state.participants[seat]
		same_roster = (
			same_roster
			and a.name == b.name
			and a.colour == b.colour
			and a.skin.id == b.skin.id
			and a.hat_id == b.hat_id
			and a.peer == b.peer
		)
	check.call(same_roster, "Both peers resolve the same roster appearance")
	check.call(
		(
			host.state.participants[0].name == "Player 1"
			and host.state.participants[1].name == "Player 2"
		),
		"Personal names in network rosters become generic player labels"
	)
	check.call(
		(
			host.state.participants[0].skin.id == SkinCatalog.definitions()[2].id
			and host.state.participants[1].skin.id == SkinCatalog.default_definition().id
			and host.state.participants[1].hat_id == &"none"
		),
		"Roster tops resolve through the catalog; unknown IDs fall back to defaults"
	)
	check.call(
		(
			host_round.get("_pilots").keys() == [2]
			and host_round.remote_turns.has(1)
			and host_round.local_seat == 0
			and client_round.local_seat == 1
			and client_round.get("_pilots").is_empty()
		),
		"Host pilots only AI seats; the client has no pilots"
	)
	var live := await _until(
		tree, func() -> bool: return client_round.phase == RoundController.Phase.LIVE, 40
	)
	check.call(live, "Client goes live from the host's snapshot phase")
	var worst := Vector2.ZERO
	var history: Array = []
	var total := 0.0
	var steered := true
	for frame in 50:
		await tree.physics_frame
		client_round.local_turn = 1.0
		if frame > 4:
			steered = steered and host_round.chairs[1].command.turn == 1.0
			steered = steered and host_round.chairs[0].command.turn == 0.0
			var error := _tracking_error(host_round, client_round, history)
			worst = worst.max(error)
			total += error.x
	var mean := total / 45.0
	print("Default map tracking: mean %.2f px, worst %.2f px, %.3f rad" % [mean, worst.x, worst.y])
	check.call(steered, "Client input steers its own seat on the host and no other")
	# A collision on the host shows up a pipeline delay later, so allow two frames of top
	# speed as a brief transient while the usual error stays a few pixels.
	check.call(
		mean < 5.0 and worst.x < 24.0 and worst.y < 0.25, "Client chairs track host chairs closely"
	)
	check.call(
		not host_round.get("_spectator").get("_instruction").visible,
		"Living humans keep the online spectator instruction hidden"
	)
	check.call(
		not host_round.call("_can_fast_forward") and not client_round.call("_can_fast_forward"),
		"Online fast forward waits until every human is eliminated"
	)
	check.call(
		pair.client_net.fake_largest.get(&"snapshot", 0) < 1024,
		(
			"Three-seat snapshots are small (%d bytes)"
			% pair.client_net.fake_largest.get(&"snapshot", 0)
		)
	)
	# A launched knockout (as the bull does) and a plain edge fall.
	var launch := Vector3(4.0, 6.0, -2.0)
	var spin := Vector3(1.5, 3.5, 0.0)
	host_round.chairs[2].set_knockout_launch(launch, spin)
	host_round.request_elimination(2, &"bull")
	var replayed := await _until(tree, func() -> bool: return not client_round.chairs[2].active, 5)
	var mirrored_ko := client_round.chairs[2]
	check.call(
		(
			replayed
			and mirrored_ko.falling
			and mirrored_ko.knockout_velocity == launch
			and mirrored_ko.knockout_spin == spin
		),
		"Knockout eliminations replay with the host's launch"
	)
	await tree.physics_frame
	check.call(
		is_instance_valid(mirrored_ko.get_node("Visuals").get("_fall_body")),
		"Mirrored knockout plays the native ragdoll flight"
	)
	check.call(
		(client_round.get("_indicators") as RoundRoster).is_eliminated(2),
		"Client roster greys out the eliminated portrait"
	)
	host_round.chairs[1].global_position = Vector2(-1500, -1500)
	var mirrored_fall := [false]
	var resolved := await _until(
		tree,
		func() -> bool:
			var chair := client_round.chairs[1]
			mirrored_fall[0] = mirrored_fall[0] or (chair.falling and chair.active)
			return not log.client_results.is_empty(),
		240
	)
	check.call(mirrored_fall[0], "A plain edge fall plays on the client before elimination")
	check.call(not client_round.chairs[1].active, "The confirmed fall eliminates on the client")
	check.call(resolved and log.host_results.size() == 1, "Results reach host and client")
	if not resolved:
		return
	var host_result: Array = log.host_results[0]
	var client_result: Array = log.client_results[0]
	check.call(
		(
			client_result[1] == 0
			and host_result[1] == 0
			and client_result[2] == 2
			and not client_result[3]
			and client_result[4] == 1
			and client_result[0].map(func(p: Dictionary) -> int: return p.wins) == [1, 0, 0]
		),
		"Client results carry the host's winner and scores"
	)
	check.call(
		client_round.phase == RoundController.Phase.FINISHED,
		"Client round finishes when the host's results arrive"
	)
	client.handle_result_action(&"continue")
	await _frames(tree, 3)
	check.call(client.round == client_round, "Clients never advance rounds themselves")
	host.handle_result_action(&"continue")
	var next := await _until(
		tree, func() -> bool: return client.round != null and client.round.round_id == 2, 10
	)
	check.call(
		next and host.round.round_id == 2 and client.round.round_id == 2,
		"Host Continue starts the next round on both peers"
	)
	if not next:
		return
	host_round = host.round
	client_round = client.round
	_shorten(host_round)
	_shorten(client_round)
	await _until(tree, func() -> bool: return client_round.phase == RoundController.Phase.LIVE, 40)
	host_round.request_elimination(1, &"fire")
	host_round.request_elimination(2, &"fire")
	var final_reached := await _until(
		tree, func() -> bool: return log.client_results.size() == 2, 60
	)
	check.call(
		(
			final_reached
			and not client_round.chairs[1].visible
			and log.client_results[1][3]
			and client.is_match_over()
		),
		"A hidden elimination and the final result replicate"
	)
	host.handle_result_action(&"home")
	await _until(tree, func() -> bool: return log.finished.size() == 2, 5)
	check.call(log.finished == ["host", "client"], "The final result returns every peer")
	check.call(
		pair.host_net.fake_ended_matches == 1 and pair.client_net.fake_ended_matches == 0,
		"Only the host ends the session's match"
	)
	check.call(host.round == null and client.round == null, "Finishing frees both rounds")
	for view in pair.views:
		view.queue_free()
	await tree.process_frame


func _test_hazard_map_and_leaving(tree: SceneTree, check: Callable) -> void:
	var pair := await _pair(tree, HAZARD_STAGE, 3)
	var host: MatchController = pair.host
	var client: MatchController = pair.client
	var host_net: Node = pair.host_net
	var client_net: Node = pair.client_net
	client_net.fake_latency = 2
	client_net.fake_drop_rate = 0.1
	_shorten(host.round)
	var built := await _until(tree, func() -> bool: return client.round != null, 5)
	check.call(
		built and client.round.stage.scene_file_path == host.round.stage.scene_file_path,
		"Client builds the hazard map round"
	)
	if not built:
		return
	var host_round := host.round
	var client_round := client.round
	await _until(tree, func() -> bool: return client_round.phase == RoundController.Phase.LIVE, 40)
	var worst := Vector2.ZERO
	var history: Array = []
	for frame in 60:
		await tree.physics_frame
		if frame > 6:
			worst = worst.max(_tracking_error(host_round, client_round, history))
	print("Hazard map tracking with latency and loss: %.2f px, %.3f rad" % [worst.x, worst.y])
	check.call(worst.x < 40.0, "Chairs track within tolerance despite latency and loss")
	host_net.fake_drop_client(client_net)
	check.call(
		(
			host_round.get("_pilots").has(1)
			and not host_round.remote_turns.has(1)
			and host.state.participants[1].peer == 0
			and host_round.chairs.size() == 3
		),
		"A client leaving mid-round turns its seat into AI and keeps the chair"
	)
	await _frames(tree, 5)
	client_net.session_closed.emit("Host left")
	await tree.physics_frame
	check.call(client.round == null, "Session closure frees the client round")
	var sent: int = client_net.fake_received.get(&"snapshot", 0)
	host_net.session_closed.emit("Closed")
	await _frames(tree, 3)
	check.call(host.round == null, "Session closure frees the host round")
	check.call(
		client_net.fake_received.get(&"snapshot", 0) == sent and pair.log.finished.is_empty(),
		"Closed sessions stop streaming without finishing the match"
	)
	for view in pair.views:
		view.queue_free()
	await tree.process_frame


func _test_fast_forward(tree: SceneTree, check: Callable) -> void:
	var scale := Engine.time_scale
	var rate := Engine.physics_ticks_per_second
	var pair := _pair(tree, DEFAULT_STAGE, 5, true)
	var host: MatchController = pair.host
	var client: MatchController = pair.client
	host.round.set_physics_process(false)
	check.call(
		await _until(tree, func() -> bool: return client.round != null, 5),
		"Fast-forward test client receives the round"
	)
	client.round.set_physics_process(false)
	host.round.begin_live()
	client.round.begin_live()
	var request := {"round": host.round.round_id, "held": true}
	host._on_message(&"fast_forward", request, 2)
	check.call(
		not host.round.is_fast_forwarding(), "Host rejects fast forward while humans survive"
	)
	host.round.request_elimination(0, &"fall")
	host.round._commit_eliminations()
	check.call(
		not host.round._can_fast_forward(),
		"An eliminated host cannot accelerate a surviving remote human"
	)
	host.round.request_elimination(1, &"fall")
	host.round._commit_eliminations()
	client.round.apply_net_snapshot(host.round.net_snapshot())
	client.round._spectator.refresh()
	check.call(
		(
			host.round._can_fast_forward()
			and client.round._can_fast_forward()
			and client.round._spectator._instruction.visible
		),
		"Both spectators receive the existing fast-forward instruction once all humans are out"
	)
	host._on_message(&"fast_forward", {"round": host.round.round_id - 1, "held": true}, 2)
	host._on_message(&"fast_forward", request, 999)
	check.call(
		not host.round.is_fast_forwarding(),
		"Unknown peers and stale rounds cannot change spectator speed"
	)
	client.round.fast_forward_requested.emit(true)
	check.call(
		await _until(tree, func() -> bool: return host.round.is_fast_forwarding(), 5),
		"Holding Right on a client requests host-authoritative fast forward"
	)
	client.round.apply_net_snapshot(host.round.net_snapshot())
	check.call(
		(
			client.round._spectator._hint.visible
			and Engine.time_scale == scale * SpectatorSpeed.MULTIPLIER
			and Engine.physics_ticks_per_second == rate * SpectatorSpeed.MULTIPLIER
		),
		"Clients display the 3x badge without compounding host acceleration"
	)
	check.call(
		(
			host.round.presentation.world.visible
			and client.round.presentation.world.visible
			and host.state.wins() == PackedInt32Array([0, 0, 0, 0])
		),
		"Fast forward keeps the level visible and does not jump to scoring"
	)
	client.round.fast_forward_requested.emit(false)
	check.call(
		await _until(tree, func() -> bool: return not host.round.is_fast_forwarding(), 5),
		"Releasing Right returns the host to normal speed"
	)
	client.round.apply_net_snapshot(host.round.net_snapshot())
	check.call(
		(
			Engine.time_scale == scale
			and Engine.physics_ticks_per_second == rate
			and not client.round._spectator._hint.visible
		),
		"Release restores timing and removes every peer's acceleration badge"
	)
	# A fresh local hold uses the original single-player controls on the host.
	Input.action_release("spectator_fast_forward")
	host.round._spectator.refresh()
	Input.action_press("spectator_fast_forward")
	host.round._spectator.refresh()
	check.call(host.round.is_fast_forwarding(), "The host can also hold Right to fast forward")
	host._on_message(&"fast_forward", request, 2)
	host._on_message(&"fast_forward", {"round": host.round.round_id, "held": false}, 2)
	check.call(
		host.round.is_fast_forwarding(),
		"One spectator releasing Right preserves another spectator's hold"
	)
	Input.action_release("spectator_fast_forward")
	host.round._spectator.refresh()
	# Dropping the requesting client must not leave acceleration stuck on.
	host._on_message(&"fast_forward", request, 2)
	pair.host_net.fake_drop_client(pair.client_net)
	check.call(
		not host.round.is_fast_forwarding() and Engine.time_scale == scale,
		"A disconnected spectator releases its fast-forward hold"
	)
	for view in pair.views:
		view.free()
	await tree.process_frame
