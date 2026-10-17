extends RefCounted
## Pure match bookkeeping checks; no scene or UI dependencies.


func run(tree: SceneTree, check: Callable) -> void:
	await tree.process_frame
	var config := MatchConfig.new()
	config.player_count = 4
	config.wins_needed = 2
	var state := MatchState.new()
	state.configure(config)
	check.call(state.participants.size() == 4, "Match creates human and configured AI seats")
	check.call(state.participants[0]["name"] == "You", "Human has stable first seat")
	check.call(not state.record_result(0, 0), "No result accepted before first round")
	var first := state.begin_round()
	check.call(state.begin_round() == first, "An unresolved round cannot be replaced")
	check.call(not state.record_result(first + 1, 0), "Future round result is rejected")
	check.call(not state.record_result(first, 4), "Unknown winner seat is rejected")
	check.call(not state.record_result(first, -2), "Invalid negative winner is rejected")
	check.call(state.record_result(first, 0), "Valid round win is accepted")
	check.call(not state.record_result(first, 1), "Duplicate round result cannot award wins")
	check.call(state.participants[0]["wins"] == 1, "Round win awards exactly one point")
	var second := state.begin_round()
	check.call(not state.record_result(first, 0), "Stale round result is rejected")
	check.call(state.record_result(second, -1), "Draw round is accepted")
	check.call(state.participants[0]["wins"] == 1, "Draw awards no points")
	check.call(not state.record_result(second, 0), "Draw cannot later become a win")
	config.wins_needed = 5
	config.player_count = 2
	check.call(state.wins_needed == 2, "Running match is isolated from setup edits")
	check.call(state.participants.size() == 4, "Setup edits cannot remove live participants")
	var third := state.begin_round()
	check.call(state.record_result(third, 0), "Decisive win is accepted")
	check.call(state.winner_id == 0, "First participant to target wins the match")
	check.call(state.begin_round() == third, "Finished match cannot begin another round")
	check.call(not state.record_result(third, 1), "Finished match cannot score again")
	state.configure(config)
	check.call(state.winner_id == -1 and state.round_number == 0, "Rematch resets match flow")
	check.call(state.participants[0]["wins"] == 0, "Rematch resets participant scores")
	check.call(state.participants.size() == 2, "New setup is applied on rematch")
	config.player_count = -5
	check.call(config.validated_copy().player_count == 2, "Player count minimum is two")
	config.player_count = 100
	config.wins_needed = 0
	state.configure(config)
	check.call(state.participants.size() == 10, "Player count is clamped to ten supported seats")
	check.call(state.wins_needed == 1, "Win target cannot be zero")
	check.call(config.wins_needed == 0, "Validation does not mutate shared setup resource")
	var separate := MatchState.new()
	separate.configure(config)
	state.record_result(state.begin_round(), 1)
	check.call(separate.participants[1]["wins"] == 0, "Separate matches never share scores")
