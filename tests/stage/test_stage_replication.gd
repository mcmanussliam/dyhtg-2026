extends RefCounted
## Host-to-client stage replication for every map. A host stage runs its hazards while a
## mirror in its own physics world receives only `net_state()` and `net_event` payloads.
## The mirror must show the same actors, warnings and holes, report the same support and
## safety, never request eliminations and never collide with anything.

const STEP := 1.0 / 60
const STATE_BUDGET := 1024
const UNITS := 1.0 / RenderStyle.PIXELS_PER_UNIT
const MAPS := [
	["a_floor_in_the_crack", 24.0],
	["a_crack_in_the_floor", 24.0],
	["bull_office", 20.0],
	["hr_training", 12.0],
	["under_construction", 14.0],
	["faulty_floors", 10.0],
	["computer_bugs", 16.0],
	["after_hours", 21.0],
]


func run(tree: SceneTree, check: Callable) -> void:
	await _test_defaults(tree, check)
	for entry in MAPS:
		await _test_map(tree, check, entry[0], entry[1])


func _test_defaults(tree: SceneTree, check: Callable) -> void:
	var base := ArenaStage.new()
	tree.root.add_child(base)
	base.apply_net_state(PackedFloat32Array([1, 2, 3]))
	base.apply_net_event({"k": "crack"})
	check.call(
		base.net_state() == null and not base.net_mirror,
		"Base stages have no network state and are not mirrors"
	)
	base.queue_free()
	# Single-player maps tolerate stray or malformed payloads without changing support.
	for entry in MAPS:
		var definition := load("res://game/stage/%s/%s.tres" % [entry[0], entry[0]])
		var stage := (definition as StageDefinition).scene.instantiate() as ArenaStage
		tree.root.add_child(stage)
		var before := _support_samples(stage)
		for payload in [null, 3, {}, {"k": "crack", "r": -4}, {"k": "panels_drop", "i": []}]:
			stage.apply_net_event(payload)
		for state in [null, 1.5, PackedFloat32Array([1]), PackedFloat64Array()]:
			stage.apply_net_state(state)
		check.call(
			_support_samples(stage) == before and not stage.net_mirror,
			"%s ignores malformed network payloads" % entry[0]
		)
		stage.queue_free()
	await tree.process_frame


func _test_map(tree: SceneTree, check: Callable, id: String, seconds: float) -> void:
	var definition := load("res://game/stage/%s/%s.tres" % [id, id]) as StageDefinition
	var host := _build(tree, definition, false)
	var mirror := _build(tree, definition, true)
	var host_stage: ArenaStage = host.stage
	var mirror_stage: ArenaStage = mirror.stage
	for stage: ArenaStage in [host_stage, mirror_stage]:
		var random: Variant = stage.get("_random")
		if random is RandomNumberGenerator:
			random.seed = 9127
	var kills: Array[int] = []
	mirror_stage.elimination_requested.connect(
		func(seat: int, _reason: StringName) -> void: kills.append(seat)
	)
	var events: Array[String] = []
	var plain := [true]
	var event_bytes := [0]
	host_stage.net_event.connect(
		func(payload: Variant) -> void:
			# Payloads cross the network as plain Variants, never Objects.
			var bytes := var_to_bytes(payload)
			event_bytes[0] = maxi(event_bytes[0], bytes.size())
			var wire: Variant = bytes_to_var(bytes)
			plain[0] = plain[0] and _is_plain(payload) and wire != null
			events.append(String(payload.get("k", "")) if payload is Dictionary else "?")
			mirror_stage.apply_net_event(wire)
	)
	await tree.physics_frame
	for stage: ArenaStage in [host_stage, mirror_stage]:
		stage.set_render_warmup(true)
		stage.set_render_warmup(false)
		stage.start_round()
	var largest := 0
	var mismatch := ""
	var support_mismatch := ""
	var steps := int(seconds / STEP)
	for step in steps:
		_move_chairs(host.chairs, mirror.chairs, host_stage, step * STEP)
		_copy_loose_props(host_stage, mirror_stage)
		host_stage.tick_hazards(STEP)
		var state: Variant = host_stage.net_state()
		var bytes := var_to_bytes(state)
		largest = maxi(largest, bytes.size())
		mirror_stage.apply_net_state(bytes_to_var(bytes))
		mirror_stage.tick_hazards(STEP)
		if mismatch.is_empty():
			mismatch = _actors_differ(id, host_stage, mirror_stage)
			if not mismatch.is_empty():
				mismatch = "%.2fs: %s" % [step * STEP, mismatch]
		if step % 20 == 0 and support_mismatch.is_empty():
			support_mismatch = _support_differs(host_stage, mirror_stage)
			if not support_mismatch.is_empty():
				support_mismatch = "%.2fs: %s" % [step * STEP, support_mismatch]
		await tree.physics_frame
	check.call(mismatch.is_empty(), "%s mirror shows the host's actors %s" % [id, mismatch])
	check.call(
		support_mismatch.is_empty(),
		"%s mirror reports the host's support and safety %s" % [id, support_mismatch]
	)
	check.call(kills.is_empty(), "%s mirror never requests eliminations" % id)
	check.call(plain[0], "%s events are plain Variants" % id)
	check.call(
		largest > 0 and largest < STATE_BUDGET,
		"%s net state stays compact (%d bytes)" % [id, largest]
	)
	check.call(event_bytes[0] < 16384, "%s events stay small (%d bytes)" % [id, event_bytes[0]])
	check.call(_mirror_is_inert(id, mirror_stage), "%s mirror actors never collide" % id)
	check.call(
		_released_props(host_stage) == _released_props(mirror_stage),
		"%s mirror releases and smashes the same furniture" % id
	)
	_check_progress(check, id, host_stage, events)
	for stage: ArenaStage in [host_stage, mirror_stage]:
		stage.stop_round()
	host.viewport.queue_free()
	mirror.viewport.queue_free()
	await tree.process_frame


