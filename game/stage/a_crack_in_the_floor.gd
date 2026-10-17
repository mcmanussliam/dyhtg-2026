@tool
class_name PitOfficeStage
extends OfficeStage
## An office surrounding a pit. One sampled outline supplies support and the 3D rim.

@export var hole_radius := 285.0

var _outline := PackedVector2Array()
var _outline_radius := -1.0
var _erosion: CrumblingEdge
var _fracture_view: FractureView
var _world: Node3D
var _units := 1.0 / RenderStyle.PIXELS_PER_UNIT
var _carpets: Array[Dictionary] = []
var _floor_material := ModelGeometry.material(Color("2e4055"))
var _side_material: ShaderMaterial


func _ready() -> void:
	super._ready()
	if not Engine.is_editor_hint():
		_erosion = CrumblingEdge.new()
		_erosion.configure(hole_radius, half_size.length() + 80, true)


func edge_changed() -> bool:
	return _erosion != null and _erosion.revision > 0


func pit_radius(world_point: Vector2) -> float:
	return _erosion.radius_at(to_local(world_point) - center) if edge_changed() else hole_radius


func hole_outline() -> PackedVector2Array:
	if edge_changed():
		return _erosion.outline
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
		and point.length() >= pit_radius(world_point) + margin
	)


func safe_target(world_point: Vector2, margin: float = 90.0) -> Vector2:
	if edge_changed():
		return _remaining_floor_target(world_point, margin)
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
	if not edge_changed():
		return is_safe(destination, margin) and nearest.length() >= hole_radius + margin
	if not is_safe(destination, margin):
		return false
	# A receding bank can put a chair inside its safety margin. Permit a route
	# that steadily regains clearance; rejecting its starting point traps it there.
	var clearance := minf(margin, start.length() - pit_radius(from)) - 0.5
	for index in range(1, 9):
		var point := from.lerp(destination, index / 8.0)
		if not is_safe(point, clearance):
			return false
		clearance = minf(margin, (to_local(point) - center).length() - pit_radius(point)) - 0.5
	return true


func recovery_target(from: Vector2, _predicted: Vector2, margin: float) -> Vector2:
	# Brake toward the bank beneath the chair, never toward a prediction across the hole.
	return safe_target(from, margin)


func navigation_target(from: Vector2, destination: Vector2, margin: float) -> Vector2:
	var goal := safe_target(destination, margin)
	var local_from := to_local(from) - center
	var local_goal := to_local(goal) - center
	var clearance := pit_radius(from) + clampf(margin, 45, 105)
	var nearest := Geometry2D.get_closest_point_to_segment(Vector2.ZERO, local_from, local_goal)
	if nearest.length() < clearance:
		var angle := wrapf(local_goal.angle() - local_from.angle(), -PI, PI)
		var waypoint := local_from.angle() + signf(angle) * minf(absf(angle), 0.48)
		var point := safe_target(
			to_global(center + Vector2.from_angle(waypoint) * (clearance + 65)), margin
		)
		return point if is_path_safe(from, point, 10) else safe_target(from, margin)
	return goal


func attack_position(opponent: Vector2) -> Vector2:
	var offset := to_local(opponent) - center
	if offset.length() > pit_radius(opponent) + 190:
		return safe_target(opponent, 40)
	var outward := offset.normalized() if offset.length_squared() > 1 else Vector2.RIGHT
	return safe_target(to_global(center + offset + outward * 110), 55)


func open_floor_target(point: Vector2) -> Vector2:
	var outward := (to_local(point) - center).normalized()
	return safe_target(to_global(center + outward * (pit_radius(point) + 165)), 45)


func has_push_angle(attacker: Vector2, opponent: Vector2) -> bool:
	var outward := (opponent - to_global(center)).normalized()
	return (attacker - opponent).dot(outward) > -15


func spawn_pose(index: int, count: int) -> Transform2D:
	var angle := PI + TAU * index / maxi(count, 1)
	var direction := Vector2.from_angle(angle)
	# Initial thrust follows the ring rather than driving directly into the pit.
	return Transform2D(angle - PI / 2, to_global(center + direction * (hole_radius + 120.0)))


func create_presentation(parent: Node3D, units_per_pixel: float) -> void:
	_world = parent
	_units = units_per_pixel
	_side_material = ShaderMaterial.new()
	_side_material.shader = preload("res://game/stage/cylinder.gdshader")
	_side_material.set_shader_parameter("fade_start", 0.5)
	_side_material.set_shader_parameter("fade_end", 3.5)
	_refresh_geometry()
	_create_office_presentation(parent, units_per_pixel)
	_fracture_view = FractureView.new()
	var room := PackedVector2Array(
		[
			-half_size,
			Vector2(half_size.x, -half_size.y),
			half_size,
			Vector2(-half_size.x, half_size.y)
		]
	)
	_fracture_view.configure(self, parent, center, units_per_pixel, 4.0, _side_material, room)


