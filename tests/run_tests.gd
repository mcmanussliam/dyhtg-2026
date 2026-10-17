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
	_expect(game.get_node_or_null("Fire") == null, "No fire hazard may be instantiated")
	_expect(
		not FileAccess.file_exists("res://game/fire/fire_field.gd"),
		"Unused fire code must be removed"
	)
	_expect(
		game.stage.get_node_or_null("Walls") == null,
		"The stage must not have a visible wall border"
	)
	_expect(
		game.stage.get_node("Floor").polygon[0] == Vector2.ZERO, "Simple floor must fill the view"
	)
	_expect(
		game.chairs[0].colour.get_luminance() > 0.65, "Characters must use a light body palette"
	)
	var face: StyleBoxFlat = game.chairs[0].get_node("Visuals").get("_face_box")
	_expect(
		face.bg_color.get_luminance() > game.chairs[0].colour.get_luminance(),
		"Face panel must be lighter than the body"
	)
	await _test_physics(game)
	await _test_spray(game)
	await _test_session(game)
	game.queue_free()
	await process_frame
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
	_expect(not chair.lock_rotation, "Collisions must be allowed to rotate the chair")
	chair.position = Vector2(600, 420)
	chair.linear_velocity = Vector2.ZERO
	chair.command.turn = 1.0
	for frame in 30:
		chair.step(1.0 / 60.0)
		await physics_frame
	_expect(chair.angular_velocity > 0.5, "Right steering must apply clockwise torque")
	var spin := chair.angular_velocity
	chair.command.turn = 0.0
	for frame in 60:
		chair.step(1.0 / 60.0)
		await physics_frame
	_expect(absf(chair.angular_velocity) < spin, "Steering release must damp angular momentum")
	# Isolate steering direction from wall/contact torque after the drift test.
	chair.position = Vector2(640, 420)
	chair.linear_velocity = Vector2.ZERO
	chair.angular_velocity = 0.0
	await physics_frame
	chair.command.turn = -1.0
	for frame in 30:
		chair.step(1.0 / 60.0)
		await physics_frame
	_expect(chair.angular_velocity < -0.5, "Left steering must apply anticlockwise torque")
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
	chair.position = Vector2(game.stage.play_bounds.end.x - 32, 420)
	chair.rotation = PI
	chair.angular_velocity = 0.0
	chair.linear_velocity = Vector2(400, 0)
	for frame in 45:
		chair.step(1.0 / 60.0)
		await physics_frame
	_expect(
		game.stage.play_bounds.has_point(chair.position), "Invisible edges must retain the chair"
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
			contained = contained and game.stage.play_bounds.grow(2.0).has_point(chair.position)
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
