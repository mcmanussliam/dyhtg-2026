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
	"res://game/stage/hr_training/hr_training.tres"
]

# The available registry stays complete while this array holds the chosen map pool.
@export var stages: Array[StageDefinition] = available_stages()

@export_range(2, 10, 1) var player_count: int = MIN_PLAYERS
@export_range(1, 5, 1) var wins_needed: int = 5
@export var appearance: CharacterAppearance = CharacterAppearance.new()

var player_colour: Color:
	get:
		return appearance.resolved_colour()


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


## Independent draws allow consecutive repeats; the round number is not a rotation index.
func stage_for_round(_number: int) -> StageDefinition:
	return stages.pick_random() if not stages.is_empty() else default_stage()


static func default_stage() -> StageDefinition:
	return load(DEFAULT_STAGE_PATH) as StageDefinition


static func available_stages() -> Array[StageDefinition]:
	var definitions: Array[StageDefinition] = []
	for path in STAGE_PATHS:
		definitions.append(load(path) as StageDefinition)
	return definitions
