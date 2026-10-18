extends RefCounted
## In-process host and clients over localhost ENet, each on its own multiplayer branch.

const WAIT_MSEC := 3000

var _tree: SceneTree
var _branches: Array[Node] = []
var _port := 0


func run(tree: SceneTree, check: Callable) -> void:
	var unnamed := NetSession.new()
	check.call(unnamed._name() == "Player", "Ordinary sessions do not use OS user or machine names")
	unnamed.free()
	_tree = tree
	_port = randi_range(20000, 40000)
	await _lobby_flow(check)
	await _refusals(check)
	await _full_lobby(check)
	await _lobby_size(check)
	await _host_leaves(check)
	for branch in _branches:
		_tree.set_multiplayer(null, branch.get_path())
		branch.queue_free()
	_branches.clear()
	await tree.process_frame


func _session(label: String, player_name: String) -> NetSession:
	var branch := Node.new()
	branch.name = "Net%s%d" % [label, _branches.size()]
	_tree.root.add_child(branch)
	_tree.set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	_branches.append(branch)
	var session := NetSession.new()
	session.name = "NetSession"
	session.announce = false
	session.local_name = player_name
	branch.add_child(session)
	return session


func _until(condition: Callable, wait_msec := WAIT_MSEC) -> bool:
	var deadline := Time.get_ticks_msec() + wait_msec
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await _tree.process_frame
	return true


func _host(session: NetSession) -> bool:
	for attempt in 5:
		_port += 1
		if session.host(_port) == OK:
			return true
	return false


func _join(session: NetSession) -> bool:
	return session.join("127.0.0.1", _port) == OK and await _until(session.is_online)


func _names(session: NetSession) -> Array:
	return session.lobby.players.map(func(player: Dictionary) -> String: return player.name)


