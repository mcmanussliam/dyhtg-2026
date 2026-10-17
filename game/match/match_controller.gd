class_name MatchController
extends Node
## Match owns round lifetime; MatchState alone awards wins.

signal results_ready(
	participants: Array[Dictionary],
	winner_id: int,
	target_wins: int,
	final_result: bool,
	round_number: int
)

const ROUND_SCENE = preload("res://game/round/round.tscn")
const DEFAULT_STAGE = preload("res://game/stage/a_floor_in_the_crack.tres")

var config: MatchConfig
var state := MatchState.new()
var round: RoundController
var _transition_pending: bool = false
var _generation: int = 0


func start(setup: MatchConfig) -> void:
	_generation += 1
	_transition_pending = false
	config = setup.validated_copy()
	state.configure(config)
	_replace_round()


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
	if is_instance_valid(round):
		remove_child(round)
		round.queue_free()
	round = ROUND_SCENE.instantiate() as RoundController
	round.configure(state.participants, DEFAULT_STAGE, state.begin_round(), state.wins_needed)
	round.completed.connect(_on_completed)
	add_child(round)
	_transition_pending = false


func _on_completed(id: int, winner: int) -> void:
	if not state.record_result(id, winner):
		return
	results_ready.emit(
		state.participants.duplicate(true),
		winner,
		state.wins_needed,
		state.winner_id != -1,
		state.round_number
	)
