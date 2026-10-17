class_name StageDefinition
extends Resource
## Immutable authored map identity. Scores and round timers never live here.

@export var id: StringName = &""
@export var display_name: String = ""
@export var scene: PackedScene


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if id == &"":
		errors.append("Stage needs a stable ID.")
	if display_name.strip_edges().is_empty():
		errors.append("Stage needs a display name.")
	if scene == null:
		errors.append("Stage needs an ArenaStage scene.")
	return errors
