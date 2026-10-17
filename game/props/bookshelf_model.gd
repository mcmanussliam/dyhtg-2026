@tool
extends StaticBody3D
## Office shelves with sparse books and simple flat materials.


func _ready() -> void:
	var wood := ModelGeometry.material(Color("b9a180"), 0.0, 0.78)
	var backing := ModelGeometry.material(Color("8f806d"), 0.0, 0.85)
	ModelGeometry.cushion(self, Vector3(0, 0.825, -0.205), Vector3(1.6, 1.65, 0.04), 0.012, backing)
	for side in [-1.0, 1.0]:
		ModelGeometry.cushion(
			self, Vector3(side * 0.765, 0.825, 0), Vector3(0.07, 1.65, 0.45), 0.016, wood
		)
	for height in [0.07, 0.57, 1.07, 1.61]:
		ModelGeometry.cushion(self, Vector3(0, height, 0), Vector3(1.53, 0.08, 0.45), 0.015, wood)
	var colours: Array[Color] = [Color("728d94"), Color("ba8e7b"), Color("c4b98c"), Color("8c9d87")]
	for shelf in 3:
		var bottom := 0.11 + shelf * 0.5
		for index in 4:
			var height := 0.27 + float((index + shelf) % 3) * 0.035
			var tint := ModelGeometry.material(colours[(index + shelf) % colours.size()], 0.0, 0.88)
			var position := Vector3(
				-0.56 + index * 0.115 + shelf * 0.16, bottom + height * 0.5, 0.015
			)
			ModelGeometry.cushion(self, position, Vector3(0.08, height, 0.30), 0.008, tint)
