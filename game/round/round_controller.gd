class_name RoundController
extends Node2D
## Owns one stage and its bodies. Eliminations are committed as one physics batch.

signal completed(round_id: int, winner_id: int)
## Host: a seat was eliminated this physics batch (after its chair has been told).
signal eliminated(seat: int, reason: StringName)
## Host: the last elimination decided the round; resolution has begun.
signal decided(winner_id: int)
## A client spectator requests a held/released fast-forward state from the host.
signal fast_forward_requested(held: bool)

enum Phase { INTRO, LIVE, RESOLVING, FINISHED }

const CHAIR_SCENE = preload("res://game/chair/chair.tscn")
## After the opening jet ramp, movement doubles over a minute of live round time.
const SPEED_RAMP_SECONDS := 60.0
const MAX_SPEED_MULTIPLIER := 2.0

var chairs: Array[Chair] = []
var stage: ArenaStage
var presentation: RoundView
var phase: Phase = Phase.INTRO
var intro_duration: float = 2.5
var startup_duration: float = 2.0
var resolve_duration: float = 1.6
var round_id: int = 0
## The seat steered by this machine's LocalInput (-1: none).
var local_seat: int = 0
## Host: seats steered by remote peers, seat -> latest turn. Shared with the match.
var remote_turns: Dictionary = {}
## Online client: build the same scene but only display the host's snapshots and events.
var mirror := false
var allow_fast_forward := true
## Online client: the steering value this peer sends to the host.
var local_turn: float = 0.0
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
var _snapshot := RoundSnapshot.new()
var _net_fast_forward_available := false
var _base_movement: Array[Vector2] = []
var _speed_multiplier := 1.0


func configure(
	roster: Array[Dictionary], definition: StageDefinition, id: int, _target_wins: int
) -> void:
	_roster = roster.duplicate(true)
	_definition = definition
	round_id = id


func _ready() -> void:
	stage = _definition.scene.instantiate() as ArenaStage
	# The flag is already set while the stage readies; the hook follows once it is in the tree.
	stage.net_mirror = mirror
	add_child(stage)
	if mirror:
		stage.set_net_mirror(true)
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
		# Each seat owns its movement tuning; do not modify the shared resource.
		chair.tuning = chair.tuning.duplicate() as ChairTuning
		_base_movement.append(Vector2(chair.tuning.thrust, chair.tuning.maximum_speed))
		var pose := poses[participant.id]
		chair.configure(participant.id, participant.colour, Vector2.from_angle(pose.get_rotation()))
		chair.prepare_round()
		chair.fall_confirmed.connect(_on_fall_confirmed)
		chair.get_node("Visuals").configure_world(presentation.viewport, presentation.world, stage)
		bodies.add_child(chair)
		chair.global_transform = pose
		chairs.append(chair)
		if mirror:
			chair.make_net_puppet()
		elif chair.seat != local_seat and not remote_turns.has(chair.seat):
			_pilots[chair.seat] = PracticePilot.new()
	stage.bind_participants(chairs)
	_snapshot.bind(stage)
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
	_spectator.manage_timing = not mirror
	_spectator.fast_forward_requested.connect(
		func(held: bool) -> void: fast_forward_requested.emit(held)
	)
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
	if mirror:
		_mirror_step(delta)
		return
	if phase == Phase.INTRO:
		_title.modulate.a = 1.0 - smoothstep(intro_duration * 0.75, intro_duration, _elapsed)
		_hint.modulate.a = _title.modulate.a
		if _elapsed >= intro_duration and not _warming_rendering:
			begin_live()
	elif phase == Phase.LIVE:
		var progress := clampf((_elapsed - startup_duration) / SPEED_RAMP_SECONDS, 0.0, 1.0)
		_apply_speed_multiplier(lerpf(1.0, MAX_SPEED_MULTIPLIER, progress))
		if not _steering_held():
			_input_ready = true
		for chair in chairs:
			if chair.seat == local_seat:
				chair.command = _input.sample() if _input_ready else ChairCommand.new()
			elif remote_turns.has(chair.seat):
				var command := ChairCommand.new()
				command.turn = clampf(remote_turns[chair.seat], -1.0, 1.0)
				chair.command = command
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
		_finish()
		completed.emit(round_id, _winner)


