class_name SpawnLayout
extends RefCounted
## Resolve dense rosters once, before bodies exist, against authored prop footprints.


static func poses(stage: ArenaStage, count: int) -> Array[Transform2D]:
	var result: Array[Transform2D] = []
	var blockers := _blockers(stage)
	var clearance := 34.0 * stage.content_scale + 5
	for index in count:
		var preferred := stage.spawn_pose(index, count)
		var chosen := preferred
		var found := false
		# Preserve authored positions whenever they fit. Search locally only for overlaps.
		for ring in 9:
			for step in 1 if ring == 0 else 24:
				var point := preferred.origin
				if ring > 0:
					point += Vector2.from_angle(step * TAU / 24.0) * ring * clearance
				if _clear(stage, point, clearance, result, blockers):
					chosen.origin = point
					found = true
					break
			if found:
				break
		assert(found, "Map has insufficient safe spawn space for %d players" % count)
		result.append(chosen)
	return result


static func _clear(
	stage: ArenaStage,
	point: Vector2,
	clearance: float,
	placed: Array[Transform2D],
	blockers: Array[PackedVector2Array]
) -> bool:
	if not stage.is_spawn_safe(point, clearance):
		return false
	for pose in placed:
		if point.distance_squared_to(pose.origin) < pow(clearance * 2, 2):
			return false
	for polygon in blockers:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return false
		for index in polygon.size():
			var closest := Geometry2D.get_closest_point_to_segment(
				point, polygon[index], polygon[(index + 1) % polygon.size()]
			)
			if point.distance_squared_to(closest) < clearance * clearance:
				return false
	return true


static func _blockers(stage: ArenaStage) -> Array[PackedVector2Array]:
	var polygons: Array[PackedVector2Array] = []
	var furniture := stage.get_node_or_null("Furniture")
	if furniture == null:
		return polygons
	for prop in furniture.get_children():
		if not prop is OfficeProp:
			continue
		var clipped := prop.find_children("*", "CollisionPolygon2D", false, false)
		if not clipped.is_empty():
			for collision in clipped:
				polygons.append(collision.global_transform * collision.polygon)
			continue
		var collision := prop.get_node("CollisionShape2D") as CollisionShape2D
		var polygon := PackedVector2Array()
		if collision.shape is RectangleShape2D:
			var half: Vector2 = collision.shape.size * 0.5
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				polygon.append(collision.to_global(half * corner))
		elif collision.shape is CircleShape2D:
			for index in 24:
				polygon.append(
					collision.to_global(
						Vector2.from_angle(index * TAU / 24) * collision.shape.radius
					)
				)
		if not polygon.is_empty():
			polygons.append(polygon)
	return polygons
