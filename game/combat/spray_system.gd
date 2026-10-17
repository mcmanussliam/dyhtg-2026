class_name SpraySystem
extends RefCounted
## Applies continuous jet force. The same wall query limits the visual jet length.


func apply(source: Chair, chairs: Array[Chair], delta: float) -> void:
	if not source.active or not source.spraying or source.jet_strength <= 0 or delta <= 0.0:
		return
	var forward := Vector2.from_angle(source.aim_angle)
	var origin := source.global_position
	var query := PhysicsRayQueryParameters2D.create(
		origin, origin + forward * source.tuning.spray_range, 1
	)
	var hit := source.get_world_2d().direct_space_state.intersect_ray(query)
	var reach := source.tuning.spray_range
	if not hit.is_empty():
		reach = origin.distance_to(hit.position)
		if hit.collider is OfficeProp:
			hit.collider.push(
				forward * source.tuning.push_force * source.jet_strength * 0.25 * delta,
				hit.position - hit.collider.global_position
			)
	source.spray_reach = reach
	for other in chairs:
		if other == source or not other.active or other.falling:
			continue
		var offset := other.global_position - origin
		var distance := offset.length()
		if distance < 0.01 or distance > reach:
			continue
		if forward.dot(offset / distance) < cos(deg_to_rad(source.tuning.half_angle_degrees)):
			continue
		var obstruction := PhysicsRayQueryParameters2D.create(origin, other.global_position, 1)
		if not source.get_world_2d().direct_space_state.intersect_ray(obstruction).is_empty():
			continue
		var falloff := lerpf(1.0, 0.55, distance / source.tuning.spray_range)
		other.apply_central_impulse(
			forward * source.tuning.push_force * source.jet_strength * falloff * delta
		)
