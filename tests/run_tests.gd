extends SceneTree
## Engine regressions for continuous-spray, torque-steered physics play.

const GAME: PackedScene = preload("res://game/session/gameplay.tscn")

var _checks: int = 0
var _failures := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await _test_input()
	var game := GAME.instantiate() as GameSession
	root.add_child(game)
	game.set_physics_process(false)
	await physics_frame
	_expect(game.chairs.size() == 2, "Game must boot with the player and AI")
	_expect(not game.hud.visible, "Gameplay must have no visible HUD text")
	var office := game.stage.get_node("Office")
	_expect(office.get_child_count() == 0, "Carpet floor must have no furniture collisions")
	var desk_ray := PhysicsRayQueryParameters2D.create(Vector2(183, 300), Vector2(183, 180), 1)
	_expect(
		game.get_world_2d().direct_space_state.intersect_ray(desk_ray).is_empty(),
		"Removed office desks must not obstruct extinguisher rays"
	)
	_expect(game.get_node_or_null("Fire") == null, "No fire hazard may be instantiated")
	_expect(
		not FileAccess.file_exists("res://game/fire/fire_field.gd"),
		"Unused fire code must be removed"
	)
	_expect(
		game.stage.get_node_or_null("Walls") == null,
		"The stage must not have a visible wall border"
	)
	var camera := game.get_node("ArenaCamera") as Camera2D
	_expect(camera.zoom == Vector2(1, 0.72), "Camera must foreshorten the floor plane")
	var half_view := Vector2(640, 400) / camera.zoom
	var floor_polygon: PackedVector2Array = game.stage.get_node("Floor").polygon
	var floor_covers_view := true
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		floor_covers_view = (
			floor_covers_view
			and Geometry2D.is_point_in_polygon(camera.position + half_view * corner, floor_polygon)
		)
	_expect(floor_covers_view, "Floor must fill every corner of the tilted camera view")
	_expect(
		game.get_node("Chairs").global_transform == Transform2D.IDENTITY,
		"Camera projection must leave chair physics unscaled"
	)
	_expect(
		game.chairs[0].colour.get_luminance() > 0.65, "Characters must use a light body palette"
	)
	var visuals := game.chairs[0].get_node("Visuals")
	var model: ChairModel = visuals.get("_model")
	var face := model.face_colour
	_expect(
		face.get_luminance() > game.chairs[0].colour.get_luminance(),
		"Face panel must be lighter than the body"
	)
	_expect(
		model.body.get_child_count() == 1,
		"Character body and limbs must form one mesh with a flush painted face"
	)
	var aligned := true
	var chair := game.chairs[0]
	var original_heading := chair.rotation
	for heading in [0.0, PI / 2, PI, -PI / 2]:
		chair.rotation = heading
		visuals._sync_heading(chair)
		var model_forward := model.basis * Vector3.BACK
		var projected := Vector2(model_forward.x, model_forward.z)
		aligned = aligned and projected.dot(Vector2.from_angle(heading)) > 0.999
		aligned = aligned and is_zero_approx(visuals.global_rotation)
	_expect(aligned, "3D facing must match physics without rotating the rendered texture twice")
	chair.rotation = original_heading
	visuals._sync_heading(chair)
	await _test_physics(game)
	await _test_spray(game)
	await _test_session(game)
	game.queue_free()
	await process_frame
	await _test_collisions()
	await _test_endurance()
	if _failures.is_empty():
		print("PASS: %d physics sandbox checks" % _checks)
		quit(0)
	else:
		for message in _failures:
			printerr("FAIL: " + message)
		quit(1)


func _test_input() -> void:
	var first := LocalInput.new()
	var second := LocalInput.new()
	second.device = LocalInput.KEYBOARD_TWO
	_key(KEY_LEFT, true)
	await process_frame
	_expect(first.sample().turn == -1.0, "Left arrow must steer P1 left")
	_expect(second.sample().turn == 0.0, "P1 steering must not affect P2")
	_key(KEY_RIGHT, true)
	await process_frame
	_expect(first.sample().turn == 0.0, "Opposing steering keys must cancel")
	_key(KEY_LEFT, false)
	await process_frame
	_expect(first.sample().turn == 1.0, "Right arrow must steer P1 right")
	_key(KEY_RIGHT, false)
	_key(KEY_A, true)
	_key(KEY_LEFT, true)
	await process_frame
	_expect(first.sample().turn == -1.0, "Keyboard aliases must not double steering")
	_key(KEY_A, false)
	_key(KEY_LEFT, false)
	_key(KEY_J, true)
	await process_frame
	_expect(
		second.sample().turn == -1.0 and first.sample().turn == 0.0, "J must independently steer P2"
	)
	_key(KEY_J, false)
	await process_frame


