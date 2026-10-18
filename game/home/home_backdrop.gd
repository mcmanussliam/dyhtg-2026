class_name HomeBackdrop
extends Control
## Full office interior behind the two-key menus, using the gameplay furniture.

const CABINET := preload("res://game/props/cabinet/cabinet_visual.tscn")
const PLANT := preload("res://game/props/plant/plant_visual.tscn")
const PREVIEW_CAMERA_SIZE := 5.3
const PREVIEW_TARGET := Vector3(-0.35, 1.95, 0.8)
const PREVIEW_HEADING := 0.08

var hat_id: StringName = &"none"
var skin: CharacterSkin
var character_colour := MatchState.COLOURS[0]
var _model: ChairModel
var _clock := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var display := TextureRect.new()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_SCALE
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	RenderStyle.configure_composite(display)
	add_child(display)
	var viewport := SubViewport.new()
	RenderStyle.configure_viewport(viewport, Vector2i(2560, 1600), false)
	add_child(viewport)
	display.texture = viewport.get_texture()
	var room := Node3D.new()
	viewport.add_child(room)
	RenderStyle.setup_world(room, false, Color("2e4055"))
	# Match the office palette, with quieter lighting behind the white options.
	var environment := room.get_node("StudioEnvironment") as WorldEnvironment
	environment.environment.ambient_light_energy = 0.28
	var key := room.get_node("KeyLight") as DirectionalLight3D
	key.light_energy = 0.48
	# Fit the shadow map to this close preview instead of the distant arena camera.
	key.directional_shadow_max_distance = 22.0
	key.shadow_bias = 0.2
	key.shadow_normal_bias = 2.0
	(room.get_node("FillLight") as DirectionalLight3D).light_energy = 0.12
	# Keep the full character/chair readable from near eye level for future customisation.
	var camera := RenderStyle.orthographic_camera(
		room, PREVIEW_CAMERA_SIZE, PREVIEW_TARGET + Vector3(0, 2.9, 9), PREVIEW_TARGET
	)
	camera.far = 24.0
	_build_office(room)
	_build_character(room)
	var shadow_material := ShaderMaterial.new()
	shadow_material.shader = preload("res://game/chair/art/contact_shadow.gdshader")
	var shadow_mesh := PlaneMesh.new()
	shadow_mesh.size = Vector2(2.4, 1.95)
	var shadow := ModelGeometry.instance(room, shadow_mesh, Vector3(1, 0.012, 1), shadow_material)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func set_colour(colour: Color) -> void:
	character_colour = colour
	if is_instance_valid(_model):
		var room := _model.get_parent() as Node3D
		_model.free()
		_build_character(room)


func set_hat(id: StringName) -> void:
	hat_id = id
	set_colour(character_colour)


func set_skin(definition: CharacterSkin) -> void:
	skin = definition
	set_colour(character_colour)


func _build_character(room: Node3D) -> void:
	_model = ChairModel.new()
	room.add_child(_model)
	_model.position = Vector3(1.0, 0, 1.0)
	_model.rotation.y = PREVIEW_HEADING
	_model.scale = Vector3.ONE * 1.5
	_model.build(character_colour, skin, hat_id)


func _build_office(parent: Node3D) -> void:
	var room := Node3D.new()
	room.name = "OfficeInterior"
	room.position.z = -1.7
	parent.add_child(room)
	# Continuous surfaces fill the camera view; room edges never expose a void.
	var navy := ModelGeometry.material(Color("2e4055"), 0, 0.95)
	var wall := ModelGeometry.material(Color("c8bf92"), 0, 0.95)
	var trim := ModelGeometry.material(Color("293946"), 0, 0.9)
	ModelGeometry.box(room, Vector3(0, -0.10, 4), Vector3(40, 0.20, 40), navy)
	ModelGeometry.box(room, Vector3(0, 4, -3.5), Vector3(40, 8, 0.16), wall)
	ModelGeometry.box(room, Vector3(11.5, 4, 6.5), Vector3(0.16, 8, 20), wall)
	ModelGeometry.box(room, Vector3(0, 0.12, -3.39), Vector3(40, 0.24, 0.08), trim)
	ModelGeometry.box(room, Vector3(11.39, 0.12, 6.5), Vector3(0.08, 0.24, 20), trim)
	# A simple office door gives the quieter left side a purpose without signage.
	var door := ModelGeometry.material(Color("43565f"), 0, 0.9)
	ModelGeometry.box(room, Vector3(-3.65, 1.35, -3.37), Vector3(1.7, 2.7, 0.12), trim)
	ModelGeometry.box(room, Vector3(-3.65, 1.30, -3.28), Vector3(1.52, 2.56, 0.06), door)
	var handle := ModelGeometry.material(Color("879696"), 0.45, 0.6)
	ModelGeometry.capsule(
		room, Vector3(-3.17, 1.3, -3.20), Vector3(-2.95, 1.3, -3.20), 0.035, handle
	)
	_build_window(room)
	_build_details(room)
	var carpet := PlaneMesh.new()
	carpet.size = Vector2(3.0, 3.3)
	var rug := ModelGeometry.instance(
		room, carpet, Vector3(2.6, 0.004, 0.1), ModelGeometry.material(Color("637672"), 0, 1)
	)
	rug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var desk := _furniture(
		room, preload("res://game/props/desk/desk_visual.tscn"), Vector3(-0.5, 0, -2.35)
	)
	OfficeAccessories.desk(desk, Color("b2745f"))
	StaticModelBatcher.batch(desk)
	_furniture(
		room, preload("res://game/props/bookshelf/bookshelf_visual.tscn"), Vector3(3.25, 0, -3.05)
	)
	var cabinet := _furniture(room, CABINET, Vector3(1.9, 0, -2.98))
	OfficeAccessories.archive_boxes(cabinet, 1.25)
	StaticModelBatcher.batch(cabinet)
	var sofa := _furniture(
		room, preload("res://game/props/sofa/sofa_visual.tscn"), Vector3(2.9, 0, 0.1)
	)
	sofa.rotation.y = -PI * 0.5
	var table := _furniture(
		room,
		preload("res://game/props/coffee_table/coffee_table_visual.tscn"),
		Vector3(1.65, 0, 0.1)
	)
	table.rotation.y = -PI * 0.5
	# Keep the entrance clear; storage forms one rear-wall bank beside the lounge.
	_furniture(room, PLANT, Vector3(-2.25, 0, -2.55))
	var task_chair := _furniture(
		room, preload("res://game/props/task_chair/task_chair_visual.tscn"), Vector3(-0.5, 0, -1.35)
	)
	task_chair.rotation.y = PI


