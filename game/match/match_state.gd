class_name MatchState
extends RefCounted
## Match bookkeeping, independent of scene lifetime and presentation.

const COLOURS: Array[Color] = [Color("f4d782"), Color("72d9ae"), Color("f498b0"), Color("94b9f4")]

var participants: Array[Dictionary] = []
var wins_needed: int = 5
var round_number: int = 0
var winner_id: int = -1
var _recorded_round: int = 0


func configure(config: MatchConfig) -> void:
	var setup := config.validated_copy()
	wins_needed = setup.wins_needed
	round_number = 0
	winner_id = -1
	_recorded_round = 0
	participants.clear()
	for index in setup.ai_count + 1:
		(
			participants
			. append(
				{
					"id": index,
					"name": "You" if index == 0 else "AI %d" % index,
					"colour": COLOURS[index],
					"wins": 0,
				}
			)
		)


func begin_round() -> int:
	if (
		winner_id == -1
		and not participants.is_empty()
		and (round_number == 0 or _recorded_round == round_number)
	):
		round_number += 1
	return round_number


func record_result(round_id: int, round_winner: int) -> bool:
	if (
		winner_id != -1
		or round_id <= 0
		or round_id != round_number
		or _recorded_round == round_id
		or round_winner < -1
		or round_winner >= participants.size()
	):
		return false
	_recorded_round = round_id
	if round_winner != -1:
		participants[round_winner]["wins"] += 1
		if participants[round_winner]["wins"] >= wins_needed:
			winner_id = round_winner
	return true
