extends RefCounted
## Play, Multiplayer, Join and Lobby pages against session, discovery and match doubles.

const FakeNet = preload("res://tests/app/online_fake_net.gd")
const FakeDiscovery = preload("res://tests/app/online_fake_discovery.gd")
const FakeMatch = preload("res://tests/app/online_fake_match.gd")


func run(tree: SceneTree, check: Callable) -> void:
	_check_command_line(check)
	var net := FakeNet.new()
	var discovery := FakeDiscovery.new()
	var app := GameApp.new()
	app.appearance_path = ""
	app.settings_path = ""
	app.web_build = false
	app.net = net
	app.discovery = discovery
	tree.root.add_child(app)
	await tree.process_frame
	check.call(
		app.get_node_or_null("NetSession") == net and discovery.get_parent() == app,
		"The app owns one NetSession child and one discovery child"
	)
	await _activate(tree, app, "Play")
	check.call(
		app.current_menu._items == PackedStringArray(["Single player", "Multiplayer", "Back"]),
		"Play opens Single player, Multiplayer and Back"
	)
	await _activate(tree, app, "Single player")
	check.call(
		app.current_menu._items.size() == 5 and app.current_menu._items[0] == "Players 6",
		"Single player opens the unchanged setup page"
	)
	await _activate(tree, app, "Back")
	check.call(app.current_menu._items[1] == "Multiplayer", "Setup Back returns to the Play page")
	await _activate(tree, app, "Back")
	check.call(app.current_menu._items[0] == "Play", "Play Back returns home")
	await _check_web(tree, app, check)
	await _activate(tree, app, "Play")
	await _activate(tree, app, "Multiplayer")
	check.call(
		app.current_menu._items == PackedStringArray(["Host game", "Join game", "Back"]),
		"Multiplayer opens Host game, Join game and Back"
	)
	await _check_host(tree, app, net, discovery, check)
	await _check_join(tree, app, net, discovery, check)
	await _check_client_match(tree, app, net, check)
	app._apply_command_line(GameApp.parse_command_line(PackedStringArray(["--join=10.0.0.2"])))
	await tree.process_frame
	check.call(
		net.calls.back() == ["join", "10.0.0.2", NetSession.DEFAULT_PORT] and app._page == &"lobby",
		"--join joins that address and opens the client lobby"
	)
	net.session_closed.emit("Host left")
	await tree.process_frame
	app._apply_command_line(GameApp.parse_command_line(PackedStringArray(["--host"])))
	await tree.process_frame
	check.call(
		net.calls.back() == ["host", NetSession.DEFAULT_PORT] and app._page == &"lobby",
		"--host hosts immediately and opens the host lobby"
	)
	app.queue_free()
	await tree.process_frame


func _check_command_line(check: Callable) -> void:
	var none := GameApp.parse_command_line(PackedStringArray())
	var hosting := GameApp.parse_command_line(PackedStringArray(["--host", "--name=Desk"]))
	var joining := GameApp.parse_command_line(PackedStringArray(["--join=192.168.1.5"]))
	check.call(
		(
			not none.host
			and none.join == ""
			and hosting.host
			and hosting.join == ""
			and not joining.host
			and joining.join == "192.168.1.5"
		),
		"Command-line parsing reads --host and --join and ignores --name"
	)


func _check_web(tree: SceneTree, app: GameApp, check: Callable) -> void:
	app.web_build = true
	app.show_play()
	await tree.process_frame
	check.call(
		app.current_menu._rows[1].get_theme_color("font_color") == Color(0.45, 0.45, 0.45),
		"The Web build greys out Multiplayer"
	)
	app.current_menu.chosen = 1
	await _tap(tree, KEY_RIGHT)
	await tree.process_frame
	check.call(app._page == &"play", "The Web build cannot activate Multiplayer")
	app.web_build = false
	app.show_home()
	await tree.process_frame


