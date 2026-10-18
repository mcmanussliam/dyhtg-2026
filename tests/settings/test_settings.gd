extends RefCounted
## Persistence, validation and live application without touching the user's preferences.


func run(tree: SceneTree, check: Callable) -> void:
	var path := "user://settings_test_%d.cfg" % Time.get_ticks_usec()
	var settings := GameSettings.load_profile(path)
	check.call(
		settings.values == GameSettings.DEFAULTS, "Missing settings use crisp rendering defaults"
	)
	for key in GameSettings.COUNTS:
		for index in GameSettings.COUNTS[key]:
			settings.cycle(key)
		check.call(settings.values[key] == GameSettings.DEFAULTS[key], "Settings wrap (%s)" % key)
	settings.values.aa = 0
	settings.values.shadows = 0
	check.call(settings.save_profile(path) == OK, "Settings save atomically")
	var loaded := GameSettings.load_profile(path)
	check.call(loaded.values == settings.values, "Settings survive restart")
	var file := ProfileStore.load_file(path)
	file.set_value("settings", "aa", "bad")
	file.set_value("settings", "shadows", -5)
	file.set_value("settings", "fps", 999)
	file.set_value("settings", "fullscreen", true)
	ProfileStore.save_file(file, path)
	var repaired := GameSettings.load_profile(path)
	check.call(
		repaired.values == GameSettings.DEFAULTS,
		"Malformed and out-of-range settings fall back independently"
	)
	check.call(
		repaired.save_profile(path) == OK, "Updated profiles save only supported preferences"
	)
	var migrated := ProfileStore.load_file(path)
	check.call(
		migrated.get_section_keys("settings").size() == GameSettings.DEFAULTS.size(),
		"Obsolete preferences are ignored and removed on save"
	)
	var preview := SubViewport.new()
	tree.root.add_child(preview)
	var world := Node3D.new()
	preview.add_child(world)
	RenderStyle.setup_world(world)
	loaded.apply(tree.root)
	check.call(
		preview.msaa_3d == Viewport.MSAA_DISABLED and not world.get_node("KeyLight").shadow_enabled,
		"Graphics changes apply to existing previews"
	)
	var next_world := Node3D.new()
	preview.add_child(next_world)
	RenderStyle.setup_world(next_world)
	check.call(
		not next_world.get_node("KeyLight").shadow_enabled, "New worlds inherit shadow preferences"
	)
	var display := GameSettings.new()
	check.call(
		(
			display.value_label("display") == "Windowed"
			and display.value_label("resolution") == "1280 × 800"
			and display.value_label("vsync") == "On"
		),
		"Defaults are a 1280 × 800 window with V-Sync"
	)
	check.call(
		GameSettings.RESOLUTIONS.all(
			func(size: Vector2i) -> bool: return size.x * 10 == size.y * 16
		),
		"Every window size keeps the game's 16:10 layout"
	)
	var menu := SettingsMenu.new()
	menu.settings = display
	menu.apply_changes = false
	tree.root.add_child(menu)
	var resolution := SettingsMenu.KEYS.find("resolution")
	check.call(not menu._disabled_items.has(resolution), "Resolution is adjustable when windowed")
	menu._change(SettingsMenu.KEYS.find("display"))
	check.call(
		display.value_label("display") == "Fullscreen" and menu._disabled_items.has(resolution),
		"Fullscreen uses the native display, so Resolution is greyed out"
	)
	menu.queue_free()
	GameSettings.new().apply(tree.root)
	preview.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await tree.process_frame
