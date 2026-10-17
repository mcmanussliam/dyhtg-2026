@tool
extends ArenaStage
## Circular office floor with aligned presentation, support and reusable furniture.

const FLOOR_COLOUR := Color("2e4055")

@export var center := Vector2(640, 422):
	set(value):
		center = value
		queue_redraw()
		update_configuration_warnings()
@export_range(120.0, 1200.0, 1.0) var radius: float = 430.0:
	set(value):
		radius = value
		queue_redraw()
		update_configuration_warnings()
@export_range(0.15, 0.70, 0.01) var spawn_radius_ratio: float = 0.43


func has_support(world_point: Vector2) -> bool:
	return to_local(world_point).distance_squared_to(center) <= radius * radius


func is_safe(world_point: Vector2, margin: float = 0.0) -> bool:
	var inset := maxf(radius - maxf(margin, 0.0), 0.0)
	return to_local(world_point).distance_squared_to(center) <= inset * inset


func safe_target(world_point: Vector2, margin: float = 90.0) -> Vector2:
	var offset := to_local(world_point) - center
	return to_global(center + offset.limit_length(maxf(radius - margin, 0.0)))


func spawn_pose(index: int, count: int) -> Transform2D:
	var angle := PI + TAU * float(index) / float(maxi(count, 1))
	var outward := Vector2.from_angle(angle)
	var point := to_global(center + outward * radius * spawn_radius_ratio)
	# The nozzle points outward, so continuous backwards thrust starts inward.
	var heading := (to_global(center + outward) - to_global(center)).angle()
	return Transform2D(heading, point)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if radius <= 120.0:
		warnings.append("Allow enough platform radius for four chairs and their turning paths.")
	for index in 4:
		if not is_safe(spawn_pose(index, 4).origin, 65.0):
			warnings.append("Spawn poses must be safely inside the platform.")
			break
	return warnings


func _draw() -> void:
	# Minimal editor preview; native 3D presentation uses the same flat floor colour.
	draw_circle(center + Vector2(0, 13), radius, Color("45484d"), true, -1.0, true)
	draw_circle(center, radius, FLOOR_COLOUR, true, -1.0, true)


func create_presentation(parent: Node3D, units_per_pixel: float) -> void:
	var centre := to_global(center) * units_per_pixel
	var world_radius := radius * units_per_pixel
	var platform := StaticBody3D.new()
	platform.name = "CirclePlatform"
	platform.position = Vector3(centre.x, -12.0, centre.y)
	parent.add_child(platform)
	var mesh := ColumnGeometry.build(world_radius, 24.0)
	var wall_material := ShaderMaterial.new()
	wall_material.shader = preload("res://game/stage/cylinder.gdshader")
	var column := ModelGeometry.instance(platform, mesh, Vector3.ZERO, wall_material)
	column.name = "ColumnSurface"
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = world_radius
	shape.height = 24.0
	collider.shape = shape
	platform.add_child(collider)
	var floor_material := ModelGeometry.material(FLOOR_COLOUR, 0.0, 0.95)
	var floor_surface := ModelGeometry.instance(
		platform, _floor_disk(world_radius), Vector3(0, 12.0, 0), floor_material
	)
	floor_surface.name = "FloorSurface"

	var furniture := get_node_or_null("Furniture")
	if furniture != null:
		for prop in furniture.get_children():
			if prop is OfficeProp:
				prop.create_presentation(parent, units_per_pixel)


func _floor_disk(world_radius: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_normal(Vector3.UP)
	for index in 256:
		var angle := float(index) * TAU / 256.0
		var next_angle := float(index + 1) * TAU / 256.0
		surface.add_vertex(Vector3.ZERO)
		surface.add_vertex(Vector3(cos(angle), 0, sin(angle)) * world_radius)
		surface.add_vertex(Vector3(cos(next_angle), 0, sin(next_angle)) * world_radius)
	return surface.commit()
