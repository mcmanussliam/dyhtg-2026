@tool
extends ArenaStage
## Angular office cutout with one shared boundary for support, rendering and collisions.

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
@export_range(0.15, 0.70, 0.01) var spawn_radius_ratio: float = 0.40

var _outline := PackedVector2Array()
var _outline_radius := -1.0
var _outline_center := Vector2.INF
var _safe_radius := 0.0
var _outline_revision := -1
var _erosion: CrumblingEdge
var _fracture_view: FractureView
var _world: Node3D
var _units := 1.0 / RenderStyle.PIXELS_PER_UNIT
var _platform: StaticBody3D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_erosion = CrumblingEdge.new()
	_erosion.configure(radius, 35.0, false)
	for prop in $Furniture.get_children():
		if prop is OfficeProp:
			prop.resize_for_stage(content_scale)
			if prop.get_meta("cut_at_edge", false):
				prop.clip_to_polygon(global_transform * floor_outline())


func has_support(world_point: Vector2) -> bool:
	var polygon := floor_outline()
	var point := to_local(world_point)
	if point.distance_squared_to(center) < _safe_radius * _safe_radius:
		return true
	return Geometry2D.is_point_in_polygon(point, polygon)


func is_safe(world_point: Vector2, margin: float = 0.0) -> bool:
	var point := to_local(world_point)
	var polygon := floor_outline()
	var inner := maxf(_safe_radius - maxf(margin, 0.0), 0.0)
	if point.distance_squared_to(center) < inner * inner:
		return true
	if not Geometry2D.is_point_in_polygon(point, polygon):
		return false
	for index in polygon.size():
		var nearest := Geometry2D.get_closest_point_to_segment(
			point, polygon[index], polygon[(index + 1) % polygon.size()]
		)
		if point.distance_squared_to(nearest) < margin * margin:
			return false
	return true


func safe_target(world_point: Vector2, margin: float = 90.0) -> Vector2:
	floor_outline()
	var offset := to_local(world_point) - center
	return to_global(center + offset.limit_length(maxf(_safe_radius - margin, 0.0)))


func floor_outline() -> PackedVector2Array:
	var revision := _erosion.revision if _erosion != null else 0
	if _outline_radius != radius or _outline_center != center or _outline_revision != revision:
		_outline = _erosion.outline.duplicate() if revision > 0 else ColumnGeometry.outline(radius)
		for index in _outline.size():
			_outline[index] += center
		_safe_radius = radius
		for index in _outline.size():
			_safe_radius = minf(
				_safe_radius,
				center.distance_to(
					Geometry2D.get_closest_point_to_segment(
						center, _outline[index], _outline[(index + 1) % _outline.size()]
					)
				)
			)
		_outline_revision = revision
		_outline_radius = radius
		_outline_center = center
	return _outline


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
	draw_colored_polygon(floor_outline(), FLOOR_COLOUR)


func create_presentation(parent: Node3D, units_per_pixel: float) -> void:
	_world = parent
	_units = units_per_pixel
	var centre := to_global(center) * units_per_pixel
	var world_radius := radius * units_per_pixel
	var platform := StaticBody3D.new()
	platform.name = "CirclePlatform"
	platform.add_to_group("stage_floor")
	platform.position = Vector3(centre.x, -12.0, centre.y)
	parent.add_child(platform)
	_platform = platform
	var mesh := ColumnGeometry.build(world_radius, 24.0)
	var wall_material := ShaderMaterial.new()
	wall_material.shader = preload("res://game/stage/cylinder.gdshader")
	var column := ModelGeometry.instance(platform, mesh, Vector3.ZERO, wall_material)
	column.name = "ColumnSurface"
	var collider := CollisionShape3D.new()
	collider.name = "ColumnCollision"
	collider.shape = mesh.create_trimesh_shape()
	platform.add_child(collider)
	var floor_material := ModelGeometry.material(FLOOR_COLOUR, 0.0, 0.95)
	var floor_surface := ModelGeometry.instance(
		platform, ColumnGeometry.floor_mesh(world_radius), Vector3(0, 12.002, 0), floor_material
	)
	floor_surface.name = "FloorSurface"
	_create_carpet(
		parent, units_per_pixel, Rect2(800, 475, 320, 340), Color("637672"), "LoungeCarpet"
	)
	_create_carpet(
		parent, units_per_pixel, Rect2(640, -30, 380, 215), Color("526979"), "StorageCarpet"
	)

	var furniture := get_node_or_null("Furniture")
	if furniture != null:
		for prop in furniture.get_children():
			if prop is OfficeProp:
				if prop.get_meta("cut_at_edge", false):
					prop.clip_to_polygon(global_transform * floor_outline())
				var model: Node3D = prop.create_presentation(parent, units_per_pixel)
				if prop.name in [&"FrontDesk", &"RearDesk2", &"FrontDesk3"]:
					OfficeAccessories.desk(model, Color("b2745f"))
				elif prop.name in [&"Cabinet", &"PrintCabinet"]:
					OfficeAccessories.archive_boxes(model, 1.25)
				StaticModelBatcher.batch(model)

	_fracture_view = FractureView.new()
	_fracture_view.configure(self, parent, center, units_per_pixel, 24.0, wall_material)


func tick_hazards(delta: float) -> void:
	if not round_running or _erosion == null:
		return
	var changed := _erosion.advance(delta)
	if changed:
		floor_outline()
		queue_redraw()
		if is_instance_valid(_platform):
			var points := _erosion.outline.duplicate()
			for index in points.size():
				points[index] *= _units
			var mesh := ColumnGeometry.build_outline(points, 24)
			_platform.get_node("ColumnSurface").mesh = mesh
			_platform.get_node("ColumnCollision").shape = mesh.create_trimesh_shape()
			_platform.get_node("FloorSurface").mesh = ColumnGeometry.floor_outline_mesh(points)
			for label in ["LoungeCarpet", "StorageCarpet"]:
				var carpet := _world.get_node_or_null(label)
				if carpet != null:
					_world.remove_child(carpet)
					carpet.queue_free()
			_create_carpet(
				_world, _units, Rect2(800, 475, 320, 340), Color("637672"), "LoungeCarpet"
			)
			_create_carpet(
				_world, _units, Rect2(640, -30, 380, 215), Color("526979"), "StorageCarpet"
			)
		for prop in $Furniture.get_children():
			if prop is OfficeProp:
				prop.release_for_fracture(self, _erosion.fallen, center)
	if _fracture_view != null:
		_fracture_view.refresh(_erosion, false)


func stop_round() -> void:
	super.stop_round()
	if _fracture_view != null:
		_fracture_view.set_active(false)


func _create_carpet(
	parent: Node3D, units_per_pixel: float, area: Rect2, colour: Color, label: String
) -> void:
	var outline := PackedVector2Array(
		[
			area.position,
			Vector2(area.end.x, area.position.y),
			area.end,
			Vector2(area.position.x, area.end.y)
		]
	)
	var clipped := Geometry2D.intersect_polygons(outline, floor_outline())
	if clipped.is_empty():
		return
	var polygon: PackedVector2Array = clipped[0]
	var triangles := Geometry2D.triangulate_polygon(polygon)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Godot front faces are clockwise when viewed from above.
	for triangle in range(0, triangles.size(), 3):
		for corner in [0, 1, 2]:
			var point := to_global(polygon[triangles[triangle + corner]]) * units_per_pixel
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(point.x, 0.003, point.y))
	var carpet := ModelGeometry.instance(
		parent, surface.commit(), Vector3.ZERO, ModelGeometry.material(colour, 0, 1)
	)
	carpet.name = label
	carpet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
