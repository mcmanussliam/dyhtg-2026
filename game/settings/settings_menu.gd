class_name SettingsMenu
extends TwoKeyMenu
## Same two-key option/value presentation as character customisation.

signal back_requested

const KEYS := ["aa", "shadows"]
const LABELS := ["Anti-aliasing", "Shadow quality", "Back"]

var settings: GameSettings
var profile_path := ""
var apply_changes := true


func _ready() -> void:
	super._ready()
	_refresh_options()
	activated.connect(_change)


func _refresh_options() -> void:
	var option_values := PackedStringArray()
	for key in KEYS:
		option_values.append(settings.value_label(key))
	option_values.append("")
	set_items(PackedStringArray(LABELS), option_values)


func _change(index: int) -> void:
	if index == KEYS.size():
		back_requested.emit()
		return
	settings.cycle(KEYS[index])
	if apply_changes:
		settings.apply(get_tree().root)
	_refresh_options()
	if not profile_path.is_empty():
		var error := settings.save_profile(profile_path)
		if error != OK:
			push_warning("Could not save settings: %s" % error_string(error))
