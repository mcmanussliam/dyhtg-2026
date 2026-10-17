extends Node2D
## Original soft blob stand-ins. Parent-body rotation supplies the physical heading.

const INK := Color.BLACK

var _time: float = 0.0
var _seat_box: StyleBoxFlat
var _back_box: StyleBoxFlat
var _face_box: StyleBoxFlat


func _ready() -> void:
	var chair := get_parent() as Chair
	_seat_box = _box(chair.colour.darkened(0.43), 10)
	_back_box = _box(Color("34464b"), 8)
	_face_box = _box(chair.colour.lightened(0.42), 10)
	_face_box.set_border_width_all(1)
	_face_box.border_color = chair.colour.darkened(0.06)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var chair := get_parent() as Chair
	var speed := chair.linear_velocity.length() / chair.tuning.maximum_speed
	_draw_shadow(chair.aim_angle)
	_draw_chair(speed)
	_draw_blob(chair, speed)
	_draw_extinguisher(chair)
	if chair.spraying:
		_draw_foam(chair.spray_reach)
	draw_set_transform(Vector2.ZERO, -chair.aim_angle)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(-5, -43),
		str(chair.seat + 1),
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		15,
		Color("4b605c")
	)
	draw_set_transform(Vector2.ZERO)


func _draw_shadow(angle: float) -> void:
	draw_set_transform(Vector2(0, 12).rotated(-angle), -angle, Vector2(1.15, 0.72))
	draw_circle(Vector2.ZERO, 32, Color(0.12, 0.19, 0.2, 0.07))
	draw_circle(Vector2.ZERO, 26, Color(0.12, 0.19, 0.2, 0.12))
	draw_set_transform(Vector2.ZERO)


func _draw_chair(speed: float) -> void:
	for index in 5:
		var angle := float(index) * TAU / 5.0 + _time * speed * 0.8
		var foot := Vector2.from_angle(angle) * 29
		draw_line(Vector2.ZERO, foot, Color("60777b"), 5, true)
		draw_circle(foot + Vector2(1, 1), 5.5, Color("34464d"))
		draw_circle(foot, 3, Color("60777b"))
	draw_style_box(_seat_box, Rect2(-24, -24, 48, 48))
	draw_style_box(_back_box, Rect2(-30, -26, 13, 52))
	draw_line(Vector2(-25, -19), Vector2(-25, 19), Color("647b7e"), 2, true)


func _draw_blob(chair: Chair, speed: float) -> void:
	var wobble := sin(_time * 13.0) * speed * 0.035
	var squash := chair.impact * 0.10
	draw_set_transform(Vector2(-2, -4), 0.0, Vector2(1.0 + wobble + squash, 1.0 - wobble - squash))
	for layer in 8:
		var t := float(layer) / 7.0
		var tint := chair.colour.darkened(0.16).lerp(chair.colour.lightened(0.05), t)
		draw_circle(Vector2(-t * 3, -t * 4), 23.0 - t * 5, tint)
	draw_style_box(_face_box, Rect2(-1, -20, 22, 34))
	draw_circle(Vector2(10, -10), 2.6, INK)
	draw_circle(Vector2(10, 4), 2.6, INK)
	draw_set_transform(Vector2.ZERO)
	draw_circle(Vector2(15, 20), 8, chair.colour)
	draw_circle(Vector2(20, -18), 6, chair.colour)


func _draw_extinguisher(chair: Chair) -> void:
	var bob := 1.0 * sin(_time * 36.0) if chair.spraying else 0.0
	var tank := Vector2(24 + bob, 14)
	draw_line(tank - Vector2(8, 0), tank + Vector2(8, 0), Color("a8514b"), 16, true)
	draw_line(tank - Vector2(7, 2), tank + Vector2(7, 2), Color("e47c68"), 11, true)
	draw_line(tank - Vector2(5, 5), tank + Vector2(5, 5), Color("f1b099"), 2, true)
	draw_line(tank + Vector2(7, 0), Vector2(37, 1), Color("34464b"), 6, true)
	draw_line(Vector2(34, 1), Vector2(41, 1), Color("d7e0dc"), 6, true)
	draw_line(Vector2(26, 6), Vector2(32, 6), Color("34464b"), 3, true)


func _draw_foam(reach: float) -> void:
	if reach <= 2.0:
		return
	var start := minf(42.0, reach * 0.35)
	for index in 20:
		var t := fmod(_time * 2.7 + float(index) / 20.0, 1.0)
		var spread := sin(float(index) * 17.3) * t * 0.36
		var point := Vector2.from_angle(spread) * lerpf(start, reach, t)
		draw_circle(point, 3.0 + t * 7, Color(0.95, 0.98, 0.98, (1.0 - t) * 0.72))


func _box(tint: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.set_corner_radius_all(radius)
	return style
