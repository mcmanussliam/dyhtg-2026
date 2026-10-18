class_name LobbyRules
extends RefCounted
## Pure host-side lobby rules: validation, unique names, colours, setup and roster.

const DEFAULT_PLAYER_COUNT := 6
const DEFAULT_WINS := 3

static var _stage_ids: Array[StringName] = []


## Every registered stage ID, in registry order.
static func stage_ids() -> Array[StringName]:
	if _stage_ids.is_empty():
		for definition in MatchConfig.available_stages():
			if definition != null:
				_stage_ids.append(definition.id)
	return _stage_ids


static func valid_hat(value: Variant) -> StringName:
	var id := _id(value)
	return id if id in CharacterHats.IDS else CharacterAppearance.NONE


static func valid_top(value: Variant) -> StringName:
	var id := _id(value)
	for skin in SkinCatalog.definitions():
		if skin.id == id:
			return id
	return CharacterAppearance.NONE


static func valid_colour(value: Variant) -> StringName:
	var id := _id(value)
	return id if id in CharacterAppearance.COLOUR_IDS else CharacterAppearance.RANDOM


## The colour a colour ID asks for; transparent for Random.
static func preferred_colour(colour_id: StringName) -> Color:
	var index := CharacterAppearance.COLOUR_IDS.find(colour_id)
	return CharacterAppearance.PALETTE[index - 1] if index > 0 else Color.TRANSPARENT


## Sets each player's "colour". Earlier players keep their preference; clashes and
## Random take the next free colour in MatchState.COLOURS order.
static func resolve_colours(players: Array) -> void:
	var taken: Array[Color] = []
	var pending: Array[Dictionary] = []
	for player: Dictionary in players:
		var preferred := preferred_colour(player.colour_id)
		if preferred.a > 0.0 and preferred not in taken:
			player.colour = preferred
			taken.append(preferred)
		else:
			pending.append(player)
	for player in pending:
		var free := free_colours(taken)
		player.colour = free[0] if not free.is_empty() else MatchState.COLOURS[0]
		taken.append(player.colour)


## MatchState.COLOURS not in `taken`, in order.
static func free_colours(taken: Array) -> Array[Color]:
	var free: Array[Color] = []
	for colour in MatchState.COLOURS:
		if colour not in taken:
			free.append(colour)
	return free


## `name` cleaned, or "Studio Mac 2", "Studio Mac 3"... when another player has it.
static func unique_name(raw: String, players: Array) -> String:
	var base := MachineName.clean(raw)
	if base.is_empty():
		base = MachineName.FALLBACK
	var taken: Array[String] = []
	for player: Dictionary in players:
		taken.append(player.name)
	var name := base
	var number := 2
	while name in taken:
		var suffix := " %d" % number
		name = base.left(MachineName.MAX_LENGTH - suffix.length()).strip_edges() + suffix
		number += 1
	return name


## Lobby setup with every value clamped; unknown stages dropped, none selected → all.
static func clamp_setup(
	player_count: int, wins_needed: int, stages: Array, humans: int
) -> Dictionary:
	var known := stage_ids()
	var chosen: Array[StringName] = []
	for stage in stages:
		var id := _id(stage)
		if id in known and id not in chosen:
			chosen.append(id)
	if chosen.is_empty():
		chosen = known.duplicate()
	var fewest := maxi(humans, MatchConfig.MIN_PLAYERS)
	return {
		"player_count": clampi(player_count, fewest, MatchConfig.MAX_PLAYERS),
		"wins_needed": clampi(wins_needed, 1, 5),
		"stages": chosen,
	}


## One seat per player: humans in join order, then AI with the colours left over.
static func build_roster(players: Array, player_count: int) -> Array:
	var roster := []
	var taken := []
	for player: Dictionary in players:
		taken.append(player.colour)
		roster.append(
			_seat(
				roster.size(), player.peer, player.name, player.hat_id, player.top_id, player.colour
			)
		)
	var spare := free_colours(taken)
	var ai := 0
	while roster.size() < player_count:
		ai += 1
		var colour: Color = spare[ai - 1] if ai <= spare.size() else MatchState.COLOURS[0]
		roster.append(_seat(roster.size(), 0, "AI %d" % ai, &"none", &"none", colour))
	return roster


static func _seat(
	id: int, peer: int, name: String, hat_id: StringName, top_id: StringName, colour: Color
) -> Dictionary:
	return {
		"id": id,
		"peer": peer,
		"name": name,
		"hat_id": hat_id,
		"top_id": top_id,
		"colour": colour,
		"wins": 0,
	}


static func _id(value: Variant) -> StringName:
	return StringName(value) if value is String or value is StringName else &""
