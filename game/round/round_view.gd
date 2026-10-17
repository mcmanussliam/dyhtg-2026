class_name RoundView
extends Node3D
## Native main-viewport 3D scene. UI previews alone use isolated render textures.

const PIXELS_PER_UNIT := RenderStyle.PIXELS_PER_UNIT

var viewport: Viewport
var world: Node3D
var _stage: ArenaStage


func configure(stage: ArenaStage) -> void:
	_stage = stage


func _ready() -> void:
	viewport = get_viewport()
	viewport.msaa_3d = RenderStyle.msaa_mode
	viewport.mesh_lod_threshold = 1.0
	world = Node3D.new()
	world.name = "ArenaWorld"
	add_child(world)
	RenderStyle.setup_world(world)
	var focus := _stage.to_global(_stage.view_focus) / PIXELS_PER_UNIT
	var target := Vector3(focus.x, 0, focus.y)
	var camera := RenderStyle.orthographic_camera(
		world,
		_stage.view_width / PIXELS_PER_UNIT,
		(
			target
			+ (
				Vector3(
					0,
					RenderStyle.GAME_CAMERA_ELEVATION,
					sqrt(1.0 - pow(RenderStyle.GAME_CAMERA_ELEVATION, 2))
				)
				* 35.0
			)
		),
		target,
		true
	)
	camera.name = "ArenaCamera"
	camera.far = 100.0
	_stage.create_presentation(world, 1.0 / PIXELS_PER_UNIT)
	_stage.hide()
