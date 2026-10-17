class_name ScoreCharacter
extends TextureRect
## Reuses the gameplay model so score identity matches the character on stage.

var colour := Color.WHITE
var _model: ChairModel
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	RenderStyle.configure_composite(self)
	custom_minimum_size = Vector2(140, 132)
	var viewport := SubViewport.new()
	RenderStyle.configure_viewport(viewport, Vector2i(560, 528), true)
	add_child(viewport)
	texture = viewport.get_texture()
	_model = ChairModel.new()
	viewport.add_child(_model)
	_model.build(colour)
	_model.rotation.y = -0.15
	RenderStyle.setup_world(viewport, true, Color.BLACK, false)
	RenderStyle.orthographic_camera(viewport, 2.35, Vector3(0.3, 2.1, 5), Vector3(0, 0.8, 0))


func _process(delta: float) -> void:
	_time += delta
	_model.animate(delta, _time, 0, 0, Vector2.ZERO, Vector2.ZERO)
