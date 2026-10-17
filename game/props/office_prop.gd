@tool
class_name OfficeProp
extends StaticBody2D
## Authored 2D gameplay footprint with a reusable, depth-tested 3D presentation.

const AUTHORING_PIXELS_PER_UNIT := RenderStyle.PIXELS_PER_UNIT

@export var visual_scene: PackedScene


func create_presentation(parent: Node3D, units_per_pixel: float) -> Node3D:
	if visual_scene == null:
		return null
	var model := visual_scene.instantiate() as Node3D
	model.name = name
	parent.add_child(model)
	var unit_scale := AUTHORING_PIXELS_PER_UNIT * units_per_pixel
	var horizontal := Vector3(global_transform.x.x, 0.0, global_transform.x.y) * unit_scale
	var depth := Vector3(global_transform.y.x, 0.0, global_transform.y.y) * unit_scale
	var basis := Basis(horizontal, Vector3.UP * unit_scale, depth)
	var origin := Vector3(global_position.x, 0.0, global_position.y) * units_per_pixel
	model.global_transform = Transform3D(basis, origin)
	return model