func _lobby_flow(check: Callable) -> void:
	var host := _session("Host", "Studio Mac")
	var a := _session("A", "Studio Mac")
	var b := _session("B", "Desk")
	var appearance := CharacterAppearance.new()
	appearance.colour_id = &"mint"
	appearance.hat_id = &"jetpack"
	host.set_local_appearance(appearance)
	a.set_local_appearance(appearance)
	check.call(not host.is_online() and host.local_peer() == 1, "Offline session is peer 1")
	check.call(_host(host), "Host opens a localhost port")
	check.call(host.is_host() and host.is_online(), "Host is online at once")
	check.call(await _join(a), "First client joins")
	check.call(await _join(b), "Second client joins")
	check.call(
		await _until(func() -> bool: return b.lobby.players.size() == 3 and a.lobby == b.lobby),
		"Every peer receives the same lobby"
	)
	check.call(not a.is_host() and a.local_peer() != 1, "Clients are not the host")
	check.call(
		_names(a) == ["Studio Mac", "Studio Mac 2", "Desk"], "Join order, host first; names de-dupe"
	)
	var peers: Array = a.lobby.players.map(func(player: Dictionary) -> int: return player.peer)
	check.call(peers == [1, a.local_peer(), b.local_peer()], "Lobby peers match join order")
	check.call(a.lobby.players[0].hat_id == &"none", "Unknown hat IDs are validated to none")
	check.call(
		a.lobby.players[0].colour == CharacterAppearance.PALETTE[1],
		"Host keeps the clashing preferred colour"
	)
	check.call(a.lobby.players[1].colour == MatchState.COLOURS[0], "Later clash moves on")
	check.call(a.lobby.players[2].colour == MatchState.COLOURS[2], "Random takes a free colour")
	check.call(
		a.lobby.setup.player_count == 6 and a.lobby.setup.wins_needed == 3,
		"Default setup reaches clients"
	)
	check.call(a.lobby.setup.stages == LobbyRules.stage_ids(), "All stages start selected")
	check.call(a.lobby.setup.stages is Array[StringName], "Stages arrive as StringNames")

	var changes := [0]
	b.lobby_changed.connect(func() -> void: changes[0] += 1)
	var top := SkinCatalog.definitions()[2].id
	var outfit := CharacterAppearance.new()
	outfit.hat_id = &"crown"
	outfit.body_id = top
	outfit.colour_id = &"blue"
	b.set_local_appearance(outfit)
	check.call(
		await _until(func() -> bool: return host.lobby.players[2].colour_id == &"blue"),
		"Appearance changes reach the host"
	)
	check.call(
		await _until(
			func() -> bool: return b.lobby.players[2].colour == CharacterAppearance.PALETTE[3]
		),
		"Resolved appearance returns to every peer"
	)
	check.call(
		b.lobby.players[2].hat_id == &"crown" and b.lobby.players[2].top_id == top,
		"Valid hat and top survive"
	)
	check.call(changes[0] >= 1, "lobby_changed fires on clients")

	a.set_setup(2, 1, [])
	host.set_setup(1, 7, [LobbyRules.stage_ids()[2], &"moon"])
	check.call(
		await _until(func() -> bool: return b.lobby.setup.wins_needed == 5), "Host setup propagates"
	)
	check.call(b.lobby.setup.player_count == 3, "Seats clamp to the humans")
	check.call(b.lobby.setup.stages == [LobbyRules.stage_ids()[2]], "Only known stages remain")
	host.set_setup(8, 2, [])

	var inbox := []
	var record := func(kind: StringName, payload: Variant, from_peer: int) -> void:
		inbox.append([kind, payload, from_peer])
	host.message_received.connect(record)
	a.message_received.connect(record)
	b.message_received.connect(record)
	a.send_to_host(&"input", {"turn": 0.5}, false)
	a.send_to_host(&"ready", [1, 2])
	host.broadcast(&"snapshot", PackedFloat32Array([1.0, 2.0]), false)
	host.broadcast(&"event", {"colour": Color.RED, "at": Vector2(1, 2)})
	check.call(await _until(func() -> bool: return inbox.size() >= 6), "Messages arrive")
	await _tree.process_frame
	check.call(inbox.size() == 6, "Host broadcast is not echoed to the host")
	check.call(
		[&"input", {"turn": 0.5}, a.local_peer()] in inbox, "Unreliable client message reaches host"
	)
	check.call([&"ready", [1, 2], a.local_peer()] in inbox, "Reliable client message reaches host")
	var snapshots := inbox.filter(func(entry: Array) -> bool: return entry[0] == &"snapshot")
	check.call(
		snapshots.size() == 2 and snapshots[0][2] == 1 and snapshots[0][1][1] == 2.0,
		"Unreliable broadcast reaches both clients"
	)
	var events := inbox.filter(func(entry: Array) -> bool: return entry[0] == &"event")
	check.call(
		events.size() == 2 and events[0][1].colour == Color.RED, "Reliable broadcast keeps Variants"
	)

	var starts := []
	var on_start := func(roster: Array, setup: Dictionary) -> void: starts.append([roster, setup])
	host.match_started.connect(on_start)
	a.match_started.connect(on_start)
	b.match_started.connect(on_start)
	host.start_match()
	check.call(
		await _until(func() -> bool: return starts.size() == 3), "match_started fires on every peer"
	)
	check.call(host.lobby.in_match, "Host lobby is in a match")
	check.call(await _until(func() -> bool: return a.lobby.in_match), "Clients see the match")
	var roster: Array = starts[2][0]
	check.call(roster == starts[0][0] and roster.size() == 8, "Every peer gets the same roster")
	check.call(
		(
			roster[0].peer == 1
			and roster[1].peer == a.local_peer()
			and roster[2].peer == b.local_peer()
		),
		"Humans hold the first seats in join order"
	)
	check.call(roster[3].peer == 0 and roster[3].name == "AI 1", "Remaining seats are AI")
	var colours := []
	for seat in roster:
		if seat.colour not in colours:
			colours.append(seat.colour)
	check.call(colours.size() == 8, "Every seat has its own colour")
	check.call(
		starts[2][1] == {"wins_needed": 2, "stages": LobbyRules.stage_ids()},
		"Setup reaches the match"
	)

	var late := _session("Late", "Late")
	var reasons := []
	late.session_closed.connect(func(reason: String) -> void: reasons.append(reason))
	late.join("127.0.0.1", _port)
	check.call(await _until(func() -> bool: return not reasons.is_empty()), "Mid-match join ends")
	check.call(reasons == ["Match in progress"], "Mid-match join gives its reason")
	check.call(not late.is_online(), "Refused client is offline")

	var left := []
	host.peer_left.connect(func(peer: int) -> void: left.append(peer))
	var a_peer := a.local_peer()
	a.leave()
	check.call(not a.is_online() and a.lobby.players.is_empty(), "Leaving resets the client")
	check.call(await _until(func() -> bool: return left == [a_peer]), "Host hears peer_left")
	check.call(
		await _until(func() -> bool: return _names(b) == ["Studio Mac", "Desk"]),
		"Leavers vanish from every lobby"
	)
	host.end_match()
	check.call(await _until(func() -> bool: return not b.lobby.in_match), "Match end reopens")
	check.call(await _join(a), "A client can rejoin after leaving")
	check.call(
		await _until(func() -> bool: return _names(b) == ["Studio Mac", "Desk", "Studio Mac 2"]),
		"Rejoiner goes to the back"
	)
	check.call(
		b.lobby.players[0].colour == CharacterAppearance.PALETTE[1],
		"Earlier players keep colours over rejoiners"
	)
	host.leave()
	await _until(func() -> bool: return not a.is_online() and not b.is_online())
	a.leave()
	b.leave()
	late.leave()


