class_name MatchConfig
extends Resource
## Reusable setup values. Runtime scores belong to MatchState, never this Resource.

@export_range(1, 3, 1) var ai_count: int = 1
@export_range(1, 5, 1) var wins_needed: int = 5


func validated_copy() -> MatchConfig:
	var copy := MatchConfig.new()
	copy.ai_count = clampi(ai_count, 1, 3)
	copy.wins_needed = clampi(wins_needed, 1, 5)
	return copy
