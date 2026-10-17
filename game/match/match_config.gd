class_name MatchConfig
extends Resource
## Reusable setup values. Runtime scores belong to MatchState, never this Resource.

const DEFAULT_STAGE_PATH := "res://game/stage/a_floor_in_the_crack.tres"

# Load at instance creation rather than preloading a scene into the class dependency graph.
@export var stages: Array[StageDefinition] = [
	load(DEFAULT_STAGE_PATH), load("res://game/stage/a_crack_in_the_floor.tres")
]

@export_range(1, 3, 1) var ai_count: int = 1
@export_range(1, 5, 1) var wins_needed: int = 5
@export var appearance: CharacterAppearance = CharacterAppearance.new()

var player_colour: Color:
	get:
		return appearance.resolved_colour()


func validated_copy() -> MatchConfig:
	var copy := MatchConfig.new()
	copy.ai_count = clampi(ai_count, 1, 3)
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


func stage_for_round(_number: int) -> StageDefinition:
	return stages.pick_random() if not stages.is_empty() else default_stage()


static func default_stage() -> StageDefinition:
	return load(DEFAULT_STAGE_PATH) as StageDefinition
