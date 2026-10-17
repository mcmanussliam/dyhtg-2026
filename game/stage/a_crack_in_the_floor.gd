@tool
extends ArenaStage
## An office surrounding a pit. One sampled outline supplies support and the 3D rim.

@export var center := Vector2(640, 422)
@export var half_size := Vector2(656, 640)
@export var hole_radius := 285.0

var _outline := PackedVector2Array()
var _outline_radius := -1.0


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for prop in $Furniture.get_children():
		prop.resize_for_stage(content_scale)
	for side in 4:
		var horizontal := side % 2 == 0
		var direction := Vector2.DOWN if horizontal else Vector2.RIGHT
		var extent := half_size.y if horizontal else half_size.x
		var location := center + direction * extent * (1.0 if side < 2 else -1.0)
		var size := (
			Vector2(half_size.x * 2 + 24, 24) if horizontal else Vector2(24, half_size.y * 2)
		)
		var body := StaticBody2D.new()
		body.name = "Wall%d" % side
		body.position = location
		body.collision_layer = 1
		body.collision_mask = 3
		body.physics_material_override = PhysicsMaterial.new()
		body.physics_material_override.bounce = 0.75
		body.physics_material_override.friction = 0.05
		var collision := CollisionShape2D.new()
		collision.shape = RectangleShape2D.new()
		collision.shape.size = size
		body.add_child(collision)
		add_child(body)


func hole_outline() -> PackedVector2Array:
	if _outline_radius != hole_radius:
		_outline = ColumnGeometry.outline(hole_radius)
		_outline_radius = hole_radius
	return _outline


func has_support(world_point: Vector2) -> bool:
	var point := to_local(world_point) - center
	return (
		absf(point.x) <= half_size.x
		and absf(point.y) <= half_size.y
		and not Geometry2D.is_point_in_polygon(point, hole_outline())
	)


func is_safe(world_point: Vector2, margin: float = 0.0) -> bool:
	var point := to_local(world_point) - center
	return (
		absf(point.x) <= half_size.x - margin
		and absf(point.y) <= half_size.y - margin
		and point.length() >= hole_radius + margin
	)


func safe_target(world_point: Vector2, margin: float = 90.0) -> Vector2:
	# A requested margin can exceed the corridor width; cap it to a feasible inset.
	var inset := clampf(margin, 0, (half_size.y - hole_radius) * 0.45)
	var point := (to_local(world_point) - center).clamp(
		-half_size + Vector2.ONE * inset, half_size - Vector2.ONE * inset
	)
	if point.length() < hole_radius + inset:
		point = (
			(point.normalized() if point.length() > 0.01 else Vector2.RIGHT) * (hole_radius + inset)
		)
	return to_global(center + point)


func navigation_target(from: Vector2, destination: Vector2, margin: float) -> Vector2:
	var goal := safe_target(destination, margin)
	var local_from := to_local(from) - center
	var local_goal := to_local(goal) - center
	var clearance := hole_radius + clampf(margin, 45, 105)
	var nearest := Geometry2D.get_closest_point_to_segment(Vector2.ZERO, local_from, local_goal)
	if nearest.length() < clearance:
		var angle := wrapf(local_goal.angle() - local_from.angle(), -PI, PI)
		var waypoint := local_from.angle() + signf(angle) * minf(absf(angle), 0.48)
		return to_global(center + Vector2.from_angle(waypoint) * (clearance + 65))
	return goal


func spawn_pose(index: int, count: int) -> Transform2D:
	var angle := PI + TAU * index / maxi(count, 1)
	var direction := Vector2.from_angle(angle)
	# Initial thrust follows the ring rather than driving directly into the pit.
	return Transform2D(angle - PI / 2, to_global(center + direction * (hole_radius + 120.0)))


