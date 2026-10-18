class_name SpectatorSpeed
extends CanvasLayer
## Owns temporary spectator acceleration and restores engine timing on every exit.

signal fast_forward_requested(held: bool)

const MULTIPLIER := 3
## Pixels from the window's bottom edge to the top of the character faces, plus a gap.
const FACES_CLEARANCE := 132.0

var can_fast_forward: Callable
## Clients request speed changes; only the host owns engine timing.
var manage_timing := true
var network_fast_forward := false
var _requested := false
var _hint: PanelContainer
var _instruction: PanelContainer
var _armed := false
var _accelerated := false
var _focused := true
var _normal_time_scale := 1.0
var _normal_physics_rate := 60
var _normal_max_steps := 8


func _ready() -> void:
	_instruction = _panel("Hold the right arrow to fast forward")
	_hint = _panel("Fast forwarding %d×" % MULTIPLIER)
	for panel in [_instruction, _hint]:
		panel.hide()
		add_child(panel)
	# Both states share one box, sized to the longer line, so it never jumps when switching.
	var size := _instruction.get_combined_minimum_size().max(_hint.get_combined_minimum_size())
	for panel in [_instruction, _hint]:
		panel.custom_minimum_size = size
		# Centred along the bottom, just above the row of character faces.
		panel.anchor_left = 0.5
		panel.anchor_right = 0.5
		panel.anchor_top = 1.0
		panel.anchor_bottom = 1.0
		panel.offset_left = -size.x * 0.5
		panel.offset_right = size.x * 0.5
		panel.offset_top = -(FACES_CLEARANCE + size.y)
		panel.offset_bottom = -FACES_CLEARANCE


## One line of white text beside the fast-forward symbol, on translucent black.
func _panel(text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0, 0, 0, 0.6)
	background.content_margin_left = 12
	background.content_margin_right = 14
	background.content_margin_top = 6
	background.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", background)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	# Symbol and words sit in the middle of the box, whichever line is showing.
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	# The same double-triangle symbol in both states.
	var symbol := Control.new()
	symbol.custom_minimum_size = Vector2(26, 18)
	symbol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	symbol.draw.connect(_draw_icon.bind(symbol))
	row.add_child(symbol)
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return panel


func _process(_delta: float) -> void:
	refresh()


func refresh() -> void:
	var available: bool = _focused and can_fast_forward.is_valid() and can_fast_forward.call()
	var held := Input.is_action_pressed("spectator_fast_forward")
	if not available:
		_armed = false
	elif not held:
		# A steering key already held at elimination must be released first.
		_armed = true
	var requested := available and _armed and held
	if requested != _requested:
		_requested = requested
		fast_forward_requested.emit(requested)
	_set_accelerated(manage_timing and available and (requested or network_fast_forward))
	var active := _accelerated if manage_timing else available and network_fast_forward
	_hint.visible = active
	# After elimination, explain fast forwarding; the 3x badge replaces it while holding.
	_instruction.visible = available and not active


func set_network_fast_forward(held: bool) -> void:
	network_fast_forward = held
	refresh()


func is_accelerated() -> bool:
	return _accelerated


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
		refresh()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true


func _exit_tree() -> void:
	_set_accelerated(false)
