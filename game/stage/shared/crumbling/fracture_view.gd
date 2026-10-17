class_name FractureView
extends RefCounted
## Sparse presentation updates: warning mesh per fracture, native debris per detached piece.

const MAX_PIECES := 36

var _stage: ArenaStage
var _world: Node3D
var _center := Vector2.ZERO
var _units := 1.0 / RenderStyle.PIXELS_PER_UNIT
var _clip := PackedVector2Array()
var _warning: MeshInstance3D
var _top: ShaderMaterial
var _side: ShaderMaterial
var _depth := 24.0
var _warning_version := -1
var _pieces: Array[FallingStagePiece] = []
var _serial := 0


func configure(
	stage: ArenaStage,
	world: Node3D,
	center: Vector2,
	units: float,
	depth: float,
	sides: ShaderMaterial,
	clip := PackedVector2Array()
) -> void:
	_stage = stage
	_world = world
	_center = center
	_units = units
	_clip = clip
	_depth = depth
	_side = sides
	# Both surfaces share the column's world-depth fade, including map-specific
	# thresholds. Duplicating parameters keeps the blue top independent of grey walls.
	_top = sides.duplicate() as ShaderMaterial
	_top.set_shader_parameter("wall_colour", Color("2e4055"))
	_top.set_shader_parameter("surface_roughness", 0.95)
	_warning = MeshInstance3D.new()
	_warning.name = "FractureWarning"
	_warning.material_override = ModelGeometry.material(Color("66798a"), 0, 0.95)
	_warning.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_world.add_child(_warning)
	_warning.hide()


func refresh(edge: CrumblingEdge, expanding: bool) -> void:
	if edge.warning_revision != _warning_version:
		_warning_version = edge.warning_revision
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var count := 0
		for polygon in edge.warning:
			for clipped in _clipped(polygon):
				count += FractureGeometry.add_polygon(surface, clipped, 0.008, _units)
		_warning.visible = count > 0
		if count > 0:
			_warning.mesh = surface.commit()
			_place(_warning)
	for polygon in edge.fallen:
		for clipped in _clipped(polygon):
			_spawn(clipped, expanding)


func set_active(active: bool) -> void:
	for piece in _pieces:
		if is_instance_valid(piece):
			piece.freeze = not active


func _clipped(polygon: PackedVector2Array) -> Array[PackedVector2Array]:
	if _clip.is_empty():
		var result: Array[PackedVector2Array] = [polygon]
		return result
	return Geometry2D.intersect_polygons(polygon, _clip)


func _place(node: Node3D) -> void:
	var point := _stage.to_global(_center) * _units
	node.position = Vector3(point.x, 0, point.y)
	node.rotation.y = -_stage.global_rotation


func _spawn(polygon: PackedVector2Array, expanding: bool) -> void:
	if polygon.size() < 3 or Geometry2D.triangulate_polygon(polygon).is_empty():
		return
	for index in range(_pieces.size() - 1, -1, -1):
		if not is_instance_valid(_pieces[index]):
			_pieces.remove_at(index)
	if _pieces.size() >= MAX_PIECES:
		var oldest := _pieces.pop_front() as FallingStagePiece
		_world.remove_child(oldest)
		oldest.queue_free()
	var centroid := Vector2.ZERO
	for point in polygon:
		centroid += point
	centroid /= polygon.size()
	var body := FallingStagePiece.new()
	_serial += 1
	body.name = "FallingFloorChunk%d" % _serial
	body.collision_layer = 0
	body.collision_mask = 0
	body.mass = 8
	_world.add_child(body)
	var point := _stage.to_global(_center + centroid) * _units
	body.position = Vector3(point.x, 0, point.y)
	body.rotation.y = -_stage.global_rotation
	ModelGeometry.instance(
		body, FractureGeometry.slab(polygon, _units, _depth, _top, _side), Vector3.ZERO, null
	)
	# Debris does not collide with players. A primitive proxy supplies stable inertia
	# even for the very thin slivers produced by adjacent chips.
	var low := polygon[0]
	var high := polygon[0]
	for vertex in polygon:
		low = low.min(vertex)
		high = high.max(vertex)
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(
		maxf((high.x - low.x) * _units, 0.05), _depth, maxf((high.y - low.y) * _units, 0.05)
	)
	var middle := ((high + low) * 0.5 - centroid) * _units
	collision.position = Vector3(middle.x, -_depth / 2, middle.y)
	body.add_child(collision)
	var outward := (point - _stage.to_global(_center) * _units).normalized()
	var drift := -0.5 if expanding else 0.5
	body.linear_velocity = Vector3(outward.x * drift, -0.15, outward.y * drift)
	body.angular_velocity = Vector3(outward.y, 0.2, -outward.x) * 0.08
	_pieces.append(body)