func _refusals(check: Callable) -> void:
	var host := _session("Host", "Host")
	var old := _session("Old", "Old")
	check.call(_host(host), "Second host opens")
	old._version = "0.0.0-old"
	var reasons := []
	old.session_closed.connect(func(reason: String) -> void: reasons.append(reason))
	old.join("127.0.0.1", _port)
	check.call(
		await _until(func() -> bool: return not reasons.is_empty()), "Old version is refused"
	)
	check.call(reasons == ["Different game version"], "Version refusal gives its reason")
	check.call(host.lobby.players.size() == 1, "Refused peers never enter the lobby")
	old._version = str(ProjectSettings.get_setting("application/config/version"))
	old._protocol = NetSession.PROTOCOL_VERSION + 1
	reasons.clear()
	old.join("127.0.0.1", _port)
	check.call(
		await _until(func() -> bool: return reasons == ["Different game version"]),
		"Protocol mismatch is refused"
	)
	old._protocol = NetSession.PROTOCOL_VERSION
	check.call(await _join(old), "Matching versions join after a refusal")
	host.leave()
	old.leave()

	var lonely := _session("Lonely", "Lonely")
	reasons.clear()
	lonely.session_closed.connect(func(reason: String) -> void: reasons.append(reason))
	lonely.join("127.0.0.1", _port)
	check.call(
		await _until(
			func() -> bool: return reasons == ["Could not connect"],
			int(NetSession.JOIN_TIMEOUT * 1000) + WAIT_MSEC
		),
		"Joining nobody times out with a reason"
	)


func _full_lobby(check: Callable) -> void:
	var host := _session("Host", "Host")
	check.call(_host(host), "Full lobby host opens")
	host.set_setup(NetSession.MAX_PLAYERS, 3, [])
	var guests: Array[NetSession] = []
	for index in NetSession.MAX_PLAYERS - 1:
		var guest := _session("Guest", "Guest")
		guest.join("127.0.0.1", _port)
		guests.append(guest)
	check.call(
		await _until(func() -> bool: return host.lobby.players.size() == NetSession.MAX_PLAYERS),
		"Ten humans fill the lobby"
	)
	check.call(host.lobby.setup.player_count == 10, "Ten humans need ten seats")
	check.call(_names(host)[9] == "Guest 9", "Many duplicates keep counting")
	var extra := _session("Extra", "Extra")
	var reasons := []
	extra.session_closed.connect(func(reason: String) -> void: reasons.append(reason))
	extra.join("127.0.0.1", _port)
	check.call(
		await _until(func() -> bool: return reasons == ["Lobby is full"]), "Full lobby refuses"
	)
	host.leave()
	for guest in guests:
		guest.leave()


## Players sets the lobby's size: people take seats, AI fills the rest, and a full lobby
## refuses joins until the host makes room.
func _lobby_size(check: Callable) -> void:
	var host := _session("Host", "Host")
	check.call(_host(host), "Sized lobby host opens")
	host.set_setup(3, 3, [])
	check.call(
		host.lobby_size() == 3 and host.ai_seats() == 2, "A lone host has AI in every other seat"
	)
	var first := _session("First", "First")
	var second := _session("Second", "Second")
	first.join("127.0.0.1", _port)
	second.join("127.0.0.1", _port)
	check.call(
		await _until(func() -> bool: return host.lobby.players.size() == 3),
		"People take the open seats"
	)
	check.call(
		await _until(func() -> bool: return first.lobby_size() == 3 and first.ai_seats() == 0),
		"Every peer sees the seats and how many AI remain"
	)
	var late := _session("Late", "Late")
	var reasons := []
	late.session_closed.connect(func(reason: String) -> void: reasons.append(reason))
	late.join("127.0.0.1", _port)
	check.call(
		await _until(func() -> bool: return reasons == ["Lobby is full"]),
		"A lobby whose seats are all people refuses joins"
	)
	host.set_setup(4, 3, [])
	var room := _session("Room", "Room")
	room.join("127.0.0.1", _port)
	check.call(
		await _until(
			func() -> bool: return host.lobby.players.size() == 4 and host.ai_seats() == 0
		),
		"Raising Players opens a seat for another person"
	)
	for session in [host, first, second, late, room]:
		session.leave()
	await _until(func() -> bool: return not host.is_online())


func _host_leaves(check: Callable) -> void:
	var host := _session("Host", "Host")
	var guest := _session("Guest", "Guest")
	check.call(_host(host), "Last host opens")
	check.call(await _join(guest), "Guest joins last host")
	var reasons := []
	guest.session_closed.connect(func(reason: String) -> void: reasons.append(reason))
	var host_reasons := []
	host.session_closed.connect(func(reason: String) -> void: host_reasons.append(reason))
	host.leave()
	check.call(
		await _until(func() -> bool: return reasons == ["Host left"]), "Host leaving closes clients"
	)
	check.call(not guest.is_online() and guest.lobby.players.is_empty(), "Closed client resets")
	check.call(host_reasons.is_empty(), "A voluntary leave does not report session_closed")
	check.call(_host(host), "The same session can host again")
	check.call(await _join(guest), "And be rejoined")
	host.leave()
	guest.leave()