func _build_window(room: Node3D) -> void:
	var frame := ModelGeometry.material(Color("e2dfc9"), 0, 0.85)
	var recess := ModelGeometry.material(Color("485e66"), 0, 0.9)
	var glass := ModelGeometry.material(Color("87abb8"), 0.05, 0.55)
	ModelGeometry.box(room, Vector3(-0.1, 2.1, -3.36), Vector3(4.26, 1.40, 0.10), recess)
	ModelGeometry.box(room, Vector3(-0.1, 2.1, -3.28), Vector3(4.10, 1.24, 0.04), glass)
	for side in [-1.0, 1.0]:
		ModelGeometry.box(
			room, Vector3(-0.1 + side * 2.09, 2.1, -3.20), Vector3(0.08, 1.40, 0.10), frame
		)
		ModelGeometry.box(
			room, Vector3(-0.1, 2.1 + side * 0.66, -3.20), Vector3(4.26, 0.08, 0.10), frame
		)
	ModelGeometry.box(room, Vector3(-0.1, 2.1, -3.20), Vector3(0.055, 1.26, 0.10), frame)
	ModelGeometry.box(room, Vector3(-0.1, 2.30, -3.20), Vector3(4.10, 0.055, 0.10), frame)
	ModelGeometry.box(room, Vector3(-0.1, 1.39, -3.13), Vector3(4.40, 0.10, 0.35), frame)


func _build_details(room: Node3D) -> void:
	var dark := ModelGeometry.material(Color("43565f"), 0, 0.85)
	var cream := ModelGeometry.material(Color("e2dfc9"), 0, 0.9)
	# A quiet analogue clock, with geometry rather than lettering or textures.
	ModelGeometry.cylinder(room, Vector3(2.9, 2.3, -3.39), Vector3(2.9, 2.3, -3.28), 0.25, dark)
	ModelGeometry.cylinder(room, Vector3(2.9, 2.3, -3.27), Vector3(2.9, 2.3, -3.25), 0.22, cream)
	ModelGeometry.capsule(room, Vector3(2.9, 2.3, -3.23), Vector3(2.9, 2.46, -3.23), 0.012, dark)
	ModelGeometry.capsule(room, Vector3(2.9, 2.3, -3.23), Vector3(3.01, 2.25, -3.23), 0.014, dark)
	# A small bin sits beside the workstation, away from the character preview.
	ModelGeometry.cylinder(room, Vector3(-1.25, 0.02, -2.4), Vector3(-1.25, 0.48, -2.4), 0.22, dark)
	var opening := ModelGeometry.material(Color("263540"), 0, 1)
	ModelGeometry.cylinder(
		room, Vector3(-1.25, 0.481, -2.4), Vector3(-1.25, 0.485, -2.4), 0.19, opening
	)
	for x in [-1.5, 1.8]:
		ModelGeometry.box(room, Vector3(x, 0.38, -3.37), Vector3(0.24, 0.16, 0.04), cream)
		for side in [-1.0, 1.0]:
			ModelGeometry.box(
				room, Vector3(x + side * 0.045, 0.38, -3.34), Vector3(0.015, 0.045, 0.01), dark
			)


func _furniture(room: Node3D, scene: PackedScene, position_in_room: Vector3) -> Node3D:
	var model := scene.instantiate() as Node3D
	model.position = position_in_room
	room.add_child(model)
	StaticModelBatcher.batch(model)
	return model


func _process(delta: float) -> void:
	_clock += delta
	if is_instance_valid(_model):
		_model.animate(delta, _clock, 0, 0, Vector2.ZERO, Vector2.ZERO)
		_model.rotation.y = PREVIEW_HEADING + sin(_clock * 0.27) * 0.035
