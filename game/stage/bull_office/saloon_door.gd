class_name SaloonDoor
extends Node3D
## Twin hinged leaves. The stage drives the spring animation on its physics clock.

var _leaves: Array[Node3D] = []
var _hold := 0.0
var _angle := 0.0
var _angular_speed := 0.0


func build() -> void:
	var wood := ModelGeometry.material(Color("a47a51"), 0, 0.9)
	var trim := ModelGeometry.material(Color("725038"), 0, 0.9)
	var metal := ModelGeometry.material(Color("b89b63"), 0.35, 0.7)
	ModelGeometry.box(
		self, Vector3(0, 1.4, 0), Vector3(3.3, 2.8, 0.04), ModelGeometry.material(Color("1b242a"))
	)
	for side in [-1.0, 1.0]:
		ModelGeometry.box(self, Vector3(side * 1.72, 1.4, 0.08), Vector3(0.15, 2.8, 0.20), trim)
		var hinge := Node3D.new()
		hinge.position = Vector3(side * 1.62, 0, 0.22)
		add_child(hinge)
		_leaves.append(hinge)
		for index in 7:
			var x := (index + 0.5) * 1.55 / 7
			var top := 1.9 + sin((index + 0.5) * PI / 7) * 0.18
			ModelGeometry.cushion(
				hinge,
				Vector3(-side * x, (top + 0.60) * 0.5, 0),
				Vector3(0.205, top - 0.60, 0.10),
				0.015,
				wood
			)
		for height in [0.82, 1.64]:
			ModelGeometry.box(
				hinge, Vector3(-side * 0.78, height, 0.07), Vector3(1.54, 0.09, 0.06), trim
			)
			ModelGeometry.cylinder(
				self,
				Vector3(side * 1.62, height - 0.07, 0.22),
				Vector3(side * 1.62, height + 0.07, 0.22),
				0.055,
				metal
			)

		StaticModelBatcher.batch(hinge)


func open_for(seconds: float) -> void:
	_hold = maxf(_hold, seconds)


func tick(delta: float) -> void:
	_hold = maxf(0, _hold - delta)
	var target := 1.25 if _hold > 0 else 0.0
	# Bounded substeps keep the spring stable during tooling and fast-forward.
	var remaining := delta
	while remaining > 0:
		var step := minf(remaining, 1.0 / 60)
		_angular_speed += ((target - _angle) * 28 - _angular_speed * 6) * step
		_angle += _angular_speed * step
		remaining -= step
	for index in _leaves.size():
		_leaves[index].rotation.y = -_angle if index == 0 else _angle
