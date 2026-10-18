class_name RoundController
extends Node2D
## Owns one stage and its bodies. Eliminations are committed as one physics batch.

signal completed(round_id: int, winner_id: int)

enum Phase { INTRO, LIVE, RESOLVING, FINISHED }

const CHAIR_SCENE = preload("res://game/chair/chair.tscn")

var chairs: Array[Chair] = []
var stage: ArenaStage
var presentation: RoundView
var phase: Phase = Phase.INTRO
var intro_duration: float = 2.5
var startup_duration: float = 2.0
var resolve_duration: float = 1.6
var round_id: int = 0
var _roster: Array[Dictionary] = []
var _definition: StageDefinition
var _elapsed: float = 0.0
var _winner: int = -1
var _pending: Dictionary = {}
var _input_ready: bool = false
var _pilots: Dictionary = {}
var _input := LocalInput.new()
var _spray := SpraySystem.new()
var _hint: Label
var _title: Label
var _indicators: RoundRoster
var _spectator: SpectatorSpeed
var _intro_background: ColorRect
var _warming_rendering := false


func configure(
	roster: Array[Dictionary], definition: StageDefinition, id: int, _target_wins: int
) -> void:
	_roster = roster.duplicate(true)
	_definition = definition
	round_id = id


func _ready() -> void:
	stage = _definition.scene.instantiate() as ArenaStage
	add_child(stage)
	stage.elimination_requested.connect(request_elimination)
	presentation = RoundView.new()
	presentation.configure(stage)
	add_child(presentation)
	presentation.world.hide()
	var bodies := Node2D.new()
	bodies.name = "Chairs"
	bodies.y_sort_enabled = true
	add_child(bodies)
	var poses := SpawnLayout.poses(stage, _roster.size())
	for participant in _roster:
		var chair := CHAIR_SCENE.instantiate() as Chair
		chair.skin = participant.get("skin", SkinCatalog.default_definition())
		chair.hat_id = participant.get("hat_id", &"none")
		chair.resize_for_stage(stage.content_scale)
		var pose := poses[participant.id]
		chair.configure(participant.id, participant.colour, Vector2.from_angle(pose.get_rotation()))
		chair.prepare_round()
		chair.fall_confirmed.connect(_on_fall_confirmed)
		chair.get_node("Visuals").configure_world(presentation.viewport, presentation.world, stage)
		bodies.add_child(chair)
		chair.global_transform = pose
		chairs.append(chair)
		if chair.seat != 0:
			_pilots[chair.seat] = PracticePilot.new()
	stage.bind_participants(chairs)
	var layer := CanvasLayer.new()
	add_child(layer)
	_intro_background = ColorRect.new()
	_intro_background.name = "IntroBackground"
	_intro_background.color = Color.BLACK
	_intro_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_intro_background)
	_title = Label.new()
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.offset_top = -48
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override(
		"font_size", 68 if _definition.display_name.length() < 27 else 54
	)
	_title.add_theme_color_override("font_shadow_color", Color.BLACK)
	_title.add_theme_constant_override("shadow_offset_y", 4)
	_title.text = _definition.display_name
	_intro_background.add_child(_title)
	_hint = Label.new()
	_hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hint.offset_top = 84
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 24)
	_hint.text = _definition.hint
	_intro_background.add_child(_hint)
	_indicators = RoundRoster.new()
	_indicators.participants = _roster.duplicate(true)
	layer.add_child(_indicators)
	_indicators.hide()
	_spectator = SpectatorSpeed.new()
	_spectator.can_fast_forward = _can_fast_forward
	add_child(_spectator)
	_warming_rendering = DisplayServer.get_name() != "headless"
	_warm_up_rendering.call_deferred()


