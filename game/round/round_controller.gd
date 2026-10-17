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
var _title: Label
var _intro_background: ColorRect


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
	var bodies := Node2D.new()
	bodies.name = "Chairs"
	bodies.y_sort_enabled = true
	add_child(bodies)
	for participant in _roster:
		var chair := CHAIR_SCENE.instantiate() as Chair
		var pose := stage.spawn_pose(participant.id, _roster.size())
		chair.configure(participant.id, participant.colour, Vector2.from_angle(pose.get_rotation()))
		chair.prepare_round()
		chair.get_node("Visuals").configure_world(presentation.viewport, presentation.world)
		bodies.add_child(chair)
		chair.global_transform = pose
		chairs.append(chair)
		if chair.seat != 0:
			_pilots[chair.seat] = PracticePilot.new()
	var layer := CanvasLayer.new()
	add_child(layer)
	_intro_background = ColorRect.new()
	_intro_background.name = "IntroBackground"
	_intro_background.color = Color.BLACK
	_intro_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_intro_background)
	_title = Label.new()
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 84)
	_title.add_theme_color_override("font_shadow_color", Color.BLACK)
	_title.add_theme_constant_override("shadow_offset_y", 4)
	_title.text = _definition.display_name
	_intro_background.add_child(_title)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if phase == Phase.INTRO:
		_title.modulate.a = 1.0 - smoothstep(intro_duration * 0.75, intro_duration, _elapsed)
		if _elapsed >= intro_duration:
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
			if chair.active:
				var reason := stage.elimination_reason(chair.global_position)
				if reason != &"":
					request_elimination(chair.seat, reason)
		_commit_eliminations()
	elif phase == Phase.RESOLVING and _elapsed >= resolve_duration:
		phase = Phase.FINISHED
		for chair in chairs:
			chair.get_node("Visuals").freeze_visuals()
		presentation.world.hide()
		completed.emit(round_id, _winner)


func begin_live() -> void:
	if phase != Phase.INTRO:
		return
	phase = Phase.LIVE
	_elapsed = 0.0
	_intro_background.hide()
	stage.start_round()
	for chair in chairs:
		chair.begin_round()


func request_elimination(seat: int, reason: StringName) -> void:
	if phase != Phase.LIVE or seat < 0 or seat >= chairs.size() or not chairs[seat].active:
		return
	_pending[seat] = reason


func _commit_eliminations() -> void:
	for seat in _pending:
		chairs[seat].eliminate(_pending[seat])
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