func _test_physics(game: GameSession) -> void:
	var chair := game.chairs[0]
	chair.rotation = 0.0
	chair.angular_velocity = 0.0
	for frame in 30:
		chair.step(1.0 / 60.0)
		await physics_frame
	_expect(chair.linear_velocity.x < -10.0, "Neutral input must still propel the chair")
	_expect(chair.spraying, "Spray must be on without a held button")
	_expect(chair.impact < 0.01, "Continuous propulsion alone must not trigger collision squash")
	_expect(not chair.lock_rotation, "Collisions must be allowed to rotate the chair")
	chair.position = Vector2(600, 420)
	chair.linear_velocity = Vector2.ZERO
	chair.command.turn = 1.0
	for frame in 30:
		chair.step(1.0 / 60.0)
		await physics_frame
	_expect(chair.angular_velocity > 4.0, "Right steering must turn sharply within half a second")
	var spin := chair.angular_velocity
	chair.command.turn = 0.0
	for frame in 12:
		chair.step(1.0 / 60.0)
		await physics_frame
	_expect(
		absf(chair.angular_velocity) < spin * 0.30,
		"Steering release must quickly settle angular momentum"
	)
	# Isolate steering direction from wall/contact torque after the drift test.
	chair.position = Vector2(640, 420)
	chair.linear_velocity = Vector2.ZERO
	chair.angular_velocity = 0.0
	await physics_frame
	chair.command.turn = -1.0
	for frame in 30:
		chair.step(1.0 / 60.0)
		await physics_frame
	_expect(chair.angular_velocity < -4.0, "Left steering must turn sharply within half a second")
	chair.command.turn = 0.0
	chair.linear_velocity = Vector2(2000, 0)
	chair.angular_velocity = 99.0
	await physics_frame
	await physics_frame
	_expect(
		chair.linear_velocity.length() <= chair.tuning.maximum_speed + 1.0,
		"Physics must cap runaway linear velocity"
	)
	_expect(
		absf(chair.angular_velocity) <= chair.tuning.maximum_spin + 0.1,
		"Physics must cap runaway angular velocity"
	)
	var stale_resource: bool = false
	for property in chair.get_property_list():
		stale_resource = stale_resource or property.name in ["fuel", "heat", "braking", "refilling"]
	_expect(not stale_resource, "Removed fuel and heat systems must not remain on the chair")
	chair.position = Vector2(
		game.stage.world_bounds.end.x - 32, game.stage.world_bounds.get_center().y
	)
	chair.rotation = PI
	chair.angular_velocity = 0.0
	chair.linear_velocity = Vector2(400, 0)
	for frame in 45:
		chair.step(1.0 / 60.0)
		await physics_frame
	_expect(
		game.stage.world_bounds.has_point(chair.position), "Invisible edges must retain the chair"
	)


func _test_spray(game: GameSession) -> void:
	var source := game.chairs[0]
	var target := game.chairs[1]
	source.position = Vector2(500, 420)
	target.position = Vector2(640, 420)
	source.rotation = 0.0
	source.linear_velocity = Vector2.ZERO
	target.linear_velocity = Vector2.ZERO
	source.angular_velocity = 0.0
	target.angular_velocity = 0.0
	await physics_frame
	await physics_frame
	var spray := SpraySystem.new()
	spray.apply(source, game.chairs, 0.1)
	await physics_frame
	_expect(target.linear_velocity.x > 20.0, "Constant spray must push another chair")
	var obstacle := StaticBody2D.new()
	obstacle.position = Vector2(570, 420)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(12, 100)
	var collision := CollisionShape2D.new()
	collision.shape = shape
	obstacle.add_child(collision)
	game.add_child(obstacle)
	target.position = Vector2(640, 420)
	target.linear_velocity = Vector2.ZERO
	await physics_frame
	await physics_frame
	spray.apply(source, game.chairs, 0.1)
	await physics_frame
	_expect(target.linear_velocity.length() < 1.0, "Future stage obstacles must block jet force")
	_expect(source.spray_reach < 75.0, "Visible spray must share the obstacle hit distance")
	var visuals := source.get_node("Visuals")
	visuals._update_plume(source)
	var foam: SprayView = visuals.get("_spray")
	var forward := Vector3(cos(source.aim_angle), 0, sin(source.aim_angle))
	var foam_contained := true
	for index in foam._positions.size():
		var far_edge := foam._positions[index].dot(forward) + foam._sizes[index]
		foam_contained = foam_contained and far_edge <= source.spray_reach / 43.0 + 0.001
	_expect(foam_contained, "Every 3D foam ball must stop before the physics obstruction")
	source.spray_reach = 0
	visuals._update_plume(source)
	_expect(not foam.visible, "Foam must disappear when the nozzle is blocked")
	obstacle.queue_free()
	await process_frame


