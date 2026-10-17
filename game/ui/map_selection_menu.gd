class_name MapSelectionMenu
extends TwoKeyMenu
## Testing map pool, held in the setup config rather than persisted to a profile.
## Every entry remains activatable, including unchecked maps and the first Back row.

signal back_requested

var config: MatchConfig
var _definitions: Array[StageDefinition] = []


func _ready() -> void:
	_definitions = MatchConfig.available_stages()
	super._ready()
	var labels := PackedStringArray(["Back"])
	for definition in _definitions:
		labels.append(definition.display_name)
	set_items(labels)
	activated.connect(_toggle)


func _is_selected(id: StringName) -> bool:
	for definition in config.stages:
		if definition.id == id:
			return true
	return false


func _toggle(index: int) -> void:
	if index == 0:
		back_requested.emit()
		return
	var definition := _definitions[index - 1]
	for selected in config.stages.size():
		if config.stages[selected].id == definition.id:
			config.stages.remove_at(selected)
			_refresh()
			return
	config.stages.append(definition)
	_refresh()


func _refresh() -> void:
	super._refresh()
	for index in range(1, _rows.size()):
		var selected := _is_selected(_definitions[index - 1].id)
		_rows[index].add_theme_color_override(
			"font_color", Color.WHITE if selected else Color(0.45, 0.45, 0.45)
		)
		if selected:
			_rows[index].text += "  ✓"
