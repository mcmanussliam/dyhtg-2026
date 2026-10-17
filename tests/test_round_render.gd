extends RefCounted
## Shared-world depth, floor alignment and native falling physics regressions.

const ROUND = preload("res://game/round/round.tscn")
const STAGE = preload("res://game/stage/a_floor_in_the_crack.tres")
const SCALE = 43.0


func run(tree: SceneTree, check: Callable) -> void:
	var state := MatchState.new()
	state.configure(MatchConfig.new())
	var round_scene := ROUND.instantiate() as RoundController
	round_scene.configure(state.participants, STAGE, 1, 5)
	tree.root.add_child(round_scene)
	round_scene.set_physics_process(false)
	await tree.process_frame
	await tree.process_frame
	var view := round_scene.presentation
	check.call(not view.world.visible, "Black introduction omits hidden arena rendering")
	var platform := view.world.get_node("CirclePlatform") as StaticBody3D
	var camera := view.world.get_node("ArenaCamera") as Camera3D
	var floor_surface := platform.get_node("FloorSurface") as MeshInstance3D
	var floor_material := floor_surface.material_override as StandardMaterial3D
	check.call(
		floor_material != null and floor_material.albedo_texture == null,
		"Office floor uses one flat material without a surface texture"
	)
	check.call(
		(
			view.world.get_node_or_null("FrontDesk") != null
			and view.world.get_node_or_null("RearDesk") != null
			and view.world.get_node_or_null("Cabinet") != null
		),
		"Office level instantiates sparse reusable furniture"
	)
	check.call(
		round_scene.stage.get_node("Furniture").get_child_count() >= 18,
		"Office includes furnished workstations, service storage and a complete lounge"
	)
	await tree.physics_frame
	var clear_spawns := true
	for index in 4:
		var footprint := CapsuleShape2D.new()
		footprint.radius = 23.0 * round_scene.stage.content_scale
		footprint.height = 60.0 * round_scene.stage.content_scale
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = footprint
		query.transform = (
			round_scene.stage.spawn_pose(index, 4) * Transform2D(PI / 2.0, Vector2.ZERO)
		)
		query.collision_mask = 1
		clear_spawns = (
			clear_spawns
			and round_scene.get_world_2d().direct_space_state.intersect_shape(query).is_empty()
		)
	check.call(clear_spawns, "All four starting chairs have furniture clearance")
	var shared := true
	var aligned := true
	for chair in round_scene.chairs:
		var visuals := chair.get_node("Visuals")
		var rig: Node3D = visuals.get("_rig")
		shared = shared and visuals.get("_viewport") == view.viewport
		shared = shared and rig.get_world_3d() == platform.get_world_3d()
		shared = shared and visuals.get_node_or_null("RenderedCharacter") == null
		var expected := Vector3(chair.position.x / SCALE, 0, chair.position.y / SCALE)
		aligned = aligned and rig.global_position.is_equal_approx(expected)
		var projected := camera.unproject_position(expected)
		var logical_size := view.viewport.get_visible_rect().size
		var ground := logical_size * 0.5
		var focus := round_scene.stage.to_global(round_scene.stage.view_focus)
		var pixel_scale := logical_size.x / round_scene.stage.view_width
		ground += (
			(chair.global_position - focus)
			* Vector2(1.0, RenderStyle.GAME_CAMERA_ELEVATION)
			* pixel_scale
		)
		aligned = aligned and projected.distance_to(ground) < 0.1
	check.call(view.viewport == tree.root, "Gameplay uses the native main 3D viewport")
	check.call(shared, "Round chairs and platform share one depth-tested 3D world")
	check.call(aligned, "Chair ground positions match the orthographic stage projection")
	var chair_shape := round_scene.chairs[0].get_node("CollisionShape2D").shape as CapsuleShape2D
	var chair_model := round_scene.chairs[0].get_node("Visuals").get("_model") as ChairModel
	check.call(
		(
			is_equal_approx(chair_shape.radius, 23.0 * round_scene.stage.content_scale)
			and chair_model.scale.is_equal_approx(Vector3.ONE * round_scene.stage.content_scale)
		),
		"Larger stage characters keep rendered models and collision footprints aligned"
	)
	check.call(
		(
			is_equal_approx(round_scene.stage.get("radius"), 480.0)
			and is_equal_approx(round_scene.stage.view_width, 1380.0)
		),
		"Closer camera retains the same physical cutout size"
	)
	var collider := platform.get_node("ColumnCollision") as CollisionShape3D
	var column := platform.get_node("ColumnSurface") as MeshInstance3D
	check.call(
		is_zero_approx(platform.position.y + column.mesh.get_aabb().end.y),
		"Angular platform top and grounded chair origins share zero height"
	)
	check.call(
		(
			collider.shape is ConcavePolygonShape3D
			and collider.shape.get_faces() == column.mesh.get_faces()
		),
		"Angular stage physics follows the rendered foundation exactly"
	)
	await tree.physics_frame
	var surface := Vector3(platform.position.x, 0.0, platform.position.z)
	var ray := PhysicsRayQueryParameters3D.create(
		surface + Vector3.UP * 3.0, surface + Vector3.DOWN
	)
	var hit := platform.get_world_3d().direct_space_state.intersect_ray(ray)
	check.call(
		not hit.is_empty() and hit.collider == platform, "Platform is a real 3D physics support"
	)
	await _test_fall(tree, check, round_scene, platform)
	var world_ref: WeakRef = weakref(view.world)
	var viewport_ref: WeakRef = weakref(view.viewport)
	round_scene.queue_free()
	await tree.process_frame
	await tree.process_frame
	check.call(
		world_ref.get_ref() == null, "Round cleanup releases shared 3D world and falling bodies"
	)
	check.call(
		viewport_ref.get_ref() == tree.root,
		"Round uses the persistent native main viewport without owning UI rendering"
	)


