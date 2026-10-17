class_name ScoreCharacter
extends TextureRect
## Reuses the gameplay model so score identity matches the character on stage.

var hat_id: StringName = &"none"
var skin: CharacterSkin
var colour := Color.WHITE
var animated := true
var close_up := false
var display_size := Vector2(140, 132)
var _model: ChairModel
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	RenderStyle.configure_composite(self)
	custom_minimum_size = display_size
	var viewport := SubViewport.new()
	RenderStyle.configure_viewport(viewport, Vector2i(display_size * 4), true)
	if not animated:
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		set_process(false)
	add_child(viewport)
	texture = viewport.get_texture()
	_model = ChairModel.new()
	viewport.add_child(_model)
	_model.build(colour, skin, hat_id)
	_model.rotation.y = -0.15
	RenderStyle.setup_world(viewport, true, Color.BLACK, false)
	# Fixed framing per view: cosmetics never resize the face or shift its position.
	if close_up:
		_model.rotation.y = 0
		# Neutral, softer portrait lighting keeps the palette readable at HUD size.
		var environment := viewport.get_node("StudioEnvironment") as WorldEnvironment
		environment.environment.ambient_light_energy = 0.5
		(viewport.get_node("KeyLight") as DirectionalLight3D).light_energy = 0.6
		(viewport.get_node("FillLight") as DirectionalLight3D).light_energy = 0.08
		RenderStyle.orthographic_camera(viewport, 0.9, Vector3(0, 1.58, 5), Vector3(0, 1.43, 0))
	else:
		RenderStyle.orthographic_camera(viewport, 2.85, Vector3(0.3, 2.3, 5), Vector3(0, 1.0, 0))


func _process(delta: float) -> void:
	_time += delta
	_model.animate(delta, _time, 0, 0, Vector2.ZERO, Vector2.ZERO)