func _test_session(game: GameSession) -> void:
	var old_id := game.chairs[0].get_instance_id()
	game.request_restart()
	await process_frame
	await process_frame
	_expect(game.chairs[0].get_instance_id() != old_id, "Reset must replace physics bodies")
	_expect(get_nodes_in_group("chairs").size() == 2, "Reset must not leave old bodies behind")
	_key(KEY_ESCAPE, true)
	await process_frame
	_expect(paused, "Escape must pause physics")
	_key(KEY_ESCAPE, false)
	_key(KEY_ESCAPE, true)
	await process_frame
	_expect(not paused, "Escape must resume physics")
	_key(KEY_ESCAPE, false)
	_key(KEY_F2, true)
	await process_frame
	_expect(game.bindings[1].device == LocalInput.KEYBOARD_TWO, "F2 must hand the AI seat to P2")
	_key(KEY_F2, false)
	for device in range(5):
		game._join_controller(device)
	await process_frame
	await process_frame
	_expect(
		game.bindings.size() == 4 and game.chairs.size() == 4,
		"Controller joins must cap at four independent chairs"
	)
	game._on_device_connection(0, false)
	_expect(
		game.bindings[0].device == LocalInput.KEYBOARD_ONE,
		"A disconnected P1 controller must restore keyboard steering"
	)


func _test_collisions() -> void:
	var game := GAME.instantiate() as GameSession
	root.add_child(game)
	game.set_physics_process(false)
	var first := game.chairs[0]
	var second := game.chairs[1]
	for chair in game.chairs:
		chair.active = false
		chair.spraying = false
		chair.rotation = 0
		chair.linear_velocity = Vector2.ZERO
		chair.angular_velocity = 0
	await physics_frame
	first.position = Vector2(500, 400)
	second.position = Vector2(620, 424)
	first.linear_velocity = Vector2(300, 0)
	var feedback := {"hits": 0, "strength": 0.0}
	first.bumped.connect(
		func(impulse: Vector2) -> void:
			feedback.hits += 1
			feedback.strength = maxf(feedback.strength, impulse.length())
	)
	var target_speed := 0.0
	var spin := 0.0
	var squash := 0.0
	var compression := 0.0
	var model: ChairModel = first.get_node("Visuals").get("_model")
	for frame in 65:
		await physics_frame
		target_speed = maxf(target_speed, second.linear_velocity.x)
		spin = maxf(spin, maxf(absf(first.angular_velocity), absf(second.angular_velocity)))
		squash = maxf(squash, first.impact)
		compression = maxf(compression, 0.49 - model.office_chair.seat_rig.position.y)
	_expect(target_speed > 60, "A chair collision must transfer momentum to the other chair")
	_expect(spin > 0.15, "An off-centre collision must produce real rigid-body rotation")
	_expect(
		feedback.hits > 0 and squash > 0.1, "Contact impulses must trigger physical bump feedback"
	)
	_expect(compression > 0.005, "A physical impact must compress the visual seat suspension")
	second.freeze = true
	second.position = Vector2(500, 300)
	first.position = Vector2(
		game.stage.world_bounds.end.x - 52, game.stage.world_bounds.get_center().y
	)
	first.rotation = 0
	first.angular_velocity = 0
	first.linear_velocity = Vector2(300, 0)
	var bounced := false
	var rocking := 0.0
	for frame in 30:
		await physics_frame
		bounced = bounced or first.linear_velocity.x < -100
		rocking = maxf(rocking, model.office_chair.seat_rig.rotation.length())
	_expect(bounced, "A fast wall impact must produce a substantial physical rebound")
	_expect(rocking > 0.04, "Wall impacts must visibly rock the suspended chair seat")
	for frame in 60:
		await physics_frame
	_expect(first.impact < 0.01, "Impact squash must settle after the collision")
	_expect(
		model.office_chair.seat_rig.rotation.length() < 0.01,
		"Chair rocking must settle back onto its planted wheel base"
	)
	game.queue_free()
	await process_frame


func _test_endurance() -> void:
	var game := GAME.instantiate() as GameSession
	root.add_child(game)
	game.bindings[0].device = LocalInput.CPU
	var initial_id := game.chairs[0].get_instance_id()
	var always_spraying: bool = true
	var contained: bool = true
	var saw_motion: bool = false
	var saw_turning: bool = false
	for frame in 2400:
		await physics_frame
		for chair in game.chairs:
			always_spraying = always_spraying and chair.spraying
			contained = contained and game.stage.world_bounds.grow(2.0).has_point(chair.position)
			saw_motion = saw_motion or chair.linear_velocity.length() > 80.0
			saw_turning = saw_turning or absf(chair.angular_velocity) > 0.5
	_expect(always_spraying, "Both extinguishers must remain on throughout 40 simulated seconds")
	_expect(contained, "Long-running physics must remain inside the unframed map")
	_expect(saw_motion and saw_turning, "AI must navigate using the same turning physics")
	_expect(
		game.chairs[0].get_instance_id() == initial_id,
		"Sandbox must not auto-eliminate or reset players"
	)
	_expect(get_nodes_in_group("chairs").size() == 2, "Long-running play must not leak bodies")
	game.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
