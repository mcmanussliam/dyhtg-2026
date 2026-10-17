class_name HomeBackdrop
extends Control
## A self-contained office diorama with the same original character as gameplay.

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
	RenderStyle.setup_world(room, false, Color("182735"))
	RenderStyle.orthographic_camera(room, 7.8, Vector3(6, 5, 9), Vector3(-1.4, 1.1, 0))
	var shadow := ModelGeometry.material(Color("485954"))
	ModelGeometry.ellipsoid(room, Vector3(1.2, 0.008, 0.5), Vector3(1.0, 0.008, 0.65), shadow)
	var carpet := ModelGeometry.material(Color("60726f"))
	var wall := ModelGeometry.material(Color("d6d2bf"))
	var dark := ModelGeometry.material(Color("273b48"))
	_box(room, Vector3(0, -0.16, 0), Vector3(14, 0.3, 10), carpet)
	_box(room, Vector3(0, 1.9, -4), Vector3(14, 4, 0.15), wall)
	_box(room, Vector3(0, 0.12, -3.88), Vector3(14, 0.22, 0.12), dark)
	# The same authored furniture assets are used by playable office stages.
	var desk := preload("res://game/props/desk_visual.tscn").instantiate() as Node3D
	desk.position = Vector3(1.8, 0, -2.6)
	room.add_child(desk)
	_model = ChairModel.new()
	room.add_child(_model)
	_model.position = Vector3(1.2, 0, 0.5)
	_model.rotation.y = 0.4
	_model.scale = Vector3.ONE * 1.6
	_model.build(MatchState.COLOURS[0])


func _process(delta: float) -> void:
	_clock += delta
	if is_instance_valid(_model):
		_model.animate(delta, _clock, 0, 0, Vector2.ZERO, Vector2.ZERO)
		_model.rotation.y = 0.4 + sin(_clock * 0.27) * 0.08


func _box(parent: Node3D, centre: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	ModelGeometry.instance(parent, mesh, centre, material)
