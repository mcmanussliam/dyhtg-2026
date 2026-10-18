class_name BugSwarmView
extends MultiMeshInstance3D
## Draws every bug in one call. Travelling bugs are green; colonies turn amber, then red.

const COLOURS := [Color(0.42, 0.95, 0.30), Color(1.0, 0.62, 0.15), Color(1.0, 0.18, 0.12)]

var _units := 1.0 / RenderStyle.PIXELS_PER_UNIT


func build(capacity: int, units: float) -> void:
	_units = units
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _bug_mesh()
	multimesh.instance_count = capacity
	multimesh.visible_instance_count = 0
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.5
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	name = "Bugs"


## Danger levels: 0 harmless (crawling between computers), 1 warning, 2 lethal.
func update(
	points: PackedVector2Array,
	headings: PackedFloat32Array,
	phases: PackedFloat32Array,
	danger: PackedByteArray,
	time: float
) -> void:
	multimesh.visible_instance_count = points.size()
	for index in points.size():
		var point := points[index]
		# A quick skitter wobble keeps bugs alive without moving them.
		var wobble := 1.0 + 0.12 * sin(time * 22.0 + phases[index])
		var basis := Basis(Vector3.UP, -headings[index] - PI / 2).scaled(
			Vector3(wobble * 0.85, 0.85, 0.85 / wobble)
		)
		multimesh.set_instance_transform(
			index, Transform3D(basis, Vector3(point.x * _units, 0.04, point.y * _units))
		)
		multimesh.set_instance_color(index, COLOURS[danger[index]])


func _bug_mesh() -> Mesh:
	# One small beetle: shell, head and three pairs of legs, baked into a single mesh.
	var source := Node3D.new()
	var material := ModelGeometry.material(Color.WHITE, 0.0, 0.5)
	ModelGeometry.ellipsoid(source, Vector3(0, 0.12, 0.04), Vector3(0.20, 0.11, 0.28), material)
	ModelGeometry.ellipsoid(source, Vector3(0, 0.11, -0.27), Vector3(0.11, 0.08, 0.10), material)
	for side in [-1.0, 1.0]:
		for pair in 3:
			var z := -0.08 + pair * 0.15
			ModelGeometry.cylinder(
				source,
				Vector3(side * 0.12, 0.09, z),
				Vector3(side * 0.34, 0.03, z + (pair - 1) * 0.08),
				0.018,
				material
			)
		ModelGeometry.cylinder(
			source,
			Vector3(side * 0.05, 0.13, -0.34),
			Vector3(side * 0.14, 0.18, -0.52),
			0.012,
			material
		)
	var mesh := StaticModelBatcher.bake_direct(source)
	source.free()
	return mesh