## Each side gets its own 2D/3D worlds, so the mirror's physics never meets the host's.
func _build(tree: SceneTree, definition: StageDefinition, mirrored: bool) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.world_2d = World2D.new()
	viewport.size = Vector2i(64, 64)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	tree.root.add_child(viewport)
	var stage := definition.scene.instantiate() as ArenaStage
	viewport.add_child(stage)
	if mirrored:
		stage.set_net_mirror(true)
	var world := Node3D.new()
	viewport.add_child(world)
	RenderStyle.setup_world(world)
	stage.create_presentation(world, UNITS)
	var chairs: Array[Chair] = []
	for seat in 3:
		var chair := preload("res://game/chair/chair.tscn").instantiate() as Chair
		chair.get_node("Visuals").free()
		chair.resize_for_stage(stage.content_scale)
		chair.configure(seat, Color.WHITE, Vector2.RIGHT)
		viewport.add_child(chair)
		chair.prepare_round()
		if mirrored:
			# Client chairs are puppets set from snapshots.
			chair.collision_layer = 0
			chair.collision_mask = 0
		chairs.append(chair)
	stage.bind_participants(chairs)
	return {"viewport": viewport, "stage": stage, "chairs": chairs}


## Deterministic laps around the room stand in for live steering.
func _move_chairs(host: Array[Chair], mirror: Array[Chair], stage: ArenaStage, time: float) -> void:
	var middle: Vector2 = stage.get("center")
	for index in host.size():
		var angle := time * 0.7 + index * TAU / host.size()
		var radius := 230.0 + 110.0 * sin(time * 0.4 + index)
		host[index].global_position = stage.to_global(middle + Vector2.from_angle(angle) * radius)
		mirror[index].global_transform = host[index].global_transform


## The round layer mirrors loose props generically; emulate it here.
func _copy_loose_props(host: ArenaStage, mirror: ArenaStage) -> void:
	var source := host.get_node_or_null(^"Furniture")
	if source == null:
		return
	for prop in source.get_children():
		if prop is RigidBody2D and not prop.freeze:
			var copy := mirror.get_node(^"Furniture").get_node(NodePath(prop.name)) as Node2D
			copy.global_transform = prop.global_transform