## Warm actual effect pipelines beneath the opaque title without advancing gameplay.
func _warm_up_rendering() -> void:
	# Hidden objects do not compile their GPU paths. Draw them once beneath the
	# opaque title, then suspend arena rendering until gameplay actually starts.
	if phase != Phase.INTRO or DisplayServer.get_name() == "headless":
		_warming_rendering = false
		return
	_warming_rendering = true
	presentation.world.show()
	stage.set_render_warmup(true)
	for chair in chairs:
		chair.get_node("Visuals").set_render_warmup(true)
	# Let the scene tree flush visibility/transforms and render the real viewport.
	# A forced draw here can run before those updates reach the renderer.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	stage.set_render_warmup(false)
	for chair in chairs:
		chair.get_node("Visuals").set_render_warmup(false)
	if phase == Phase.INTRO:
		presentation.world.hide()
	_warming_rendering = false


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if phase == Phase.INTRO:
		_title.modulate.a = 1.0 - smoothstep(intro_duration * 0.75, intro_duration, _elapsed)
		_hint.modulate.a = _title.modulate.a
		if _elapsed >= intro_duration and not _warming_rendering:
			begin_live()
	elif phase == Phase.LIVE:
		if not _steering_held():
			_input_ready = true
		for chair in chairs:
			if chair.seat == 0:
				chair.command = _input.sample() if _input_ready else ChairCommand.new()
			else:
				chair.command = _pilots[chair.seat].sample_on_stage(chair, chairs, stage, delta)
			chair.step(delta)
		for chair in chairs:
			_spray.apply(chair, chairs, delta)
		stage.tick_hazards(delta)
		for chair in chairs:
			if chair.is_in_play():
				var reason := stage.elimination_reason(chair.global_position)
				if reason == &"fall":
					# Tiny rim tolerance preserves partial wheel overhang. Once the center
					# loses support, native gravity/contact physics decides tipping or landing.
					var radius := 0.15 * RenderStyle.PIXELS_PER_UNIT * chair.size_scale
					if not stage.has_support_near(chair.global_position, radius):
						chair.begin_fall()
				elif reason != &"":
					request_elimination(chair.seat, reason)
		_commit_eliminations()
		_spectator.refresh()
	elif phase == Phase.RESOLVING and _elapsed >= resolve_duration:
		phase = Phase.FINISHED
		for chair in chairs:
			chair.get_node("Visuals").freeze_visuals()
		presentation.world.hide()
		_indicators.hide()
		completed.emit(round_id, _winner)


func begin_live() -> void:
	if phase != Phase.INTRO:
		return
	phase = Phase.LIVE
	_elapsed = 0.0
	_intro_background.hide()
	presentation.world.show()
	_indicators.show()
	stage.start_round()
	for chair in chairs:
		chair.start_extinguisher_ramp(startup_duration)
		chair.begin_round()


func request_elimination(seat: int, reason: StringName) -> void:
	if phase != Phase.LIVE or seat < 0 or seat >= chairs.size() or not chairs[seat].active:
		return
	_pending[seat] = reason


func _commit_eliminations() -> void:
	if _pending.is_empty():
		return
	for seat in _pending:
		chairs[seat].eliminate(_pending[seat])
		_indicators.mark_eliminated(seat)
	_pending.clear()
	var survivors: Array[Chair] = []
	for chair in chairs:
		if chair.active:
			survivors.append(chair)
	if survivors.size() > 1:
		return
	_winner = survivors[0].seat if survivors.size() == 1 else -1
	phase = Phase.RESOLVING
	_elapsed = 0.0
	stage.stop_round()
	for chair in chairs:
		chair.stop_drive()


func _steering_held() -> bool:
	return (
		Input.is_physical_key_pressed(KEY_LEFT)
		or Input.is_physical_key_pressed(KEY_RIGHT)
		or Input.is_physical_key_pressed(KEY_A)
		or Input.is_physical_key_pressed(KEY_D)
	)


func _exit_tree() -> void:
	if is_instance_valid(stage):
		stage.stop_round()


func _can_fast_forward() -> bool:
	if phase != Phase.LIVE or chairs.is_empty() or chairs[0].active:
		return false
	var surviving_ai := 0
	for chair in chairs:
		if chair.active and _pilots.has(chair.seat):
			surviving_ai += 1
	return surviving_ai > 1


func _on_fall_confirmed(seat: int) -> void:
	request_elimination(seat, &"fall")
