extends RefCounted
## Stage geometry and future hazard seams, independent of match scoring.

const CIRCLE = preload("res://game/stage/a_floor_in_the_crack/a_floor_in_the_crack.tscn")
const DEFINITION = preload("res://game/stage/a_floor_in_the_crack/a_floor_in_the_crack.tres")


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
	check.call(DEFINITION.id == &"a_floor_in_the_crack", "First map has its own stable identity")
	var edge: Vector2 = stage.to_global(stage.floor_outline()[0])
	check.call(stage.has_support(edge), "Angular floor vertex retains support")
	check.call(not stage.has_support(Vector2(1170, 422)), "Past circle edge loses support")
	check.call(stage.elimination_reason(Vector2(1170, 422)) == &"fall", "Circle loss is falling")
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
	var shape := collision.shape as ConcavePolygonShape3D
	check.call(shape != null, "Angular stage uses matching static triangle collision")
	var column := platform.get_node("ColumnSurface") as MeshInstance3D
	var sides := platform.get_node("ColumnCollision") as CollisionShape3D
	var bounds := column.mesh.get_aabb()
	check.call(
		sides.shape is ConcavePolygonShape3D and sides.shape.get_faces() == column.mesh.get_faces(),
		"Rough column collision follows the exact rendered triangles"
	)
	var floor := platform.get_node("FloorSurface") as MeshInstance3D
	var floor_faces := floor.mesh.get_faces()
	var rim_matches := true
	var authored: PackedVector2Array = stage.floor_outline()
	for point in floor_faces:
		var local: Vector2 = Vector2(point.x, point.z) * 43.0 + stage.get("center")
		if local.distance_to(stage.get("center")) < 0.01:
			continue
		var nearest := INF
		for vertex in authored:
			nearest = minf(nearest, local.distance_to(vertex))
		rim_matches = rim_matches and nearest < 0.005
	check.call(rim_matches, "Rendered angular floor vertices match authoritative support")
	var triangles_supported := true
	for index in range(0, floor_faces.size(), 3):
		var midpoint := (floor_faces[index] + floor_faces[index + 1] + floor_faces[index + 2]) / 3.0
		triangles_supported = (
			triangles_supported
			and stage.has_support(
				stage.to_global(Vector2(midpoint.x, midpoint.z) * 43.0 + stage.get("center"))
			)
		)
	check.call(triangles_supported, "Floor triangles never bridge unsupported chips")
	check.call(
		is_zero_approx(platform.position.y + bounds.end.y),
		"Rough foundation retains the aligned playable rim"
	)
	check.call(
		bounds.size.y >= 20.0 and platform.position.y + bounds.position.y <= -20,
		"Rough column collision extends deep into the void"
	)
	await tree.physics_frame
	var matched_support := true
	var polygon: PackedVector2Array = stage.floor_outline()
	for index in polygon.size():
		var first := polygon[index]
		var next := polygon[(index + 1) % polygon.size()]
		var edge_direction := next - first
		var outward := Vector2(edge_direction.y, -edge_direction.x).normalized()
		for inset in [-8.0, 8.0]:
			var point := stage.to_global((first + next) * 0.5 + outward * inset)
			var surface := Vector3(point.x / 43.0, 0.0, point.y / 43.0)
			var ray := PhysicsRayQueryParameters3D.create(
				surface + Vector3.UP, surface + Vector3.DOWN
			)
			var hit := platform.get_world_3d().direct_space_state.intersect_ray(ray)
			matched_support = matched_support and stage.has_support(point) == (inset < 0.0)
			matched_support = matched_support and (not hit.is_empty()) == stage.has_support(point)
	check.call(matched_support, "Physical support matches every cut edge after translation")
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
	rules.start_round()
	var before := rules.danger_radius
	await tree.physics_frame
	await tree.physics_frame
	check.call(rules.danger_radius < before, "Stage hazards advance on the live physics clock")
	rules.stop_round()
	rules.queue_free()
	await tree.process_frame
	var replacement := CIRCLE.instantiate() as ArenaStage
	tree.root.add_child(replacement)
	check.call(not replacement.round_running, "Replacement stage starts with hazards stopped")
	replacement.queue_free()
	await tree.process_frame
