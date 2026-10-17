@tool
class_name PitOfficeStage
extends OfficeStage
## An office surrounding a pit. One sampled outline supplies support and the 3D rim.

@export var hole_radius := 285.0

var _outline := PackedVector2Array()
var _outline_radius := -1.0


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
		absf(point.x) <= half_size.x
		and absf(point.y) <= half_size.y
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


func is_path_safe(from: Vector2, destination: Vector2, margin: float = 0.0) -> bool:
	var start := to_local(from) - center
	var end := to_local(destination) - center
	var nearest := Geometry2D.get_closest_point_to_segment(Vector2.ZERO, start, end)
	return is_safe(destination, margin) and nearest.length() >= hole_radius + margin


func recovery_target(from: Vector2, _predicted: Vector2, margin: float) -> Vector2:
	# Brake toward the bank beneath the chair, never toward a prediction across the hole.
	return safe_target(from, margin)


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


func attack_position(opponent: Vector2) -> Vector2:
	var offset := to_local(opponent) - center
	if offset.length() > hole_radius + 190:
		return safe_target(opponent, 40)
	var outward := offset.normalized() if offset.length_squared() > 1 else Vector2.RIGHT
	return safe_target(to_global(center + offset + outward * 110), 55)


func open_floor_target(point: Vector2) -> Vector2:
	var outward := (to_local(point) - center).normalized()
	return to_global(center + outward * (hole_radius + 165))


func has_push_angle(attacker: Vector2, opponent: Vector2) -> bool:
	var outward := (opponent - to_global(center)).normalized()
	return (attacker - opponent).dot(outward) > -15


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
	_create_office_presentation(parent, units_per_pixel)


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
