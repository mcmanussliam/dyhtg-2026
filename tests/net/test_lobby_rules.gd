extends RefCounted
## Pure session rules: names, appearance validation, colours, setup and roster.


func run(tree: SceneTree, check: Callable) -> void:
	await tree.process_frame
	_names(check)
	_appearance(check)
	_colours(check)
	_setup(check)
	_roster(check)


func _player(peer: int, name: String, colour_id: StringName) -> Dictionary:
	return {
		"peer": peer,
		"name": name,
		"hat_id": &"none",
		"top_id": &"none",
		"colour_id": colour_id,
		"colour": Color.TRANSPARENT,
	}


func _names(check: Callable) -> void:
	check.call(MachineName.clean("  Studio \t Mac\n ") == "Studio Mac", "Names collapse whitespace")
	check.call(MachineName.clean("x".repeat(40)).length() == 24, "Names are at most 24 characters")
	check.call(MachineName.clean(" \t ").is_empty(), "Blank names clean to empty")
	check.call(
		MachineName.override(PackedStringArray(["--host", "--name=Desk 4"])) == "Desk 4",
		"--name= override is parsed"
	)
	check.call(MachineName.override(PackedStringArray(["--host"])).is_empty(), "No override")
	check.call(
		MachineName.resolve(PackedStringArray(["--name=  Big   Desk "])) == "Big Desk",
		"--name override wins and is cleaned"
	)
	check.call(
		not MachineName.resolve(PackedStringArray(["--name=   "])).is_empty(),
		"Blank override falls back to a non-empty name"
	)
	check.call(not MachineName.local().is_empty(), "Local machine name is never empty")
	var first := MachineName.local()
	check.call(MachineName.local() == first, "Local machine name is cached")
	var players := [_player(1, "Studio Mac", &"random")]
	check.call(LobbyRules.unique_name("Studio Mac", players) == "Studio Mac 2", "Names de-dupe")
	players.append(_player(2, "Studio Mac 2", &"random"))
	check.call(LobbyRules.unique_name("Studio Mac", players) == "Studio Mac 3", "Next free suffix")
	check.call(LobbyRules.unique_name("", players) == "Player", "Empty names become Player")
	var long_name := "y".repeat(24)
	players.append(_player(3, long_name, &"random"))
	var numbered := LobbyRules.unique_name(long_name, players)
	check.call(
		numbered.length() <= 24 and numbered.ends_with(" 2"), "Suffixed names stay within limit"
	)


func _appearance(check: Callable) -> void:
	check.call(LobbyRules.valid_hat(&"top_hat") == &"top_hat", "Known hats pass")
	check.call(LobbyRules.valid_hat(&"jetpack") == &"none", "Unknown hats become none")
	check.call(LobbyRules.valid_hat(42) == &"none", "Non-string hats become none")
	var skin := SkinCatalog.definitions()[1].id
	check.call(LobbyRules.valid_top(String(skin)) == skin, "Known tops pass")
	check.call(LobbyRules.valid_top(&"cape") == &"none", "Unknown tops become none")
	check.call(LobbyRules.valid_colour("mint") == &"mint", "Known colours pass")
	check.call(LobbyRules.valid_colour(&"plaid") == &"random", "Unknown colours become random")


func _colours(check: Callable) -> void:
	var palette := CharacterAppearance.PALETTE
	var players := [_player(1, "A", &"mint"), _player(2, "B", &"mint")]
	LobbyRules.resolve_colours(players)
	check.call(players[0].colour == palette[1], "Earliest joiner keeps a clashing colour")
	check.call(players[1].colour == MatchState.COLOURS[0], "Clash takes the next free colour")
	players.append(_player(3, "C", &"random"))
	LobbyRules.resolve_colours(players)
	check.call(players[2].colour == MatchState.COLOURS[2], "Random takes the next free colour")
	players.remove_at(0)
	LobbyRules.resolve_colours(players)
	check.call(players[0].colour == palette[1], "A freed colour returns to its later fan")
	var seen := []
	var crowd := []
	for index in 10:
		crowd.append(_player(index + 1, "P%d" % index, &"yellow"))
	LobbyRules.resolve_colours(crowd)
	for player in crowd:
		if player.colour not in seen:
			seen.append(player.colour)
	check.call(seen.size() == 10, "Ten humans get ten distinct colours")


func _setup(check: Callable) -> void:
	var all := LobbyRules.stage_ids()
	check.call(all.size() == MatchConfig.STAGE_PATHS.size(), "Every registered stage is known")
	var setup := LobbyRules.clamp_setup(1, 9, [], 1)
	check.call(setup.player_count == 2, "At least two seats")
	check.call(setup.wins_needed == 5, "Wins clamp to five")
	check.call(setup.stages == all, "No stages selects every stage")
	setup = LobbyRules.clamp_setup(3, 0, [all[1], &"moon", all[1]], 4)
	check.call(setup.player_count == 4, "Seats cover every human")
	check.call(setup.wins_needed == 1, "Wins clamp to one")
	check.call(setup.stages == [all[1]], "Unknown and repeated stages are dropped")
	check.call(LobbyRules.clamp_setup(15, 3, [], 1).player_count == 10, "At most ten seats")


func _roster(check: Callable) -> void:
	var players := [_player(1, "Host", &"yellow"), _player(5, "Guest", &"random")]
	players[1].hat_id = &"cap"
	LobbyRules.resolve_colours(players)
	var roster := LobbyRules.build_roster(players, 4)
	check.call(roster.size() == 4, "Roster fills seats to the player count")
	check.call(
		roster[0].peer == 1 and roster[0].id == 0 and roster[1].peer == 5,
		"Humans take the first seats in join order"
	)
	check.call(roster[1].hat_id == &"cap", "Roster keeps human cosmetics")
	check.call(
		roster[2].peer == 0 and roster[2].name == "AI 1" and roster[3].name == "AI 2",
		"AI seats are numbered"
	)
	var colours := []
	for seat in roster:
		check.call(seat.wins == 0 and seat.has("top_id"), "Roster seat has every field")
		if seat.colour not in colours:
			colours.append(seat.colour)
	check.call(colours.size() == 4, "AI seats take colours the humans left")
	check.call(roster[2].colour == MatchState.COLOURS[2], "AI colours follow the palette order")
