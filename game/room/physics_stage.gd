class_name PhysicsStage
extends Node2D
## Flat prototype stage. Invisible outer collisions keep continuous-thrust tests visible.

@export var play_bounds := Rect2(28, 112, 1224, 620)


func _ready() -> void:
	var boundaries := Node2D.new()
	boundaries.name = "InvisibleBounds"
	add_child(boundaries)
	var thickness := 48.0
	var start := play_bounds.position
	var end := play_bounds.end
	_add_edge(
		boundaries,
		Rect2(
			start - Vector2(thickness, thickness),
			Vector2(play_bounds.size.x + thickness * 2, thickness)
		)
	)
	_add_edge(
		boundaries,
		Rect2(
			Vector2(start.x - thickness, end.y),
			Vector2(play_bounds.size.x + thickness * 2, thickness)
		)
	)
	_add_edge(
		boundaries, Rect2(start - Vector2(thickness, 0), Vector2(thickness, play_bounds.size.y))
	)
	_add_edge(boundaries, Rect2(Vector2(end.x, start.y), Vector2(thickness, play_bounds.size.y)))


func spawn_position(index: int) -> Vector2:
	var markers := $SpawnPoints.get_children()
	var marker := markers[index % markers.size()] as Marker2D
	return marker.position


func _add_edge(parent: Node2D, area: Rect2) -> void:
	var body := StaticBody2D.new()
	body.position = area.get_center()
	body.collision_layer = 1
	body.collision_mask = 2
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = area.size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
