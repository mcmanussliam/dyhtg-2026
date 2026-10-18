class_name GameSettings
extends Resource
## Validated local preferences, independent of match rules and appearance.
## Window size applies only when windowed; fullscreen always uses the native display.

const MSAA_MODES := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X]
## Window sizes share the game's 16:10 layout, so menus and HUD never letterbox.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 800),
	Vector2i(1440, 900),
	Vector2i(1680, 1050),
	Vector2i(1920, 1200),
	Vector2i(2560, 1600),
]
const DEFAULTS := {"display": 0, "resolution": 0, "vsync": 1, "aa": 2, "shadows": 2}
const COUNTS := {"display": 2, "resolution": 5, "vsync": 2, "aa": 4, "shadows": 3}

static var _applied_window := []

var values: Dictionary = DEFAULTS.duplicate()


func cycle(key: String) -> void:
	if COUNTS.has(key):
		values[key] = (int(values.get(key, DEFAULTS[key])) + 1) % int(COUNTS[key])


func value_label(key: String) -> String:
	if key == "resolution":
		var size: Vector2i = RESOLUTIONS[values.resolution]
		return "%d × %d" % [size.x, size.y]
	var labels := {
		"display": ["Windowed", "Fullscreen"],
		"vsync": ["Off", "On"],
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
	_apply_window()


func _apply_window() -> void:
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if values.vsync == 1 else DisplayServer.VSYNC_DISABLED
	)
	# Resize only on a real change, so other settings never move the window.
	var window := [values.display, values.resolution]
	if window == _applied_window:
		return
	_applied_window = window
	if values.display == 1:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var size := RESOLUTIONS[values.resolution].min(screen.size)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


func _apply_rendering(node: Node) -> void:
	if node is Viewport:
		node.msaa_3d = RenderStyle.msaa_mode
	if node is DirectionalLight3D and node.name == "KeyLight":
		node.shadow_enabled = values.shadows != 0 and node.get_meta("shadows_allowed", true)
	for child in node.get_children():
		_apply_rendering(child)
