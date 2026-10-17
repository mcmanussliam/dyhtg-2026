class_name PropCollisionBridge
extends AnimatableBody2D
## Native falling furniture remains solid to planar chairs while it intersects their height.
## The proxy follows 3D collider geometry; contact impulses return to the native body.

var _body: RigidBody3D
var _units := 1.0 / RenderStyle.PIXELS_PER_UNIT
var _height := 1.4
var _sources: Array[CollisionShape3D] = []
var _faces: Array[PackedVector3Array] = []
var _bounds: Array[AABB] = []
var _colliders: Array[CollisionShape2D] = []
var _last_pose := Transform3D()
var _initialized := false
var _impulses: Array[Vector2] = []
var _offsets: Array[Vector2] = []


func configure(body: RigidBody3D, units: float, scale_factor: float) -> void:
	_body = body
	_units = units
	_height *= scale_factor
	collision_layer = 1
	collision_mask = 2
	sync_to_physics = false
	name = "FallingFurnitureCollision"
	for child in body.find_children("*", "CollisionShape3D", true, false):
		var source := child as CollisionShape3D
		if source.disabled or source.shape == null:
			continue
		_sources.append(source)
		var mesh := source.shape.get_debug_mesh()
		_faces.append(mesh.get_faces())
		_bounds.append(mesh.get_aabb())
		var collider := CollisionShape2D.new()
		collider.shape = ConvexPolygonShape2D.new()
		collider.disabled = true
		add_child(collider)
		_colliders.append(collider)
	_refresh()


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_body):
		queue_free()
		return
	# Apply outside the 2D contact callback, keeping the two physics servers independent.
	for index in _impulses.size():
		var impulse := _impulses[index] * _units
		var offset := _offsets[index] * _units
		_body.apply_impulse(
			Vector3(impulse.x, 0, impulse.y),
			Vector3(offset.x, _height * 0.5 - _body.global_position.y, offset.y)
		)
	_impulses.clear()
	_offsets.clear()
	_refresh()


func _refresh() -> void:
	constant_linear_velocity = Vector2(_body.linear_velocity.x, _body.linear_velocity.z) / _units
	constant_angular_velocity = -_body.angular_velocity.y
	var pose := _body.global_transform
	if _initialized and pose.is_equal_approx(_last_pose):
		return
	_last_pose = pose
	_initialized = true
	global_transform = Transform2D(0, Vector2(pose.origin.x, pose.origin.z) / _units)
	for index in _sources.size():
		var source := _sources[index]
		var transform := source.global_transform
		var bounds := transform * _bounds[index]
		if bounds.end.y < 0.02 or bounds.position.y > _height:
			_colliders[index].disabled = true
			continue
		var points := PackedVector2Array()
		var faces := _faces[index]
		for triangle in range(0, faces.size(), 3):
			var previous := transform * faces[triangle + 2]
			for corner in 3:
				var point := transform * faces[triangle + corner]
				if point.y >= 0.02 and point.y <= _height:
					points.append(_project(point))
				for plane in [0.02, _height]:
					if (previous.y < plane) != (point.y < plane):
						points.append(
							_project(
								previous.lerp(point, (plane - previous.y) / (point.y - previous.y))
							)
						)
				previous = point
		var hull := Geometry2D.convex_hull(points)
		if hull.size() > 1 and hull[0].is_equal_approx(hull[-1]):
			hull.resize(hull.size() - 1)
		var collider := _colliders[index]
		collider.disabled = hull.size() < 3
		if hull.size() >= 3:
			(collider.shape as ConvexPolygonShape2D).points = hull


func _project(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z) / _units - global_position


func is_movable() -> bool:
	return is_instance_valid(_body) and not _body.freeze


func push(impulse: Vector2, offset: Vector2) -> void:
	if is_movable():
		_impulses.append(impulse)
		_offsets.append(offset)
