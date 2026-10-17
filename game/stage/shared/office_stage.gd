@tool
class_name OfficeStage
extends ArenaStage
## Shared solid office shell, bouncy walls, dressing and reusable furniture.
## Concrete maps own layouts and hazards; this shell does not choose match results.

@export var center := Vector2(640, 422)
@export var half_size := Vector2(656, 640)


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for prop in $Furniture.get_children():
		prop.resize_for_stage(content_scale)
	for side in 4:
		for section in wall_sections(side):
			var body := StaticBody2D.new()
			body.name = "Wall%d" % side
			body.position = section.get_center()
			body.collision_layer = 1
			body.collision_mask = 3
			body.physics_material_override = PhysicsMaterial.new()
			body.physics_material_override.bounce = 0.75
			body.physics_material_override.friction = 0.05
			var collision := CollisionShape2D.new()
			collision.shape = RectangleShape2D.new()
			collision.shape.size = section.size
			body.add_child(collision)
			add_child(body)


## Local footprints shared by planar collisions and native wall geometry.
## Maps with entrances override this rather than covering solid walls with artwork.
func wall_sections(side: int) -> Array[Rect2]:
	var horizontal := side % 2 == 0
	var direction := Vector2.DOWN if horizontal else Vector2.RIGHT
	var extent := half_size.y if horizontal else half_size.x
	var location := center + direction * extent * (1.0 if side < 2 else -1.0)
	var size := Vector2(half_size.x * 2 + 24, 24) if horizontal else Vector2(24, half_size.y * 2)
	return [Rect2(location - size * 0.5, size)]


func wall_height(side: int) -> float:
	# Low front/side partitions preserve visibility; rear wall frames the office.
	return 2.8 if side == 2 else 0.55


func has_support(world_point: Vector2) -> bool:
	var point := to_local(world_point) - center
	return absf(point.x) <= half_size.x and absf(point.y) <= half_size.y


func is_safe(world_point: Vector2, margin: float = 0.0) -> bool:
	var point := to_local(world_point) - center
	return absf(point.x) <= half_size.x - margin and absf(point.y) <= half_size.y - margin


func is_spawn_safe(world_point: Vector2, clearance: float) -> bool:
	# Wall bounces are safe in play, but a spawn footprint must fit inside the room.
	var point := to_local(world_point) - center
	return (
		is_safe(world_point, clearance)
		and absf(point.x) <= half_size.x - clearance
		and absf(point.y) <= half_size.y - clearance
	)


func safe_target(world_point: Vector2, margin: float = 90.0) -> Vector2:
	var inset := clampf(margin, 0, minf(half_size.x, half_size.y) * 0.8)
	return to_global(
		(
			center
			+ (to_local(world_point) - center).clamp(
				-half_size + Vector2.ONE * inset, half_size - Vector2.ONE * inset
			)
		)
	)


func create_presentation(parent: Node3D, units_per_pixel: float) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "OfficeFloor"
	floor_body.add_to_group("stage_floor")
	parent.add_child(floor_body)
	var point := to_global(center) * units_per_pixel
	var mesh := BoxMesh.new()
	mesh.size = Vector3(half_size.x * 2 * units_per_pixel, 0.2, half_size.y * 2 * units_per_pixel)
	ModelGeometry.instance(
		floor_body, mesh, Vector3(point.x, -0.1, point.y), ModelGeometry.material(Color("2e4055"))
	)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = mesh.size
	shape.position = Vector3(point.x, -0.1, point.y)
	floor_body.add_child(shape)
	_create_office_presentation(parent, units_per_pixel)


func _create_office_presentation(parent: Node3D, units_per_pixel: float) -> void:
	for side in 4:
		for section in wall_sections(side):
			var location := to_global(section.get_center()) * units_per_pixel
			var height := wall_height(side)
			var horizontal := side % 2 == 0
			var box := BoxMesh.new()
			box.size = (
				Vector3(
					section.size.x * units_per_pixel + 0.55 - 24 * units_per_pixel, height, 0.55
				)
				if horizontal
				else Vector3(0.55, height, section.size.y * units_per_pixel)
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


func boundary_in_direction(
	world_point: Vector2, direction: Vector2, inset: float = 12.0
) -> Vector2:
	# Slab exit distance in local space keeps the guide correct under stage transforms.
	var point := to_local(world_point)
	var local_direction := to_local(world_point + direction) - point
	var extent := half_size - Vector2.ONE * inset
	var distance := INF
	if absf(local_direction.x) > 0.00001:
		distance = minf(
			distance, (center.x + signf(local_direction.x) * extent.x - point.x) / local_direction.x
		)
	if absf(local_direction.y) > 0.00001:
		distance = minf(
			distance, (center.y + signf(local_direction.y) * extent.y - point.y) / local_direction.y
		)
	if not is_finite(distance) or distance < 0:
		return world_point
	return to_global(point + local_direction * distance)
