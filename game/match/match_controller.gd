class_name MatchController
extends Node
## Match owns round lifetime; MatchState alone awards wins. Online, the host runs this
## exactly as offline and streams it; clients mirror the host (docs/multiplayer.md).

signal results_ready(
	participants: Array[Dictionary],
	winner_id: int,
	target_wins: int,
	final_result: bool,
	round_number: int
)

## Online: the match is over and every peer returns to the lobby.
signal online_finished
## A new round scene exists (online clients clear their results screen here).
signal round_began(round_number: int)

const ROUND_SCENE = preload("res://game/round/round.tscn")

var config: MatchConfig
var state := MatchState.new()
var round: RoundController
var net: NetSession
var _transition_pending: bool = false
var _generation: int = 0
var _online := false
var _ended := false
var _local_seat := 0
## Host: remote human seats, seat -> latest turn. Shared with each round by reference.
var _remote_turns: Dictionary = {}
var _stages_by_id: Dictionary = {}
var _next_fast_snapshot := 0
var _fast_forward_peers: Dictionary = {}


func start(setup: MatchConfig) -> void:
	_generation += 1
	_transition_pending = false
	config = setup.validated_copy()
	state.configure(config)
	_replace_round()


## Online match from a NetSession roster (docs/multiplayer.md). The host simulates and
## streams; a client waits for the host's `&"round"` message.
func start_online(session: NetSession, roster: Array, setup: Dictionary) -> void:
	_stop()
	_generation += 1
	_online = true
	_ended = false
	net = session
	config = MatchConfig.new()
	config.wins_needed = clampi(int(setup.get("wins_needed", config.wins_needed)), 1, 5)
	config.player_count = roster.size()
	_stages_by_id.clear()
	for definition in MatchConfig.available_stages():
		_stages_by_id[definition.id] = definition
	config.stages.clear()
	for id: Variant in setup.get("stages", []):
		if (id is String or id is StringName) and _stages_by_id.has(StringName(id)):
			config.stages.append(_stages_by_id[StringName(id)])
	if config.stages.is_empty():
		config.stages = MatchConfig.available_stages()
	state.configure_roster(roster, config.wins_needed)
	_local_seat = -1
	_remote_turns.clear()
	for participant in state.participants:
		if participant.peer == net.local_peer():
			_local_seat = participant.id
		elif participant.peer != 0:
			_remote_turns[participant.id] = 0.0
	net.message_received.connect(_on_message)
	net.peer_left.connect(_on_peer_left)
	net.session_closed.connect(_on_session_closed)
	if net.is_host():
		_replace_round()


## Online: a results-screen action (&"continue" or &"home"). Only the host advances.
func handle_result_action(action: StringName) -> void:
	if not _online or _ended:
		return
	var final_result := state.winner_id != -1
	if net.is_host():
		if action == &"continue" and not final_result:
			continue_round()
		elif action == &"home" or final_result:
			_finish_online()
	elif final_result:
		_finish_online()
	elif action == &"home":
		# The app leaves the session; this match simply stops.
		_ended = true
		_stop()


## Online: true once the host's final result has arrived (or been decided).
func is_match_over() -> bool:
	return state.winner_id != -1


func continue_round() -> void:
	if (
		_transition_pending
		or state.winner_id != -1
		or round.phase != RoundController.Phase.FINISHED
	):
		return
	_transition_pending = true
	_continue_if_current.call_deferred(_generation)


func _continue_if_current(generation: int) -> void:
	if not is_inside_tree() or not _transition_pending or generation != _generation:
		return
	_replace_round()


func _replace_round() -> void:
	var number := state.begin_round()
	var definition := config.stage_for_round(number)
	if _online:
		# Clients build the same round before the first snapshot can reach them.
		for seat in _remote_turns:
			_remote_turns[seat] = 0.0
		net.broadcast(
			&"round", {"round": number, "stage": definition.id, "roster": state.roster_entries()}
		)
	_build_round(definition, number, false)


func _build_round(definition: StageDefinition, number: int, mirror: bool) -> void:
	_free_round()
	round = ROUND_SCENE.instantiate() as RoundController
	round.configure(state.participants, definition, number, state.wins_needed)
	if _online:
		round.local_seat = _local_seat
		round.allow_fast_forward = true
		round.mirror = mirror
		if not mirror:
			round.remote_turns = _remote_turns
	round.completed.connect(_on_completed)
	round.fast_forward_requested.connect(_request_fast_forward)
	add_child(round)
	if _online and not mirror:
		round.eliminated.connect(_on_eliminated)
		round.decided.connect(_on_decided)
		round.stage.net_event.connect(_on_stage_event.bind(number))
	_transition_pending = false
	_fast_forward_peers.clear()
	_next_fast_snapshot = 0
	round_began.emit(number)


func _request_fast_forward(held: bool) -> void:
	if _ended or not _online or net.is_host() or not is_instance_valid(round):
		return
	net.send_to_host(&"fast_forward", {"round": round.round_id, "held": held})


func _free_round() -> void:
	if is_instance_valid(round):
		remove_child(round)
		round.queue_free()
	round = null


func _on_completed(id: int, winner: int) -> void:
	if not state.record_result(id, winner):
		return
	if _online:
		_send_event(
			{
				"type": &"results",
				"round": id,
				"winner": winner,
				"match_winner": state.winner_id,
				"wins": state.wins(),
			}
		)
	results_ready.emit(
		state.participants.duplicate(true),
		winner,
		state.wins_needed,
		state.winner_id != -1,
		state.round_number
	)


