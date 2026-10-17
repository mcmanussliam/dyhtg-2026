@tool
extends StaticBody3D
## Reusable temporary site fence, with a footprint including its stabilising feet.


func _ready() -> void:
	var steel := ModelGeometry.material(Color("77858a"), 0.65, 0.55)
	var wire := ModelGeometry.material(Color("54636a"), 0.55, 0.62)
	var rubber := ModelGeometry.material(Color("303a40"), 0, 0.9)
	var yellow := ModelGeometry.material(Color("c9a653"), 0, 0.85)
	for side in [-1.0, 1.0]:
		ModelGeometry.capsule(
			self, Vector3(side * 1.32, 0.12, 0), Vector3(side * 1.32, 1.35, 0), 0.035, steel
		)
		ModelGeometry.cushion(
			self, Vector3(side * 1.16, 0.07, 0), Vector3(0.38, 0.14, 0.7), 0.035, rubber
		)
	for height in [0.25, 1.32]:
		ModelGeometry.capsule(
			self, Vector3(-1.32, height, 0), Vector3(1.32, height, 0), 0.03, steel
		)
	for index in 17:
		var x := -1.23 + index * 0.154
		ModelGeometry.cylinder(self, Vector3(x, 0.28, 0), Vector3(x, 1.29, 0), 0.009, wire)
	for height in [0.51, 0.77, 1.03]:
		ModelGeometry.cylinder(
			self, Vector3(-1.29, height, 0), Vector3(1.29, height, 0), 0.009, wire
		)
	ModelGeometry.cushion(self, Vector3(0, 0.31, 0.025), Vector3(2.46, 0.18, 0.035), 0.008, yellow)
	for index in 8:
		var stripe := ModelGeometry.cushion(
			self,
			Vector3(-1.06 + index * 0.30, 0.31, 0.047),
			Vector3(0.12, 0.16, 0.007),
			0.003,
			rubber
		)
		stripe.rotation.z = -0.35