func create_presentation(parent: Node3D, units_per_pixel: float) -> void:
	var floor_surface := SurfaceTool.new()
	var sides := SurfaceTool.new()
	floor_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline := hole_outline()
	for index in outline.size():
		var inner_a := outline[index]
		var inner_b := outline[(index + 1) % outline.size()]
		var outer_a := _outer(inner_a)
		var outer_b := _outer(inner_b)
		for point in [inner_a, outer_a, outer_b, inner_a, outer_b, inner_b]:
			var world := to_global(center + point) * units_per_pixel
			floor_surface.set_normal(Vector3.UP)
			floor_surface.add_vertex(Vector3(world.x, 0, world.y))
		# Include rectangle corners between radial samples so no unsupported slivers remain.
		for corner in [
			half_size,
			Vector2(-half_size.x, half_size.y),
			-half_size,
			Vector2(half_size.x, -half_size.y)
		]:
			var angle := fposmod(corner.angle(), TAU)
			var start_angle := fposmod(inner_a.angle(), TAU)
			var end_angle := fposmod(inner_b.angle(), TAU)
			if end_angle <= start_angle:
				end_angle += TAU
			if angle > start_angle and angle < end_angle:
				for point in [outer_a, corner, outer_b]:
					var world := to_global(center + point) * units_per_pixel
					floor_surface.set_normal(Vector3.UP)
					floor_surface.add_vertex(Vector3(world.x, 0, world.y))
		var a := to_global(center + inner_a) * units_per_pixel
		var b := to_global(center + inner_b) * units_per_pixel
		for point in [
			Vector3(a.x, 0, a.y),
			Vector3(b.x, -4, b.y),
			Vector3(a.x, -4, a.y),
			Vector3(a.x, 0, a.y),
			Vector3(b.x, 0, b.y),
			Vector3(b.x, -4, b.y)
		]:
			var inward := -(inner_b - inner_a).orthogonal().normalized()
			sides.set_normal(Vector3(inward.x, 0, inward.y))
			sides.add_vertex(point)
	_add_surface(
		parent, floor_surface.commit(), ModelGeometry.material(Color("2e4055")), "OfficeFloor"
	)
	var side_material := ShaderMaterial.new()
	side_material.shader = preload("res://game/stage/cylinder.gdshader")
	side_material.set_shader_parameter("fade_start", 0.5)
	side_material.set_shader_parameter("fade_end", 3.5)
	_add_surface(parent, sides.commit(), side_material, "PitWalls")
	for side in 4:
		var horizontal := side % 2 == 0
		var direction := Vector2.DOWN if horizontal else Vector2.RIGHT
		var extent := half_size.y if horizontal else half_size.x
		var location := (
			to_global(center + direction * extent * (1.0 if side < 2 else -1.0)) * units_per_pixel
		)
		# Low front/side partitions preserve visibility; rear wall frames the office.
		var height := 2.8 if side == 2 else 0.55
		var box := BoxMesh.new()
		box.size = (
			Vector3(half_size.x * 2 * units_per_pixel + 0.55, height, 0.55)
			if horizontal
			else Vector3(0.55, height, half_size.y * 2 * units_per_pixel)
		)
		var body := StaticBody3D.new()
		parent.add_child(body)
		ModelGeometry.instance(
			body,
			box,
			Vector3(location.x, height / 2, location.y),
			ModelGeometry.material(Color("c8bf92"))
		)
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		shape.shape.size = box.size
		shape.position = Vector3(location.x, height / 2, location.y)
		body.add_child(shape)
	_create_carpet(
		parent, units_per_pixel, Rect2(875, -191, 395, 290), Color("526979"), "StorageCarpet"
	)
	_create_carpet(
		parent, units_per_pixel, Rect2(880, 765, 390, 270), Color("637672"), "LoungeCarpet"
	)
	_create_wall_details(parent, units_per_pixel)
	for prop in $Furniture.get_children():
		var model: Node3D = prop.create_presentation(parent, units_per_pixel)
		if prop.name in [&"DeskA", &"DeskC", &"SideDeskA"]:
			OfficeAccessories.desk(model, Color("b2745f"))
		StaticModelBatcher.batch(model)


func _outer(direction: Vector2) -> Vector2:
	var factor := minf(
		half_size.x / maxf(absf(direction.x), 0.001), half_size.y / maxf(absf(direction.y), 0.001)
	)
	return direction * factor


func _add_surface(parent: Node3D, mesh: Mesh, material: Material, label: String) -> void:
	var body := StaticBody3D.new()
	body.name = label
	if label == "OfficeFloor":
		body.add_to_group("stage_floor")
	parent.add_child(body)
	ModelGeometry.instance(body, mesh, Vector3.ZERO, material)
	var collision := CollisionShape3D.new()
	collision.name = "SurfaceCollision"
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)


func _create_carpet(
	parent: Node3D, units: float, area: Rect2, colour: Color, label: String
) -> void:
	# Cosmetic floor inset: the existing solid office floor remains authoritative.
	var clipped := area.intersection(
		Rect2(center - half_size + Vector2.ONE * 16, half_size * 2 - Vector2.ONE * 32)
	)
	if not clipped.has_area():
		return
	var mesh := PlaneMesh.new()
	mesh.size = clipped.size * units
	var point := to_global(clipped.get_center()) * units
	var carpet := ModelGeometry.instance(
		parent, mesh, Vector3(point.x, 0.004, point.y), ModelGeometry.material(colour, 0, 1)
	)
	carpet.name = label
	carpet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _create_wall_details(parent: Node3D, units: float) -> void:
	for item in [
		["WorkWindowA", 260.0, 1.95, &"window"],
		["WorkWindowB", 500.0, 1.95, &"window"],
		["OfficeDoor", 750.0, 0.0, &"door"],
		["OfficeClock", 835.0, 2.18, &"clock"]
	]:
		var detail := Node3D.new()
		detail.name = item[0]
		var point := to_global(Vector2(item[1], center.y - half_size.y)) * units
		detail.position = Vector3(point.x, item[2], point.y + 0.29)
		parent.add_child(detail)
		match item[3]:
			&"window":
				OfficeWallDetails.window(detail)
			&"door":
				OfficeWallDetails.door(detail)
			&"clock":
				OfficeWallDetails.clock(detail)
		StaticModelBatcher.batch(detail)