func _actors_differ(id: String, host: ArenaStage, mirror: ArenaStage) -> String:
	var compare := {
		"a_floor_in_the_crack": _edges_differ,
		"a_crack_in_the_floor": _edges_differ,
		"bull_office": _bulls_differ,
		"hr_training": _vehicles_differ,
		"under_construction": _vehicles_differ,
		"faulty_floors": _panels_differ,
		"computer_bugs": _clumps_differ,
		"after_hours": _guards_differ,
	}
	return compare[id].call(host, mirror)


func _edges_differ(host: ArenaStage, mirror: ArenaStage) -> String:
	var a: CrumblingEdge = host.get("_erosion")
	var b: CrumblingEdge = mirror.get("_erosion")
	var host_view: Node3D = host.get("_fracture_view").get("_warning")
	var mirror_view: Node3D = mirror.get("_fracture_view").get("_warning")
	if a.revision != b.revision or a.outline != b.outline:
		return "outline revision %d vs %d" % [a.revision, b.revision]
	if a.warning.size() != b.warning.size() or host_view.visible != mirror_view.visible:
		return "warning sections %d vs %d" % [a.warning.size(), b.warning.size()]
	return ""


func _bulls_differ(host: ArenaStage, mirror: ArenaStage) -> String:
	var a: Array = host.get("bulls")
	var b: Array = mirror.get("bulls")
	if a.size() != b.size():
		return "bull count %d vs %d" % [a.size(), b.size()]
	for index in a.size():
		if (
			a[index].phase != b[index].phase
			or a[index].position.distance_to(b[index].position) > 0.05
			or absf(angle_difference(a[index].rotation, b[index].rotation)) > 0.001
			or a[index].get("_lane").visible != b[index].get("_lane").visible
		):
			return "bull %d pose, phase or charge lane" % index
	if absf(_door_angle(host) - _door_angle(mirror)) > 0.001:
		return "saloon door angle"
	return ""


func _vehicles_differ(host: ArenaStage, mirror: ArenaStage) -> String:
	var trains := host.get("trains") != null
	var a: Array = host.get("trains" if trains else "vehicles")
	var b: Array = mirror.get("trains" if trains else "vehicles")
	for index in a.size():
		var moving: bool = a[index].phase != 0
		if (
			a[index].phase != b[index].phase
			or (moving and a[index].position.distance_to(b[index].position) > 0.05)
			or (moving and a[index].lane != b[index].lane)
			or (moving and not a[index].direction.is_equal_approx(b[index].direction))
			or a[index].get("_model").visible != b[index].get("_model").visible
			or (not trains and a[index].get("_lane").visible != b[index].get("_lane").visible)
		):
			return "vehicle %d phase, lane, pose or warning" % index
	if trains:
		var lights_a: Array = host.get("_signals")
		var lights_b: Array = mirror.get("_signals")
		for index in lights_a.size():
			var lit_a: bool = lights_a[index].material_override == host.get("_signal_on")
			var lit_b: bool = lights_b[index].material_override == mirror.get("_signal_on")
			if lit_a != lit_b:
				return "warning signal %d" % index
	return ""


func _panels_differ(host: ArenaStage, mirror: ArenaStage) -> String:
	var a: FaultyFloorGrid = host.get("grid")
	var b: FaultyFloorGrid = mirror.get("grid")
	if a.states != b.states:
		return "panel states"
	for index in a.states.size():
		if a.states[index] == FaultyFloorGrid.State.WARNING:
			if not is_equal_approx(a.armed_at[index], b.armed_at[index]):
				return "panel %d warning clock" % index
	return ""


func _clumps_differ(host: ArenaStage, mirror: ArenaStage) -> String:
	var a: Array = host.get("clumps")
	var b: Array = mirror.get("clumps")
	if a.size() != b.size():
		return "clump count %d vs %d" % [a.size(), b.size()]
	for index in a.size():
		if (
			a[index].phase != b[index].phase
			or a[index].position != b[index].position
			or absf(a[index].height - b[index].height) > 0.001
			or a[index].landed != b[index].landed
			or a[index].block != b[index].block
		):
			return "clump %d" % index
	for slot in ComputerBugsStage.POOL:
		for pool in ["_markers", "_falling"]:
			if host.get(pool)[slot].visible != mirror.get(pool)[slot].visible:
				return "%s slot %d visibility" % [pool, slot]
	if host.get("_blob").visible != mirror.get("_blob").visible:
		return "mush decal visibility"
	return ""


