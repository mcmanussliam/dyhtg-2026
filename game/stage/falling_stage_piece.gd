class_name FallingStagePiece
extends RigidBody3D
## Native gravity/tumbling, with bounded lifetime for offscreen floor and furniture debris.

var lifetime := 7.0
var _age := 0.0


func _physics_process(delta: float) -> void:
	_age += delta
	if global_position.y < -35 or (lifetime > 0 and _age > lifetime):
		queue_free()


func freeze_for_results() -> void:
	freeze = true
