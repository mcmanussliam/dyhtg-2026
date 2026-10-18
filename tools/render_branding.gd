extends SceneTree
## Render the app icon and boot splash from the real game models (native renderer only).
## Run with: godot --path . --script tools/render_branding.gd
## Outputs game/app/art/icon.png and game/app/art/splash.png; rerun after art changes.

const ICON_SIZE := 1024
const SPLASH_SIZE := Vector2i(1920, 1200)
const ICON_PATH := "res://game/app/art/icon.png"
const SPLASH_PATH := "res://game/app/art/splash.png"
const NAVY := Color("2e4055")
const UNITS := 1.0 / RenderStyle.PIXELS_PER_UNIT


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	RenderStyle.msaa_mode = Viewport.MSAA_8X
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://game/app/art"))
	var face := await _render_face()
	_icon(face).save_png(ICON_PATH)
	var splash := await _render_splash()
	splash.save_png(SPLASH_PATH)
	print("Saved %s and %s" % [ICON_PATH, SPLASH_PATH])
	quit()


func _render_face() -> Image:
	var viewport := _viewport(Vector2i(ICON_SIZE, ICON_SIZE), true)
	var model := ChairModel.new()
	viewport.add_child(model)
	model.build(CharacterAppearance.PALETTE[0])
	RenderStyle.setup_world(viewport, true, Color.BLACK, false)
	(viewport.get_node("StudioEnvironment") as WorldEnvironment).environment.ambient_light_energy = 0.55
	(viewport.get_node("KeyLight") as DirectionalLight3D).light_energy = 0.7
	# Head-and-shoulders framing, square on to the flush face panel and both eyes.
	RenderStyle.orthographic_camera(viewport, 0.8, Vector3(0, 1.55, 5), Vector3(0, 1.5, 0))
	return await _capture(viewport)