func tick_hazards(delta: float) -> void:
	if not round_running or _erosion == null:
		return
	if _erosion.advance(delta):
		if is_instance_valid(_world):
			_refresh_geometry()
			for carpet in _carpets:
				_create_carpet(_world, _units, carpet.area, carpet.colour, carpet.label)
		for prop in $Furniture.get_children():
			if prop is OfficeProp:
				prop.release_for_fracture(self, _erosion.fallen, center)
	if _fracture_view != null:
		_fracture_view.refresh(_erosion, true)


func stop_round() -> void:
	super.stop_round()
	if _fracture_view != null:
		_fracture_view.set_active(false)


func _refresh_geometry() -> void:
	_update_surface(
		"OfficeFloor",
		FractureGeometry.pit_floor(hole_outline(), half_size, _units),
		_floor_material
	)
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outline := hole_outline()
	var has_sides := false
	for index in outline.size():
		var line := _clip_wall(outline[index], outline[(index + 1) % outline.size()])
		if line.is_empty():
			continue
		has_sides = true
		var a := line[0] * _units
		var b := line[1] * _units
		var inward := -(line[1] - line[0]).orthogonal().normalized()
		for point in [
			Vector3(a.x, 0, a.y),
			Vector3(b.x, -4, b.y),
			Vector3(a.x, -4, a.y),
			Vector3(a.x, 0, a.y),
			Vector3(b.x, 0, b.y),
			Vector3(b.x, -4, b.y)
		]:
			sides.set_normal(Vector3(inward.x, 0, inward.y))
			sides.add_vertex(point)
	_update_surface("PitWalls", sides.commit() if has_sides else ArrayMesh.new(), _side_material)


func _update_surface(label: String, mesh: ArrayMesh, material: Material) -> void:
	var body := _world.get_node_or_null(label) as StaticBody3D
	if body == null:
		body = StaticBody3D.new()
		body.name = label
		if label == "OfficeFloor":
			body.add_to_group("stage_floor")
		_world.add_child(body)
		var visual := MeshInstance3D.new()
		visual.name = "Surface"
		visual.material_override = material
		body.add_child(visual)
		var collision := CollisionShape3D.new()
		collision.name = "SurfaceCollision"
		body.add_child(collision)
	var point := to_global(center) * _units
	body.position = Vector3(point.x, 0, point.y)
	body.rotation.y = -global_rotation
	body.get_node("Surface").mesh = mesh
	body.get_node("SurfaceCollision").shape = (
		mesh.create_trimesh_shape() if mesh.get_surface_count() > 0 else null
	)


func _create_carpet(
	parent: Node3D, units: float, area: Rect2, colour: Color, label: String
) -> void:
	if not _carpets.any(func(item: Dictionary): return item.label == label):
		_carpets.append({"area": area, "colour": colour, "label": label})
	var region := area.intersection(
		Rect2(center - half_size + Vector2.ONE * 16, half_size * 2 - Vector2.ONE * 32)
	)
	var carpet := parent.get_node_or_null(label) as MeshInstance3D
	if carpet == null:
		carpet = ModelGeometry.instance(
			parent, ArrayMesh.new(), Vector3.ZERO, ModelGeometry.material(colour, 0, 1)
		)
		carpet.name = label
		carpet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	carpet.mesh = FractureGeometry.pit_region(
		hole_outline(), Rect2(region.position - center, region.size), units
	)
	var point := to_global(center) * units
	carpet.position = Vector3(point.x, 0.004, point.y)
	carpet.rotation.y = -global_rotation


func _remaining_floor_target(world_point: Vector2, margin: float) -> Vector2:
	var point := to_local(world_point) - center
	var best := Vector2.ZERO
	var distance := INF
	for index in 24:
		var angle := point.angle() + (index / 2 + 1) * (1 if index % 2 == 0 else -1) * TAU / 24
		var direction := Vector2.from_angle(angle) if index > 0 else point.normalized()
		if direction.is_zero_approx():
			direction = Vector2.RIGHT
		var outer := _outer(direction).length()
		var inner := _erosion.radius_at(direction)
		if outer - inner < 25:
			continue
		var inset := minf(margin, (outer - inner) * 0.4)
		var candidate := direction * clampf(point.length(), inner + inset, outer - inset)
		var score := candidate.distance_squared_to(point)
		if score < distance:
			distance = score
			best = candidate
	return to_global(center + best)


func _clip_wall(a: Vector2, b: Vector2) -> PackedVector2Array:
	var start := 0.0
	var end := 1.0
	var delta := b - a
	for axis in 2:
		if absf(delta[axis]) < 0.00001:
			if absf(a[axis]) > half_size[axis]:
				return PackedVector2Array()
		else:
			var first := (-half_size[axis] - a[axis]) / delta[axis]
			var last := (half_size[axis] - a[axis]) / delta[axis]
			start = maxf(start, minf(first, last))
			end = minf(end, maxf(first, last))
	if start >= end:
		return PackedVector2Array()
	return PackedVector2Array([a.lerp(b, start), a.lerp(b, end)])


func _outer(direction: Vector2) -> Vector2:
	var factor := minf(
		half_size.x / maxf(absf(direction.x), 0.001), half_size.y / maxf(absf(direction.y), 0.001)
	)
	return direction * factor
