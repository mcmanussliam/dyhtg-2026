class_name SpectatorSpeed
extends CanvasLayer
## Owns temporary spectator acceleration and restores engine timing on every exit.

const MULTIPLIER := 3

var can_fast_forward: Callable
var _hint: PanelContainer
var _armed := false
var _accelerated := false
var _focused := true
var _normal_time_scale := 1.0
var _normal_physics_rate := 60
var _normal_max_steps := 8


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hint = PanelContainer.new()
	_hint.position = Vector2(48, 40)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color.BLACK
	background.content_margin_left = 16
	background.content_margin_right = 16
	background.content_margin_top = 8
	background.content_margin_bottom = 8
	_hint.add_theme_stylebox_override("panel", background)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(36, 26)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(_draw_icon.bind(icon))
	row.add_child(icon)
	var label := Label.new()
	label.text = "%d×" % MULTIPLIER
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	_hint.hide()
	add_child(_hint)


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	var available: bool = (
		_focused
		and not get_tree().paused
		and can_fast_forward.is_valid()
		and can_fast_forward.call()
	)
	var held := Input.is_action_pressed("spectator_fast_forward")
	if not available:
		_armed = false
	elif not held:
		# A steering key already held at elimination must be released first.
		_armed = true
	_set_accelerated(available and _armed and held)
	_hint.visible = _accelerated


func _draw_icon(icon: Control) -> void:
	# Two right-pointing triangles: the standard fast-forward symbol.
	var size := icon.size
	var half := size.x * 0.5
	for x in [0.0, half]:
		icon.draw_colored_polygon(
			PackedVector2Array(
				[Vector2(x, 0), Vector2(x + half, size.y * 0.5), Vector2(x, size.y)]
			),
			Color.WHITE
		)


func _set_accelerated(enabled: bool) -> void:
	if enabled == _accelerated:
		return
	_accelerated = enabled
	if enabled:
		_normal_time_scale = Engine.time_scale
		_normal_physics_rate = Engine.physics_ticks_per_second
		_normal_max_steps = Engine.max_physics_steps_per_frame
		# Keep each simulated physics step unchanged rather than increasing delta.
		Engine.physics_ticks_per_second = _normal_physics_rate * MULTIPLIER
		Engine.max_physics_steps_per_frame = _normal_max_steps * MULTIPLIER
		Engine.time_scale = _normal_time_scale * MULTIPLIER
	else:
		Engine.time_scale = _normal_time_scale
		Engine.physics_ticks_per_second = _normal_physics_rate
		Engine.max_physics_steps_per_frame = _normal_max_steps


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_armed = false
		_set_accelerated(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true


func _exit_tree() -> void:
	_set_accelerated(false)
