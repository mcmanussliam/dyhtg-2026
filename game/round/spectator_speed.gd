class_name SpectatorSpeed
extends CanvasLayer
## Owns temporary spectator acceleration and restores engine timing on every exit.

const MULTIPLIER := 3

var can_fast_forward: Callable
var _hint: Label
var _armed := false
var _accelerated := false
var _focused := true
var _normal_time_scale := 1.0
var _normal_physics_rate := 60
var _normal_max_steps := 8


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_hint.offset_left = 32
	_hint.offset_right = -32
	_hint.offset_top = 32
	_hint.offset_bottom = 64
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_color", Color.WHITE)
	_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_hint.visible = available
	_hint.text = "Fast-forward 3×" if _accelerated else "Hold → to fast-forward"


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
