class_name GameHud
extends Control
## Small transparent readouts. No room frame, gauges, menu or round UI.

const INK := Color("35434a")
const MUTED := Color("637771")

var chairs: Array[Chair] = []
var labels := PackedStringArray()
var paused: bool = false
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	_text("PLEASE REMAIN SEATED", Vector2(36, 39), 19, INK)
	_text(
		"PAUSED · Esc to resume" if paused else "PHYSICS TEST · AUTO SPRAY",
		Vector2(913, 39),
		14,
		MUTED
	)
	for index in chairs.size():
		var left := 36.0 + index * 250.0
		draw_circle(Vector2(left + 5, 72), 5, chairs[index].colour.darkened(0.22))
		var device := labels[index] if index < labels.size() else ""
		_text("P%d · %s" % [index + 1, device], Vector2(left + 19, 77), 13, MUTED)
	_text("← / → or A / D turn · Extinguisher always on", Vector2(36, 772), 16, INK)
	_text("P2: J / L   F2 AI / P2   R reset   Esc pause", Vector2(883, 772), 13, MUTED)


func _text(value: String, point: Vector2, font_size: int, tint: Color) -> void:
	draw_string(_font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)
