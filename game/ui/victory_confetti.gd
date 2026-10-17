class_name VictoryConfetti
extends Control
## Deterministic one-shot celebration, confined to presentation.

var _time := 0.0
var _pieces: Array[Vector4] = []
var _colours := [Color("efbc61"), Color("e4825e"), Color("9bd2c6"), Color("f4eee0")]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var random := RandomNumberGenerator.new()
	random.seed = 73193
	for index in 125:
		_pieces.append(
			Vector4(
				random.randf(),
				random.randf_range(-650, -10),
				random.randf_range(95, 170),
				random.randf_range(0, TAU)
			)
		)


func _process(delta: float) -> void:
	_time += delta
	if _time > 11:
		set_process(false)
	queue_redraw()


func _draw() -> void:
	for index in _pieces.size():
		var piece := _pieces[index]
		var y := piece.y + _time * piece.z
		if y > size.y + 20:
			continue
		var x := piece.x * size.x + sin(_time * 1.7 + piece.w) * 32
		draw_set_transform(Vector2(x, y), piece.w + _time, Vector2(1, cos(_time * 3 + piece.w)))
		draw_rect(Rect2(-4, -7, 8, 14), _colours[index % _colours.size()])
	draw_set_transform(Vector2.ZERO)