func _test_fall(
	tree: SceneTree, check: Callable, round_scene: RoundController, platform: StaticBody3D
) -> void:
	var chair := round_scene.chairs[0]
	var polygon: PackedVector2Array = round_scene.stage.floor_outline()
	var far_edge := Vector2.INF
	var outward := Vector2.UP
	for index in polygon.size():
		var first := polygon[index]
		var next := polygon[(index + 1) % polygon.size()]
		var midpoint := (first + next) * 0.5
		if first.distance_to(next) > 40 and midpoint.y < far_edge.y:
			far_edge = midpoint
			var direction := next - first
			outward = Vector2(direction.y, -direction.x).normalized()
	chair.global_position = round_scene.stage.to_global(far_edge + outward * 12)
	chair.linear_velocity = outward * 100
	chair.angular_velocity = 1.5
	await tree.process_frame
	await tree.process_frame
	chair.eliminate(&"fall")
	await tree.process_frame
	await tree.process_frame
	var visuals := chair.get_node("Visuals")
	var body: RigidBody3D = visuals.get("_fall_body")
	check.call(is_instance_valid(body), "Ring-out creates a native falling rigid body")
	if not is_instance_valid(body):
		return
	check.call(
		body.get_world_3d() == platform.get_world_3d(),
		"Fallen body keeps platform depth and collision in the shared world"
	)
	check.call(
		not (visuals.get("_shadow") as MeshInstance3D).visible,
		"Falling chair loses its floor shadow"
	)
	check.call(
		not (visuals.get("_spray") as Node3D).visible,
		"Falling chair stops its extinguisher presentation"
	)
	var collider_count := 0
	for node in body.get_children():
		if node is CollisionShape3D:
			collider_count += 1
	check.call(collider_count >= 2, "Falling assembly has body and chair-base collision shapes")
	body.contact_monitor = true
	body.max_contacts_reported = 8
	var touched := [false]
	body.body_entered.connect(
		func(other: Node) -> void:
			if other == platform:
				touched[0] = true
	)
	var before_pause := body.global_transform
	tree.paused = true
	await tree.create_timer(0.05, true).timeout
	check.call(
		body.global_transform.is_equal_approx(before_pause),
		"Pause stops native falling-body simulation"
	)
	tree.paused = false
	var initial_height := body.position.y
	var tipped := false
	for frame in 90:
		await tree.physics_frame
		tipped = tipped or Vector2(body.angular_velocity.x, body.angular_velocity.z).length() > 0.1
	check.call(touched[0], "Overhanging chair base contacts the physical platform edge")
	check.call(tipped, "Platform edge contact tips the unsupported falling assembly")
	check.call(
		body.position.y < initial_height - 1.0, "Gravity drops the chair visibly below the platform"
	)
	check.call(
		body.linear_velocity.y < -1.0, "Falling body accelerates downward under real gravity"
	)