func _apply_speed_multiplier(multiplier: float) -> void:
	_speed_multiplier = clampf(multiplier, 1.0, MAX_SPEED_MULTIPLIER)
	for index in chairs.size():
		chairs[index].tuning.thrust = _base_movement[index].x * _speed_multiplier
		chairs[index].tuning.maximum_speed = _base_movement[index].y * _speed_multiplier


func _finish() -> void:
	phase = Phase.FINISHED
	for chair in chairs:
		chair.get_node("Visuals").freeze_visuals()
	presentation.world.hide()
	_indicators.hide()


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
	if (
		mirror
		or phase != Phase.LIVE
		or seat < 0
		or seat >= chairs.size()
		or not chairs[seat].active
	):
		return
	_pending[seat] = reason


func _commit_eliminations() -> void:
	if _pending.is_empty():
		return
	for seat in _pending:
		chairs[seat].eliminate(_pending[seat])
		_indicators.mark_eliminated(seat)
		eliminated.emit(seat, _pending[seat])
	_pending.clear()
	var survivors: Array[Chair] = []
	for chair in chairs:
		if chair.active:
			survivors.append(chair)
	if survivors.size() > 1:
		return
	_winner = survivors[0].seat if survivors.size() == 1 else -1
	_resolve()
	decided.emit(_winner)


func _resolve() -> void:
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
	if not allow_fast_forward or phase != Phase.LIVE:
		return false
	if mirror:
		return _net_fast_forward_available
	var survivors := 0
	for chair in chairs:
		if not chair.active:
			continue
		if chair.seat == local_seat or remote_turns.has(chair.seat):
			return false
		survivors += 1
	return survivors > 1


## Host: combine remote holds with the local hold. Client: display the host's speed.
func set_network_fast_forward(held: bool) -> void:
	_spectator.set_network_fast_forward(held)


func is_fast_forwarding() -> bool:
	return _spectator.is_accelerated()


func _on_fall_confirmed(seat: int) -> void:
	request_elimination(seat, &"fall")


## Host: a remote seat whose peer left is piloted by AI for the rest of the round.
func make_ai(seat: int) -> void:
	remote_turns.erase(seat)
	if not mirror and seat >= 0 and seat < chairs.size() and not _pilots.has(seat):
		_pilots[seat] = PracticePilot.new()


## Host: this frame's continuous state for clients (see RoundSnapshot).
func net_snapshot() -> Dictionary:
	var packed := _snapshot.capture_chairs(chairs)
	var payload := {
		"r": round_id,
		"speed": _speed_multiplier,
		"fast_forward_available": _can_fast_forward(),
		"fast_forward": is_fast_forwarding(),
		"p": phase,
		"t": _elapsed,
		"c": packed[0],
		"f": packed[1],
		"o": _snapshot.capture_props(),
	}
	var hazards: Variant = stage.net_state()
	if hazards != null:
		payload["s"] = hazards
	return payload


## Client: adopt the host's latest snapshot. Chairs glide towards it every physics frame.
func apply_net_snapshot(payload: Dictionary) -> void:
	var values: PackedFloat32Array = payload.get("c", PackedFloat32Array())
	var flags: PackedByteArray = payload.get("f", PackedByteArray())
	if values.size() != chairs.size() * RoundSnapshot.CHAIR_FLOATS or flags.size() != chairs.size():
		return
	_apply_speed_multiplier(float(payload.get("speed", 1.0)))
	_net_fast_forward_available = bool(payload.get("fast_forward_available", false))
	var host_phase: int = payload.get("p", Phase.INTRO)
	if phase == Phase.INTRO:
		if host_phase == Phase.INTRO:
			_elapsed = payload.get("t", _elapsed)
		elif host_phase == Phase.LIVE:
			begin_live()
	set_network_fast_forward(bool(payload.get("fast_forward", false)))
	for chair in chairs:
		_apply_chair(chair, values, flags[chair.seat])
	_snapshot.apply_props(payload.get("o", PackedFloat32Array()))
	if payload.has("s"):
		stage.apply_net_state(payload["s"])