func _physics_process(_delta: float) -> void:
	if not _online or _ended or not is_instance_valid(round):
		return
	if net.is_host():
		if round.phase != RoundController.Phase.FINISHED:
			# Acceleration increases simulation ticks, while network updates stay at
			# normal wall-clock frequency. Reliable events still send immediately.
			if round.is_fast_forwarding():
				var now := Time.get_ticks_msec()
				if now < _next_fast_snapshot:
					return
				_next_fast_snapshot = now + 16
			net.broadcast(&"snapshot", round.net_snapshot(), false)
	elif round.phase == RoundController.Phase.LIVE:
		net.send_to_host(&"input", round.local_turn, false)


func _send_event(payload: Dictionary) -> void:
	net.broadcast(&"event", payload)


func _on_eliminated(seat: int, reason: StringName) -> void:
	var chair := round.chairs[seat]
	_send_event(
		{
			"type": &"eliminated",
			"round": round.round_id,
			"seat": seat,
			"reason": reason,
			"falling": chair.falling,
			"position": chair.global_position,
			"rotation": chair.global_rotation,
			"fall_velocity": chair.fall_velocity,
			"fall_spin": chair.fall_spin,
			"knockout_velocity": chair.knockout_velocity,
			"knockout_spin": chair.knockout_spin,
		}
	)


func _on_decided(winner: int) -> void:
	_send_event({"type": &"decided", "round": round.round_id, "winner": winner})


func _on_stage_event(payload: Variant, number: int) -> void:
	_send_event({"type": &"stage", "round": number, "data": payload})


func _on_message(kind: StringName, payload: Variant, from_peer: int) -> void:
	if _ended:
		return
	if net.is_host():
		if kind == &"fast_forward" and payload is Dictionary:
			if (
				not is_instance_valid(round)
				or payload.get("round") != round.round_id
				or not payload.get("held") is bool
				or _seat_of(from_peer) < 0
			):
				return
			if payload.held and round._can_fast_forward():
				_fast_forward_peers[from_peer] = true
			else:
				_fast_forward_peers.erase(from_peer)
			round.set_network_fast_forward(not _fast_forward_peers.is_empty())
		elif kind == &"input" and (payload is float or payload is int):
			var seat := _seat_of(from_peer)
			if _remote_turns.has(seat):
				_remote_turns[seat] = clampf(float(payload), -1.0, 1.0)
		return
	if not payload is Dictionary:
		return
	match kind:
		&"round":
			_on_round_message(payload)
		&"snapshot":
			if is_instance_valid(round) and payload.get("r") == round.round_id:
				round.apply_net_snapshot(payload)
		&"event":
			_on_event(payload)


func _on_round_message(payload: Dictionary) -> void:
	var definition: StageDefinition = _stages_by_id.get(StringName(str(payload.get("stage"))))
	var roster: Array = payload.get("roster", [])
	if definition == null or roster.size() != state.participants.size():
		push_warning("Ignoring an unknown online round: %s" % payload.get("stage"))
		return
	var wins := PackedInt32Array()
	for entry: Variant in roster:
		wins.append(int(entry.get("wins", 0)) if entry is Dictionary else 0)
	state.apply_wins(wins, -1)
	state.round_number = int(payload.get("round", state.round_number + 1))
	_build_round(definition, state.round_number, true)


func _on_event(payload: Dictionary) -> void:
	var type: StringName = StringName(str(payload.get("type", "")))
	if type == &"finished":
		_finish_online()
		return
	if not is_instance_valid(round) or payload.get("round") != round.round_id:
		return
	match type:
		&"stage":
			round.stage.apply_net_event(payload.get("data"))
		&"eliminated":
			round.apply_net_elimination(payload)
		&"decided":
			round.apply_net_decision()
		&"results":
			round.apply_net_finish()
			state.apply_wins(
				payload.get("wins", PackedInt32Array()), payload.get("match_winner", -1)
			)
			results_ready.emit(
				state.participants.duplicate(true),
				payload.get("winner", -1),
				state.wins_needed,
				state.winner_id != -1,
				state.round_number
			)


func _seat_of(peer: int) -> int:
	for participant in state.participants:
		if participant.peer == peer and peer != 0:
			return participant.id
	return -1


func _on_peer_left(peer: int) -> void:
	if _ended or not net.is_host():
		return
	var seat := _seat_of(peer)
	if seat == -1:
		return
	# The chair stays; an AI pilot takes the seat for the rest of the match.
	state.participants[seat]["peer"] = 0
	_remote_turns.erase(seat)
	_fast_forward_peers.erase(peer)
	if is_instance_valid(round):
		round.make_ai(seat)
		round.set_network_fast_forward(not _fast_forward_peers.is_empty())


func _on_session_closed(_reason: String) -> void:
	_ended = true
	_stop()


## Host Home or the final result: every peer returns to the lobby.
func _finish_online() -> void:
	if _ended:
		return
	_ended = true
	if net.is_host():
		_send_event({"type": &"finished"})
		if net.has_method(&"end_match"):
			net.call(&"end_match")
	_stop()
	online_finished.emit()


## Stop listening and free the round; scores stay readable.
func _stop() -> void:
	_generation += 1
	_transition_pending = false
	_free_round()
	_disconnect_net()


func _disconnect_net() -> void:
	if net == null:
		return
	for connection in [
		[net.message_received, _on_message],
		[net.peer_left, _on_peer_left],
		[net.session_closed, _on_session_closed]
	]:
		if connection[0].is_connected(connection[1]):
			connection[0].disconnect(connection[1])


func _exit_tree() -> void:
	# The round leaves with this node; only the session's signals outlive it.
	_ended = true
	_disconnect_net()