func _check_host(
	tree: SceneTree, app: GameApp, net: FakeNet, discovery: FakeDiscovery, check: Callable
) -> void:
	net.host_result = ERR_CANT_CREATE
	await _activate(tree, app, "Host game")
	var menu := app.current_menu
	check.call(
		(
			app._page == &"multiplayer"
			and menu._items[0] == "Could not host game"
			and menu.is_info(0)
			and menu.chosen == 1
		),
		"A failed host stays on Multiplayer with a non-selectable reason"
	)
	var visited := {}
	for step in 4:
		await _tap(tree, KEY_LEFT)
		visited[menu.chosen] = true
	check.call(not visited.has(0), "The cursor skips the reason row")
	net.host_result = OK
	var sends := net.appearance_sends
	await _activate(tree, app, "Host game")
	menu = app.current_menu
	var stages := MatchConfig.available_stages().size()
	check.call(
		(
			app._page == &"lobby"
			and menu._items[0] == "Yellow"
			and menu._values[0] == "Host"
			and menu._items[1] == "AI players"
			and menu._values[1] == "5"
			and menu.is_info(1)
			and menu._items[2] == "Players 6"
			and menu.chosen == 2
		),
		"The host lobby lists players, then AI filling the other seats, then the options"
	)
	check.call(
		(
			net.setups.back().player_count == 6
			and net.setups.back().wins_needed == 3
			and net.setups.back().stages.size() == stages
			and net.appearance_before_connect == sends + 1
		),
		"Hosting sends the local appearance first, then the setup"
	)
	await _tap(tree, KEY_LEFT)
	net.set_players([net.lobby.players[0], FakeNet.player(2, "Desk PC", MatchState.COLOURS[8])])
	check.call(
		(
			menu._items[1] == "Lime"
			and menu._values[1] == ""
			and menu._values[2] == "4"
			and menu._items[menu.chosen] == "First to 3 wins"
		),
		"A joining player takes an AI seat and the cursor keeps its option"
	)
	for step in 6:
		await _tap(tree, KEY_LEFT)
		check.call(not menu.is_info(menu.chosen), "Lobby player rows are skipped (%d)" % step)
	await _activate(tree, app, "Players 6")
	check.call(
		(
			net.setups.back().player_count == 7
			and menu._items[3] == "Players 7"
			and menu._values[2] == "5"
		),
		"Players changes the lobby size, and AI fill the new seat"
	)
	for step in 3:
		await _tap(tree, KEY_RIGHT)
	await _tap(tree, KEY_RIGHT)
	check.call(
		(
			net.setups.back().player_count == 2
			and menu._items[2] == "Players 2"
			and not menu._items.has("AI players")
		),
		"Players wraps from ten to the human count, leaving no AI seats"
	)
	await _activate(tree, app, "First to 3 wins")
	check.call(net.setups.back().wins_needed == 4, "First to N changes the lobby setup")
	await _activate(tree, app, "Select maps")
	check.call(app.current_menu is MapSelectionMenu, "Select maps opens the map list")
	await _tap(tree, KEY_LEFT)
	await _tap(tree, KEY_RIGHT)
	check.call(
		net.setups.back().stages.size() == stages - 1 and app.config.stages.size() == stages,
		"Map toggles update the lobby setup without changing single player"
	)
	await _tap(tree, KEY_LEFT)
	await _activate(tree, app, "Back")
	check.call(app._page == &"lobby", "Map Back returns to the lobby")
	await _activate(tree, app, "Start game")
	check.call(net.start_requests == 1, "Start match asks the session to start")
	app.match_script = FakeMatch
	var roster := [
		{
			"id": 0,
			"peer": 1,
			"name": "Studio Mac",
			"hat_id": &"none",
			"top_id": &"none",
			"colour": MatchState.COLOURS[0],
			"wins": 0
		}
	]
	var setup := {"wins_needed": 4, "stages": [MatchConfig.available_stages()[0].id]}
	net.match_started.emit(roster, setup)
	await tree.process_frame
	var controller := app.match_controller as FakeMatch
	check.call(
		(
			controller != null
			and controller.online_start == [net, roster, setup]
			and not is_instance_valid(app.screen)
		),
		"match_started replaces the lobby with an online match"
	)
	await _present_results(tree, app, false)
	await _tap(tree, KEY_RIGHT)
	await tree.process_frame
	check.call(
		controller.result_actions == [&"continue"] and not is_instance_valid(app.screen),
		"Online Continue is forwarded to the match"
	)
	await _present_results(tree, app, false)
	await _tap(tree, KEY_LEFT)
	await tree.process_frame
	check.call(
		controller.result_actions.back() == &"home" and not net.called("leave"),
		"The host's Home is forwarded without leaving the session"
	)
	controller.online_finished.emit()
	await tree.process_frame
	await tree.process_frame
	check.call(
		app._page == &"lobby" and not is_instance_valid(app.match_controller),
		"online_finished returns to the lobby"
	)
	await _activate(tree, app, "Leave")
	check.call(
		net.called("leave") and not discovery.beacon_used and app._page == &"multiplayer",
		"Leave ends the session and returns to Multiplayer; the session owns the beacon"
	)