func _icon(face: Image) -> Image:
	# A rounded navy tile; the character rises from its lower edge.
	var icon := Image.create(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	var radius := ICON_SIZE * 0.22
	var inset := ICON_SIZE * 0.04
	var low := Vector2.ONE * (inset + radius)
	var high := Vector2.ONE * (ICON_SIZE - inset - radius)
	for y in ICON_SIZE:
		for x in ICON_SIZE:
			var point := Vector2(x + 0.5, y + 0.5)
			var distance := (point - point.clamp(low, high)).length() - radius
			var coverage := clampf(0.5 - distance, 0.0, 1.0)
			if coverage <= 0.0:
				continue
			# Soft top light keeps the flat navy from reading as a hole.
			var tint := NAVY.lightened(0.18 * (1.0 - y / float(ICON_SIZE)))
			tint.a = coverage
			icon.set_pixel(x, y, tint)
	var mask := icon.duplicate() as Image
	icon.blend_rect(face, Rect2i(Vector2i.ZERO, face.get_size()), Vector2i.ZERO)
	# Keep the character inside the rounded tile.
	for y in ICON_SIZE:
		for x in ICON_SIZE:
			var colour := icon.get_pixel(x, y)
			colour.a = minf(colour.a, mask.get_pixel(x, y).a)
			icon.set_pixel(x, y, colour)
	return icon


func _render_splash() -> Image:
	var viewport := _viewport(SPLASH_SIZE, false)
	var stage := (
		(load("res://game/stage/bull_office/bull_office.tscn") as PackedScene).instantiate()
		as OfficeStage
	)
	root.add_child(stage)
	stage.hide()
	var world := Node3D.new()
	viewport.add_child(world)
	RenderStyle.setup_world(world, false, Color("1c2733"))
	stage.create_presentation(world, UNITS)
	for node in world.get_children():
		if node is BullModel:
			node.hide()
	# A head-on chase down one diagonal line, from the bull at the saloon doors to the
	# lead player nearest the lens. Players spray at the bull, so their jets carry them away.
	var bull_point := Vector3(17.2, 0, -1.4)
	var line := Vector3(-0.42, 0, 1).normalized()
	var across := Vector3(line.z, 0, -line.x)
	var lead := bull_point + line * 9.5
	var bull := BullModel.new()
	world.add_child(bull)
	bull.build()
	bull.scale = Vector3.ONE * 1.4
	bull.position = bull_point
	bull.rotation.y = PI / 2 - atan2(line.z, line.x)
	bull.animate(0.0, 0.35, true, false, false)
	var drivers := Node2D.new()
	root.add_child(drivers)
	var eye := lead + across * 3.4 + line * 2.9 + Vector3.UP * 2.0
	# The pack fans out either side of the line so the bull stays in view between them.
	var pack := [
		[0.0, 0.0, 0],
		[2.4, -1.5, 3],
		[2.9, 2.6, 1],
		[4.9, -2.0, 4],
		[5.6, 3.4, 2],
	]
	for index in pack.size():
		var point: Vector3 = lead - line * pack[index][0] + across * pack[index][1]
		var toward_bull := Vector2(bull.position.x - point.x, bull.position.z - point.z)
		var toward_eye := Vector2(eye.x - point.x, eye.z - point.z)
		# Part-way from the bull towards the lens, so each face reads in three-quarters.
		var heading := lerp_angle(toward_bull.angle(), toward_eye.angle(), 0.62)
		_flee(world, drivers, point, heading, index, CharacterAppearance.PALETTE[pack[index][2]])
	# Raise the rear wall for this shot only, so it fills the frame behind the bull.
	var wall := ModelGeometry.material(Color("c8bf92"))
	ModelGeometry.box(world, Vector3(15, 6.3, -5.4), Vector3(32, 7.0, 0.5), wall)
	# Beside the pack, looking diagonally back down the line onto the charging bull.
	var camera := Camera3D.new()
	camera.fov = 34.0
	camera.far = 80.0
	world.add_child(camera)
	camera.fov = 42.0
	camera.position = eye
	camera.look_at(lead - line * 3.4 + Vector3.UP * 0.9)
	camera.rotate_object_local(Vector3.FORWARD, -0.06)
	camera.make_current()
	_title(viewport)
	var image := await _capture(viewport)
	stage.queue_free()
	drivers.queue_free()
	return image


func _flee(
	world: Node3D, drivers: Node2D, point: Vector3, heading: float, seat: int, colour: Color
) -> void:
	var rig := Node3D.new()
	rig.position = point
	world.add_child(rig)
	var model := ChairModel.new()
	rig.add_child(model)
	model.build(colour)
	model.rotation.y = PI / 2 - heading
	model.animate(0.016, 0.4 + seat, 0.9, 0.0, Vector2(-5, 0), Vector2(0, -1))
	# A frozen stand-in body supplies the spray's heading and strength.
	var chair := (load("res://game/chair/chair.tscn") as PackedScene).instantiate() as Chair
	chair.get_node("Visuals").free()
	chair.freeze = true
	chair.seat = seat
	chair.rotation = heading
	# Short, light jets keep the faces and the bull clear of foam.
	chair.jet_strength = 0.55
	chair.spray_reach = 120.0
	drivers.add_child(chair)
	var spray := SprayView.new()
	world.add_child(spray)
	spray.update_plume(chair, model.extinguisher.nozzle.global_position, 1.1 + seat * 0.3, point)


func _title(viewport: SubViewport) -> void:
	var layer := CanvasLayer.new()
	viewport.add_child(layer)
	var label := Label.new()
	label.text = "DILLY DALLYING"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 132)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color("1c2733"))
	label.add_theme_constant_override("outline_size", 28)
	# Across the plain upper wall, clear of the chase.
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	label.offset_top = 60
	layer.add_child(label)


func _viewport(size: Vector2i, transparent: bool) -> SubViewport:
	var viewport := SubViewport.new()
	RenderStyle.configure_viewport(viewport, size, transparent)
	root.add_child(viewport)
	return viewport


func _capture(viewport: SubViewport) -> Image:
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	viewport.queue_free()
	return image
