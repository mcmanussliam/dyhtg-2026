class_name GameSettings
extends Resource
## Validated local preferences, independent of match rules and appearance.

const MSAA_MODES := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X]
const DEFAULTS := {"aa": 2, "shadows": 2}
const COUNTS := {"aa": 4, "shadows": 3}

var values: Dictionary = DEFAULTS.duplicate()


func cycle(key: String) -> void:
	if COUNTS.has(key):
		values[key] = (int(values.get(key, DEFAULTS[key])) + 1) % int(COUNTS[key])


func value_label(key: String) -> String:
	var labels := {
		"aa": ["Off", "2×", "4×", "8×"],
		"shadows": ["Off", "Low", "High"],
	}
	return labels[key][values[key]] if labels.has(key) else ""


static func load_profile(path: String) -> GameSettings:
	var result := GameSettings.new()
	var file := ProfileStore.load_file(path)
	for key in DEFAULTS:
		var saved: Variant = file.get_value("settings", key, DEFAULTS[key])
		if saved is int and saved >= 0 and saved < COUNTS[key]:
			result.values[key] = saved
	return result


func save_profile(path: String) -> Error:
	var file := ConfigFile.new()
	for key in DEFAULTS:
		var value: Variant = values.get(key, DEFAULTS[key])
		if not (value is int and value >= 0 and value < COUNTS[key]):
			value = DEFAULTS[key]
		file.set_value("settings", key, value)
	return ProfileStore.save_file(file, path)


func apply(root: Node) -> void:
	RenderStyle.msaa_mode = MSAA_MODES[values.aa]
	RenderStyle.shadow_quality = values.shadows
	RenderingServer.directional_soft_shadow_filter_set_quality(
		(
			RenderingServer.SHADOW_QUALITY_SOFT_HIGH
			if values.shadows == 2
			else RenderingServer.SHADOW_QUALITY_SOFT_LOW
		)
	)
	_apply_rendering(root)


func _apply_rendering(node: Node) -> void:
	if node is Viewport:
		node.msaa_3d = RenderStyle.msaa_mode
	if node is DirectionalLight3D and node.name == "KeyLight":
		node.shadow_enabled = values.shadows != 0 and node.get_meta("shadows_allowed", true)
	for child in node.get_children():
		_apply_rendering(child)