func _check_join(
	tree: SceneTree, app: GameApp, net: FakeNet, discovery: FakeDiscovery, check: Callable
) -> void:
	discovery.games.clear()
	await _activate(tree, app, "Join game")
	var menu := app.current_menu
	check.call(
		(
			discovery.listening
			and menu._items == PackedStringArray(["Searching…", "Back"])
			and menu.chosen == 1
		),
		"Join listens and shows an inactive searching row"
	)
	(
		discovery
		. set_games(
			[
				{
					"address": "10.0.0.4",
					"port": 7777,
					"name": "Studio Mac",
					"players": 2,
					"max": 10
				},
				{"address": "10.0.0.9", "port": 7790, "name": "Desk PC", "players": 1, "max": 10},
			]
		)
	)
	check.call(
		(
			menu._items == PackedStringArray(["Lobby 1", "Lobby 2", "Back"])
			and menu._values[0] == "2/10"
			and menu._items[menu.chosen] == "Back"
		),
		"Discovered games refresh the list and the cursor stays on Back"
	)
	var sends := net.appearance_sends
	await _activate(tree, app, "Lobby 2")
	check.call(
		(
			net.calls.back() == ["join", "10.0.0.9", 7790]
			and net.appearance_before_connect == sends + 1
			and not discovery.listening
			and app._page == &"lobby"
			and app.current_menu._items[0] == "Connecting…"
		),
		"Choosing a game joins its address and opens the client lobby"
	)
	net.session_closed.emit("Game is full")
	await tree.process_frame
	await tree.process_frame
	menu = app.current_menu
	check.call(
		(
			app._page == &"join"
			and menu._items[0] == "Game is full"
			and menu.is_info(0)
			and discovery.listening
		),
		"A refused join returns to the Join page with the reason"
	)
	net.join_result = ERR_CANT_CONNECT
	await _activate(tree, app, "Lobby 1")
	check.call(
		app._page == &"join" and app.current_menu._items[0] == "Could not join game",
		"A failed join stays on Join with the reason"
	)
	net.join_result = OK


