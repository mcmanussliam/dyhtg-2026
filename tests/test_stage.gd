extends RefCounted
## Stage geometry and future hazard seams, independent of match scoring.

const CIRCLE = preload("res://game/stage/a_floor_in_the_crack.tscn")
const DEFINITION = preload("res://game/stage/a_floor_in_the_crack.tres")


class RuleStage:
	extends ArenaStage
	var danger_radius := 100.0
	var has_pit := false

	func _physics_process(delta: float) -> void:
		tick_hazards(delta)

	func has_support(world_point: Vector2) -> bool:
		return not (has_pit and world_point.length() < 20.0)

	func elimination_reason(world_point: Vector2) -> StringName:
		if not has_support(world_point):
			return &"fall"
		return &"danger" if world_point.length() > danger_radius else &""

	func tick_hazards(delta: float) -> void:
		if round_running:
			danger_radius -= delta


func run(tree: SceneTree, check: Callable) -> void:
	var stage := CIRCLE.instantiate() as ArenaStage
	tree.root.add_child(stage)
	check.call(
		DEFINITION.validation_errors().is_empty(), "Circle definition has valid authored data"
	)
	check.call(DEFINITION.id == &"a_floor_in_the_crack", "First map has its own stable identity")
	check.call(
		DEFINITION.display_name == "A Floor in the Crack", "First map displays its authored name"
	)
	check.call(stage.has_support(Vector2(1120, 422)), "Circle edge retains centre support")
	check.call(not stage.has_support(Vector2(1120.01, 422)), "Past circle edge loses support")
	check.call(stage.elimination_reason(Vector2(1121, 422)) == &"fall", "Circle loss is falling")
	check.call(not stage.is_safe(Vector2(1110, 422), 30), "AI inset respects platform edge")
	check.call(
		stage.is_safe(stage.safe_target(Vector2(2000, 422)), 89.9), "AI target clamps safely"
	)
	var valid_spawns := true
	for count in range(2, 5):
		for index in count:
			var pose := stage.spawn_pose(index, count)
			var thrust := -Vector2.from_angle(pose.get_rotation())
			valid_spawns = (
				valid_spawns
				and stage.is_safe(pose.origin, 100)
				and thrust.dot((Vector2(640, 422) - pose.origin).normalized()) > 0.99
			)
	check.call(valid_spawns, "All circle spawns are inset and propel toward centre")
	var presentation := Node3D.new()
	tree.root.add_child(presentation)
	stage.position = Vector2(32, -18)
	stage.create_presentation(presentation, 1.0 / 43.0)
	var platform := presentation.get_node("CirclePlatform") as StaticBody3D
	var collision := platform.get_child(1) as CollisionShape3D
	var shape := collision.shape as CylinderShape3D
	check.call(
		is_equal_approx(shape.radius * 43.0, stage.get("radius")),
		"3D circle support matches authoritative arena radius"
	)
	check.call(
		is_zero_approx(platform.position.y + shape.height * 0.5),
		"3D platform top aligns with chair ground plane"
	)
	var mesh_matches := false
	for child in platform.get_children():
		if child is MeshInstance3D:
			var bounds: AABB = child.mesh.get_aabb()
			if bounds.size.y >= 20.0:
				mesh_matches = (
					is_equal_approx(bounds.size.y, shape.height)
					and is_equal_approx(bounds.size.x * 0.5, shape.radius)
					and is_equal_approx(bounds.size.z * 0.5, shape.radius)
					and is_zero_approx(platform.position.y + bounds.end.y)
				)
	check.call(mesh_matches, "Deep column mesh and physical cylinder share height and radius")
	check.call(shape.height >= 20.0, "First map extends as a deep column below its surface")
	check.call(
		platform.position.y - shape.height * 0.5 <= -20.0,
		"Column collision extends below the visible fall"
	)
	await tree.physics_frame
	var matched_support := true
	var center: Vector2 = stage.get("center")
	var radius: float = stage.get("radius")
	for index in 12:
		var radial := Vector2.from_angle(float(index) * TAU / 12.0)
		for inset in [-8.0, 8.0]:
			var point := stage.to_global(center + radial * (radius + inset))
			var surface := Vector3(point.x / 43.0, 0.0, point.y / 43.0)
			var ray := PhysicsRayQueryParameters3D.create(
				surface + Vector3.UP, surface + Vector3.DOWN
			)
			var hit := platform.get_world_3d().direct_space_state.intersect_ray(ray)
			matched_support = matched_support and stage.has_support(point) == (inset < 0.0)
			matched_support = matched_support and (not hit.is_empty()) == stage.has_support(point)
	check.call(
		matched_support,
		"Physical support matches analytic circle at twelve angles after translation"
	)
	presentation.queue_free()
	stage.queue_free()
	var rules := RuleStage.new()
	tree.root.add_child(rules)
	check.call(
		rules.has_support(Vector2(150, 0)) and rules.elimination_reason(Vector2(150, 0)) != &"",
		"Legal arena region is independent of solid floor support"
	)
	rules.has_pit = true
	check.call(rules.elimination_reason(Vector2.ZERO) == &"fall", "Interior holes lose support")
	rules.tick_hazards(5.0)
	check.call(is_equal_approx(rules.danger_radius, 100), "Hazards do not advance during intro")
	rules.start_round()
	rules.tick_hazards(5.0)
	rules.stop_round()
	rules.tick_hazards(5.0)
	check.call(is_equal_approx(rules.danger_radius, 95), "Hazards advance only during live round")
	rules.process_mode = Node.PROCESS_MODE_PAUSABLE
	rules.start_round()
	var before_pause := rules.danger_radius
	tree.paused = true
	await tree.physics_frame
	await tree.physics_frame
	check.call(
		is_equal_approx(rules.danger_radius, before_pause),
		"Tree pause suspends stage hazard processing"
	)
	tree.paused = false
	await tree.physics_frame
	await tree.physics_frame
	check.call(rules.danger_radius < before_pause, "Stage hazards resume after tree pause")
	rules.stop_round()
	rules.queue_free()
	await tree.process_frame
	var replacement := CIRCLE.instantiate() as ArenaStage
	tree.root.add_child(replacement)
	check.call(not replacement.round_running, "Replacement stage starts with hazards stopped")
	replacement.queue_free()
	await tree.process_frame