func _apply_chair(chair: Chair, values: PackedFloat32Array, flag: int) -> void:
	var base := chair.seat * RoundSnapshot.CHAIR_FLOATS
	var point := Vector2(values[base], values[base + 1])
	var heading := values[base + 2]
	var velocity := Vector2(values[base + 3], values[base + 4])
	var spin := values[base + 5]
	chair.jet_strength = values[base + 6]
	chair.impact = values[base + 7]
	chair.spray_reach = values[base + 8]
	chair.spraying = chair.active and flag & RoundSnapshot.SPRAYING != 0
	if not chair.active:
		return
	var host_falling := flag & RoundSnapshot.FALLING != 0
	if flag & RoundSnapshot.ACTIVE == 0:
		# Eliminations replay from their reliable event, which carries the launch.
		return
	if host_falling and not chair.falling:
		_start_mirrored_fall(chair, point, heading, velocity, spin)
	elif not host_falling and chair.falling:
		# The host's chair crossed a gap and landed back on the floor.
		chair.get_node("Visuals").end_fall()
		chair.land_from_fall(point, heading, velocity, spin)
		chair.set_net_state(point, heading, velocity, spin)
	elif not host_falling:
		chair.set_net_state(point, heading, velocity, spin)


func _start_mirrored_fall(
	chair: Chair, point: Vector2, heading: float, velocity: Vector2, spin: float
) -> void:
	chair.global_position = point
	chair.global_rotation = heading
	chair.begin_fall()
	chair.fall_velocity = velocity
	chair.fall_spin = spin


## Client: replay the host's elimination, including any launch, as local cosmetics.
func apply_net_elimination(data: Dictionary) -> void:
	var seat: int = data.get("seat", -1)
	if seat < 0 or seat >= chairs.size() or not chairs[seat].active:
		return
	var chair := chairs[seat]
	if data.get("falling", false) and not chair.falling:
		chair.knockout_velocity = data.get("knockout_velocity", Vector3.ZERO)
		chair.knockout_spin = data.get("knockout_spin", Vector3.ZERO)
		_start_mirrored_fall(
			chair,
			data.get("position", chair.global_position),
			data.get("rotation", chair.global_rotation),
			data.get("fall_velocity", Vector2.ZERO),
			data.get("fall_spin", 0.0)
		)
	elif not data.get("falling", false):
		chair.knockout_velocity = Vector3.ZERO
	chair.eliminate(data.get("reason", &"fall"))
	_indicators.mark_eliminated(seat)


## Client: the host decided the round; stop hazards and drive as the host did.
func apply_net_decision() -> void:
	if phase == Phase.INTRO:
		begin_live()
	if phase == Phase.LIVE:
		_resolve()


## Client: the host's results are in; end the round exactly as the host's did.
func apply_net_finish() -> void:
	apply_net_decision()
	if phase == Phase.RESOLVING:
		_finish()


func _mirror_step(delta: float) -> void:
	# Play streamed movement and stage cosmetics at the host's spectator speed.
	if phase == Phase.LIVE and _spectator.network_fast_forward:
		delta *= SpectatorSpeed.MULTIPLIER
	if phase == Phase.INTRO:
		_title.modulate.a = 1.0 - smoothstep(intro_duration * 0.75, intro_duration, _elapsed)
		_hint.modulate.a = _title.modulate.a
	elif phase == Phase.LIVE:
		if not _steering_held():
			_input_ready = true
		local_turn = _input.sample().turn if _input_ready else 0.0
		stage.tick_hazards(delta)
	for chair in chairs:
		chair.follow_net(delta)