func _check_client_match(tree: SceneTree, app: GameApp, net: FakeNet, check: Callable) -> void:
	await _activate(tree, app, "Lobby 1")
	var stage := MatchConfig.available_stages()[0].id
	net.lobby.setup = {"player_count": 6, "wins_needed": 2, "stages": [stage]}
	(
		net
		. set_players(
			[
				FakeNet.player(1, "Studio Mac", MatchState.COLOURS[0]),
				FakeNet.player(2, "Desk PC", MatchState.COLOURS[3]),
			]
		)
	)
	var menu := app.current_menu
	check.call(
		(
			(
				menu._items
				== PackedStringArray(
					[
						"Yellow",
						"Blue",
						"AI players",
						"Players 6",
						"First to 2 wins",
						"1 map",
						"Leave"
					]
				)
			)
			and menu._values[1] == ""
			and menu._values[2] == "4"
			and menu.chosen == 6
		),
		"The client lobby shows players and read-only host settings"
	)
	await _tap(tree, KEY_LEFT)
	check.call(menu.chosen == 6, "Client settings are read-only and only Leave is selectable")
	var sends := net.appearance_sends
	app.show_customisation()
	await tree.process_frame
	await _tap(tree, KEY_RIGHT)
	check.call(net.appearance_sends == sends + 1, "Customising while connected sends appearance")
	app.show_lobby()
	await tree.process_frame
	app.match_script = MatchController
	var roster := []
	for player: Dictionary in net.lobby.players:
		roster.append(
			{
				"id": roster.size(),
				"peer": player.peer,
				"name": player.name,
				"hat_id": &"none",
				"top_id": &"none",
				"colour": player.colour,
				"wins": 0
			}
		)
	net.match_started.emit(roster, {"wins_needed": 2, "stages": [stage]})
	await tree.process_frame
	check.call(
		app.match_controller is MatchController and is_instance_valid(app.match_controller),
		"match_started creates a MatchController and starts it online"
	)
	var started := app.match_controller
	net.session_closed.emit("Host left")
	await tree.process_frame
	await tree.process_frame
	check.call(
		(
			not is_instance_valid(started)
			and app._page == &"multiplayer"
			and app.current_menu._items[0] == "Host left"
		),
		"session_closed tears down the match and returns to Multiplayer with the reason"
	)
	await _activate(tree, app, "Join game")
	await _activate(tree, app, "Lobby 1")
	net.set_players([FakeNet.player(2, "Desk PC", MatchState.COLOURS[3])])
	app.match_script = FakeMatch
	net.match_started.emit([], {})
	await tree.process_frame
	var controller := app.match_controller as FakeMatch
	var actions := controller.result_actions
	await _present_results(tree, app, false)
	await _tap(tree, KEY_RIGHT)
	await tree.process_frame
	check.call(
		actions == [&"continue"] and app.screen is ResultsScreen,
		"A client's Continue is forwarded and the results wait for the host"
	)
	controller.emit_signal(&"round_began", 2)
	await tree.process_frame
	check.call(not is_instance_valid(app.screen), "round_began closes a client's results")
	controller.match_over = true
	await _present_results(tree, app, true)
	await _tap(tree, KEY_LEFT)
	await tree.process_frame
	check.call(
		actions.back() == &"home" and net.calls.back()[0] == "join",
		"A client's Home once the match is over waits for the lobby instead of leaving"
	)
	controller.match_over = false
	await _present_results(tree, app, false)
	await _tap(tree, KEY_LEFT)
	await tree.process_frame
	check.call(
		actions.size() == 3 and net.calls.back() == ["leave"] and app._page == &"multiplayer",
		"A client's Home between rounds leaves the session for Multiplayer"
	)


func _present_results(tree: SceneTree, app: GameApp, final_result: bool) -> void:
	var participants: Array[Dictionary] = [
		{"id": 0, "name": "Studio Mac", "colour": MatchState.COLOURS[0], "wins": 1},
		{"id": 1, "name": "AI 1", "colour": MatchState.COLOURS[1], "wins": 0},
	]
	app.match_controller.results_ready.emit(participants, 0, 3, final_result, 1)
	await tree.process_frame


## Left until the labelled row is chosen, then Right, letting the next page settle.
func _activate(tree: SceneTree, app: GameApp, label: String) -> void:
	var menu := app.current_menu
	for step in menu._items.size():
		if menu._items[menu.chosen] == label:
			break
		await _tap(tree, KEY_LEFT)
	await _tap(tree, KEY_RIGHT)
	await tree.process_frame
	await tree.process_frame


func _tap(tree: SceneTree, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await tree.process_frame
	event = InputEventKey.new()
	event.physical_keycode = key
	Input.parse_input_event(event)
	await tree.process_frame
