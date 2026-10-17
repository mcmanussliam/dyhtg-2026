class_name RenderStyle
extends RefCounted
## Shared native rendering conventions: metres in 3D, 43 authoring pixels per metre in 2D.
## Framing/content stay with each view; lighting and quality settings stay consistent.

const PIXELS_PER_UNIT := 43.0
const GAME_CAMERA_ELEVATION := 0.60
const AMBIENT_ENERGY := 0.35
const KEY_ENERGY := 0.9
const FILL_ENERGY := 0.18

static var msaa_mode: Viewport.MSAA = Viewport.MSAA_4X
static var shadow_quality := 2


static func configure_viewport(
	viewport: Viewport, render_size: Vector2i, transparent: bool
) -> void:
	if viewport is SubViewport:
		viewport.size = render_size
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = transparent
	viewport.own_world_3d = true
	viewport.msaa_3d = msaa_mode
	viewport.mesh_lod_threshold = 1.0


static func setup_world(
	parent: Node, transparent: bool = false, background: Color = Color.BLACK, shadows: bool = true
) -> void:
	var environment := WorldEnvironment.new()
	environment.name = "StudioEnvironment"
	var settings := Environment.new()
	settings.background_mode = Environment.BG_CLEAR_COLOR if transparent else Environment.BG_COLOR
	settings.background_color = background
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = AMBIENT_ENERGY
	environment.environment = settings
	parent.add_child(environment)
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.rotation_degrees = Vector3(-45, -35, 0)
	key.light_color = Color.WHITE
	key.light_energy = KEY_ENERGY
	key.set_meta("shadows_allowed", shadows)
	key.shadow_enabled = shadows and shadow_quality != 0
	key.shadow_bias = 0.2
	key.shadow_normal_bias = 2.0
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 70.0
	parent.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.rotation_degrees = Vector3(25, 140, 0)
	fill.light_color = Color.WHITE
	fill.light_energy = FILL_ENERGY
	parent.add_child(fill)


static func configure_composite(item: CanvasItem) -> void:
	item.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var composite := CanvasItemMaterial.new()
	composite.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	item.material = composite


static func orthographic_camera(
	parent: Node, view_size: float, eye: Vector3, target: Vector3, keep_width: bool = false
) -> Camera3D:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_WIDTH if keep_width else Camera3D.KEEP_HEIGHT
	camera.size = view_size
	camera.far = 100.0
	camera.position = eye
	parent.add_child(camera)
	camera.look_at(target)
	return camera
