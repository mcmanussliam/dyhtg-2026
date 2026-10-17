class_name MatchState
extends RefCounted
## Match bookkeeping, independent of scene lifetime and presentation.

# Share canonical customisation colours, with three distinct extras for ten seats.
const COLOURS: Array[Color] = [
	CharacterAppearance.PALETTE[0],
	CharacterAppearance.PALETTE[1],
	CharacterAppearance.PALETTE[2],
	CharacterAppearance.PALETTE[3],
	CharacterAppearance.PALETTE[4],
	CharacterAppearance.PALETTE[5],
	CharacterAppearance.PALETTE[6],
	Color("63c9d9"),
	Color("b2d16e"),
	Color("9ba7bd")
]

var participants: Array[Dictionary] = []
var wins_needed: int = 5
var round_number: int = 0
var winner_id: int = -1
var _recorded_round: int = 0


func configure(config: MatchConfig) -> void:
	# Bookkeeping validates its own values without instantiating map scenes.
	var appearance := (
		config.appearance.validated_copy()
		if config.appearance != null
		else CharacterAppearance.new()
	)
	var human_colour := appearance.resolved_colour()
	wins_needed = clampi(config.wins_needed, 1, 5)
	round_number = 0
	winner_id = -1
	_recorded_round = 0
	participants.clear()
	var ai_colours: Array[Color] = COLOURS.duplicate()
	ai_colours.remove_at(0)
	ai_colours.append(COLOURS[0])
	# Reserve the human colour before assigning the remaining seats without reuse.
	ai_colours.erase(human_colour)
	var default_skin := SkinCatalog.default_definition()
	for index in clampi(config.player_count, MatchConfig.MIN_PLAYERS, MatchConfig.MAX_PLAYERS):
		var skin := appearance.resolved_skin() if index == 0 else default_skin
		var colour := human_colour if index == 0 else ai_colours[index - 1]
		(
			participants
			. append(
				{
					"id": index,
					"skin": skin.duplicate(),
					"hat_id": appearance.hat_id if index == 0 else &"none",
					"name": "You" if index == 0 else "AI %d" % index,
					"colour": colour,
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
