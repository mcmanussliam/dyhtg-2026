extends RefCounted
## LAN beacons reach a localhost listener, foreign packets are ignored, silence expires.


func run(tree: SceneTree, check: Callable) -> void:
	check.call(
		(
			LanDiscovery._parse_broadcasts(
				(
					"inet 10.56.203.207 netmask 0xffff8000 broadcast 10.56.255.255\n"
					+ "inet 192.168.4.2 netmask 0xffffff00 broadcast 192.168.4.255\n"
					+ "inet 10.56.203.208 broadcast 10.56.255.255\n"
					+ "inet6 fe80::1 prefixlen 64\n"
				)
			)
			== PackedStringArray(["10.56.255.255", "192.168.4.255"])
		),
		"macOS broadcasts preserve actual subnets and deduplicate routes"
	)
	check.call(
		(
			LanDiscovery._parse_broadcasts(
				(
					"2: eth0 inet 172.16.3.2/20 brd 172.16.15.255 scope global eth0\n"
					+ "inet 127.0.0.1 broadcast 127.255.255.255\n"
					+ "inet 1.2.3.4 broadcast 999.1.2.3\n"
				)
			)
			== PackedStringArray(["172.16.15.255"])
		),
		"Linux broadcasts exclude loopback and malformed addresses"
	)
	check.call(
		(
			LanDiscovery._parse_windows_broadcasts(
				(
					"10.56.203.207/17\r\n192.168.4.2/24\r\n10.56.203.208/17\r\n"
					+ "127.0.0.1/8\n192.168.1.1/32\n1.2.3.4/31\n1.2.3.4/no\n"
					+ "999.1.2.3/24\nfe80::1/64\n"
				)
			)
			== PackedStringArray(["10.56.255.255", "192.168.4.255"])
		),
		"Windows subnet prefixes produce broadcasts without assuming /24"
	)
	var listener := LanDiscovery.new()
	var beacon := LanDiscovery.new()
	var reservation := PacketPeerUDP.new()
	check.call(reservation.bind(0, "127.0.0.1") == OK, "Discovery test port reserved")
	listener.discovery_port = reservation.get_local_port()
	beacon.discovery_port = listener.discovery_port
	reservation.close()
	tree.root.add_child(listener)
	tree.root.add_child(beacon)
	var changes := [0]
	listener.games_changed.connect(func() -> void: changes[0] += 1)
	listener.start_listening()
	await tree.process_frame
	listener._process(0.0)
	check.call(listener.is_listening(), "Isolated discovery listener binds")
	if not listener.is_listening():
		_free(listener, beacon)
		return
	var stranger := PacketPeerUDP.new()
	stranger.set_dest_address("127.0.0.1", listener._listener.get_local_port())
	stranger.put_packet("not json".to_utf8_buffer())
	var foreign := {
		"game": "other_game",
		"id": "x",
		"protocol": 1,
		"version": "1",
		"name": "Other",
		"port": 1,
		"players": 1,
		"max": 2
	}
	stranger.put_packet(JSON.stringify(foreign).to_utf8_buffer())
	beacon.start_beacon("Beacon  Desk", 45678, 2, 10)
	# Disable unsolicited beacons: finding this host must use a query and unicast reply.
	beacon._next_beacon = Time.get_ticks_msec() + 60000
	beacon._next_target_refresh = Time.get_ticks_msec() + 60000
	beacon._targets = PackedStringArray(["127.0.0.1"])
	check.call(
		await _until(tree, func() -> bool: return _ours(listener) != null),
		"Active query discovers a host without unsolicited beacons"
	)
	var game: Dictionary = _ours(listener)
	check.call(
		game.name == "Beacon Desk" and game.players == 2 and game.max == 10,
		"Beacon carries name and player counts"
	)
	check.call(not game.address.is_empty(), "Address comes from the packet source")
	check.call(
		listener.games.all(func(entry: Dictionary) -> bool: return entry.name != "Other"),
		"Other games and junk are ignored"
	)
	var before: int = changes[0]
	await _until(tree, func() -> bool: return false, 1500)
	check.call(changes[0] == before, "Repeated beacons do not re-announce an unchanged list")
	check.call(
		(
			(
				listener
				. games
				. filter(func(entry: Dictionary) -> bool: return entry.port == 45678)
				. size()
			)
			== 1
		),
		"A beacon heard on two routes is listed once"
	)
	beacon.update_beacon(3)
	check.call(
		await _until(tree, func() -> bool: return _players(listener) == 3), "Player count updates"
	)
	beacon.stop_beacon()
	check.call(
		await _until(tree, func() -> bool: return _ours(listener) == null, 5000),
		"Silent beacons expire"
	)
	await _hosted_session(tree, listener, check)
	var second := LanDiscovery.new()
	tree.root.add_child(second)
	second.discovery_port = listener.discovery_port
	second.start_listening()
	await tree.process_frame
	second._process(0.0)
	check.call(second.is_listening(), "Two Join pages can search on the same machine")
	check.call(
		second._listener.get_local_port() != listener._listener.get_local_port(),
		"Each searching guest owns a separate reply port"
	)
	second.stop_listening()
	second.queue_free()
	_free(listener, beacon)


## A hosting NetSession announces its lobby until it starts a match.
func _hosted_session(tree: SceneTree, listener: LanDiscovery, check: Callable) -> void:
	var branch := Node.new()
	branch.name = "NetDiscoveryHost"
	tree.root.add_child(branch)
	tree.set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var session := NetSession.new()
	session._discovery = LanDiscovery.new()
	session._discovery.discovery_port = listener.discovery_port
	session.add_child(session._discovery)
	session.local_name = "Announced"
	branch.add_child(session)
	var port := randi_range(40001, 50000)
	check.call(session.host(port) == OK, "Announcing host opens")
	check.call(
		await _until(tree, func() -> bool: return _ours(listener, port) != null),
		"A hosting session announces itself"
	)
	var game: Variant = _ours(listener, port)
	check.call(
		game != null and game.name == "Lobby" and game.players == 1,
		"Announcement uses a generic lobby name"
	)
	session.start_match()
	check.call(
		await _until(tree, func() -> bool: return _ours(listener, port) == null, 5000),
		"Matches in progress stop announcing"
	)
	session.leave()
	tree.set_multiplayer(null, branch.get_path())
	branch.queue_free()


func _ours(listener: LanDiscovery, port := 45678) -> Variant:
	for game in listener.games:
		if game.port == port:
			return game
	return null


func _players(listener: LanDiscovery) -> int:
	var game: Variant = _ours(listener)
	return game.players if game != null else -1


func _until(tree: SceneTree, condition: Callable, wait_msec := 3000) -> bool:
	var deadline := Time.get_ticks_msec() + wait_msec
	while not condition.call():
		if Time.get_ticks_msec() > deadline:
			return false
		await tree.process_frame
	return true


func _free(listener: LanDiscovery, beacon: LanDiscovery) -> void:
	listener.stop_listening()
	beacon.stop_beacon()
	listener.queue_free()
	beacon.queue_free()
