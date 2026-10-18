class_name MatchConfig
extends Resource
## Reusable setup values. Runtime scores belong to MatchState, never this Resource.

const DEFAULT_STAGE_PATH := "res://game/stage/a_floor_in_the_crack/a_floor_in_the_crack.tres"
const MIN_PLAYERS := 2
const MAX_PLAYERS := 10

const STAGE_PATHS := [
	DEFAULT_STAGE_PATH,
	"res://game/stage/a_crack_in_the_floor/a_crack_in_the_floor.tres",
	"res://game/stage/bull_office/bull_office.tres",
	"res://game/stage/hr_training/hr_training.tres",
	"res://game/stage/faulty_floors/faulty_floors.tres",
	"res://game/stage/under_construction/under_construction.tres",
	"res://game/stage/computer_bugs/computer_bugs.tres",
	"res://game/stage/after_hours/after_hours.tres"
]

# The available registry stays complete while this array holds the chosen map pool.
@export var stages: Array[StageDefinition] = available_stages()

@export_range(2, 10, 1) var player_count: int = MIN_PLAYERS
@export_range(1, 5, 1) var wins_needed: int = 5
@export var appearance: CharacterAppearance = CharacterAppearance.new()

var player_colour: Color:
	get:
		return appearance.resolved_colour()

var _bag: Array[StageDefinition] = []
var _bag_signature: Array = []
var _last_stage_id: StringName = &""
var _stage_random := RandomNumberGenerator.new()


func _init() -> void:
	_stage_random.randomize()


## Tests pin the shuffle order; real matches use an unpredictable one.
func seed_stage_order(value: int) -> void:
	_stage_random.seed = value
	_bag.clear()


func validated_copy() -> MatchConfig:
	var copy := MatchConfig.new()
	copy.player_count = clampi(player_count, MIN_PLAYERS, MAX_PLAYERS)
	copy.wins_needed = clampi(wins_needed, 1, 5)
	copy.appearance = (
		appearance.validated_copy() if appearance != null else CharacterAppearance.new()
	)
	copy.stages.clear()
	for definition in stages:
		if definition != null and definition.validation_errors().is_empty():
			copy.stages.append(definition.duplicate() as StageDefinition)
	if copy.stages.is_empty():
		copy.stages.append(default_stage())
	return copy


## Maps are dealt from a shuffled bag: every selected map appears exactly once, in random
## order, before any map repeats. When the bag empties it is reshuffled, and the new pass
## never opens with the map that just closed the previous one. The round number is not a
## rotation index.
func stage_for_round(_number: int) -> StageDefinition:
	var pool: Array[StageDefinition] = []
	for definition in stages:
		if definition != null:
			pool.append(definition)
	if pool.is_empty():
		return default_stage()
	# Changing the selected maps mid-match starts a fresh pass over the new pool.
	var signature: Array = pool.map(
		func(definition: StageDefinition) -> StringName: return definition.id
	)
	if signature != _bag_signature:
		_bag_signature = signature
		_bag.clear()
	if _bag.is_empty():
		_bag = pool.duplicate()
		# Fisher-Yates on the config's own generator, leaving the global stream untouched.
		for index in range(_bag.size() - 1, 0, -1):
			var other := _stage_random.randi_range(0, index)
			var held := _bag[index]
			_bag[index] = _bag[other]
			_bag[other] = held
		if _bag.size() > 1 and _bag[-1].id == _last_stage_id:
			var swap := _stage_random.randi_range(0, _bag.size() - 2)
			var displaced := _bag[swap]
			_bag[swap] = _bag[-1]
			_bag[-1] = displaced
	var pick: StageDefinition = _bag.pop_back()
	_last_stage_id = pick.id
	return pick


static func default_stage() -> StageDefinition:
	return load(DEFAULT_STAGE_PATH) as StageDefinition


static func available_stages() -> Array[StageDefinition]:
	var definitions: Array[StageDefinition] = []
	for path in STAGE_PATHS:
		definitions.append(load(path) as StageDefinition)
	return definitions