func _guards_differ(host: ArenaStage, mirror: ArenaStage) -> String:
	var a: Array = host.get("guards")
	var b: Array = mirror.get("guards")
	if a.size() != b.size():
		return "guard count %d vs %d" % [a.size(), b.size()]
	for index in a.size():
		if (
			a[index].phase != b[index].phase
			or a[index].position.distance_to(b[index].position) > 0.05
			or absf(angle_difference(a[index].beam_angle, b[index].beam_angle)) > 0.001
			or a[index].get("_model").get("_alert") != b[index].get("_model").get("_alert")
		):
			return "guard %d pose, beam or alert" % index
	return ""


func _door_angle(stage: ArenaStage) -> float:
	var door: Variant = stage.get("_door")
	return door.get("_angle") if is_instance_valid(door) else 0.0


## Sample support, elimination reasons and safety across (and just beyond) the room.
func _support_differs(host: ArenaStage, mirror: ArenaStage) -> String:
	var middle: Vector2 = host.get("center")
	for x in 21:
		for y in 21:
			var point := host.to_global(middle + Vector2(x - 10, y - 10) * 68.0)
			if host.has_support(point) != mirror.has_support(point):
				return "support at %s" % point
			if host.elimination_reason(point) != mirror.elimination_reason(point):
				return "elimination reason at %s" % point
			if host.is_safe(point, 20) != mirror.is_safe(point, 20):
				return "safety at %s" % point
	return ""


## Names of furniture taken off the planar floor: fractured, smashed or launched.
func _released_props(stage: ArenaStage) -> Array[String]:
	var names: Array[String] = []
	for prop in stage.get_node(^"Furniture").get_children():
		if prop is OfficeProp and prop.collision_layer == 0:
			names.append(String(prop.name))
	return names


func _support_samples(stage: ArenaStage) -> Array[bool]:
	var samples: Array[bool] = []
	for x in 9:
		for y in 9:
			samples.append(stage.has_support(Vector2(x * 160 - 20, y * 140 - 200)))
	return samples


func _mirror_is_inert(id: String, mirror: ArenaStage) -> bool:
	var bodies: Array = []
	match id:
		"bull_office":
			bodies = mirror.get("bulls")
		"after_hours":
			bodies = mirror.get("guards")
		"hr_training":
			for actor in mirror.get("trains"):
				bodies.append(actor.get("_model"))
	return bodies.all(
		func(body: Variant) -> bool: return body.collision_layer == 0 and body.collision_mask == 0
	)


## The run must actually exercise each map's hazards, or matching proves nothing.
func _check_progress(check: Callable, id: String, host: ArenaStage, events: Array[String]) -> void:
	match id:
		"a_floor_in_the_crack", "a_crack_in_the_floor":
			check.call(
				events.has("crack_warn") and events.count("crack") >= 2,
				"%s replicated crumble warnings and steps" % id
			)
		"bull_office":
			check.call(host.get("bulls").size() >= 2, "Bull office replicated a door arrival")
		"hr_training":
			check.call(
				host.get("trains").any(func(t: TrainingTrain) -> bool: return t.phase == 2),
				"HR training replicated a crossing train"
			)
		"under_construction":
			check.call(
				host.get("_deployed") >= 3 and events.has("prop_hit"),
				"Under construction replicated diggers and smashed furniture"
			)
		"faulty_floors":
			check.call(
				events.has("panels_warn") and events.has("panels_drop"),
				"Faulty floors replicated panel warnings and drops"
			)
		"computer_bugs":
			check.call(
				events.has("bug_drop") and events.has("bug_land"),
				"Computer bugs replicated announcements and landings"
			)
		"after_hours":
			check.call(host.get("guards").size() >= 2, "After hours replicated guard arrivals")


func _is_plain(value: Variant) -> bool:
	if value is Object:
		return false
	if value is Array:
		return value.all(_is_plain)
	if value is Dictionary:
		return value.keys().all(_is_plain) and value.values().all(_is_plain)
	return true
