extends Node2D
## Carpet floor only. No furniture, windows or obstacle collisions.


func _draw() -> void:
	for row in range(-5, 18):
		for column in range(-1, 18):
			var tile := Rect2(column * 80, row * 80, 80, 80)
			var tint := Color("aeb9b6") if (row + column) % 2 == 0 else Color("b3beba")
			draw_rect(tile, tint)
			draw_rect(tile.grow(-1), Color(0.9, 0.94, 0.91, 0.06), false, 1)
