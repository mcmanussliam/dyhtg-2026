class_name BugMassView
extends MultiMeshInstance3D
## Draws thousands of beetles in a single call to give the mush its crawling texture:
## a ring along each mass's ragged edge plus a scatter through the middle. Beetles are
## placed once, when a mass lands. After that the bug shader moves them outward as the
## radius uniform grows, so growth is perfectly smooth.

const BUGS_PER_BLOCK := 56
const RIM_BUGS := 34
const BUG_SHADER = preload("res://game/stage/computer_bugs/bug.gdshader")

var _units := 1.0 / RenderStyle.PIXELS_PER_UNIT
var _material: ShaderMaterial
var _radii := PackedFloat32Array()


func build(block_count: int, units: float, bounds: Rect2) -> void:
	_units = units
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = _beetle_mesh()
	multimesh.instance_count = block_count * BUGS_PER_BLOCK
	multimesh.visible_instance_count = 0
	_material = ShaderMaterial.new()
	_material.shader = BUG_SHADER
	_material.set_shader_parameter(
		"room", Vector4(bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y) * units
	)
	_radii.resize(block_count)
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Positions are computed in the shader, so cull by a bound that covers the whole room.
	extra_cull_margin = 16384.0
	name = "BugMass"


## Where one mass's beetles sit, as fractions of its radius. Deterministic per seed: a
## ring along the edge, then a scatter through the middle.
static func layout(seed: float) -> Array[Dictionary]:
	var bugs: Array[Dictionary] = []
	for index in BUGS_PER_BLOCK:
		var chance := _hash(seed * 91.7 + index * 1.37)
		var angle := _hash(seed * 13.1 + index * 2.71) * TAU
		var on_edge := index < RIM_BUGS
		var unit := Vector2.ZERO
		var heading := 0.0
		if on_edge:
			# Along the edge, a little inside and a little beyond it, facing round the rim.
			angle = (index + chance * 0.8) * TAU / RIM_BUGS
			unit = Vector2.from_angle(angle) * lerpf(0.84, 1.06, _hash(seed * 7.7 + index))
			heading = angle + PI * 0.5 + (chance - 0.5) * 1.6
		else:
			# Scattered through the middle, facing every way.
			unit = Vector2.from_angle(angle) * 0.78 * sqrt(_hash(seed * 5.3 + index * 3.1))
			heading = angle * 3.0 + chance * 6.0
		bugs.append(
			{
				"unit": unit,
				"heading": heading,
				"size":
				lerpf(0.75, 1.25, _hash(seed * 3.3 + index * 0.9)) * (1.0 if on_edge else 0.9),
				"shade": 0.012 + 0.06 * _hash(seed * 2.2 + index * 4.1),
				"phase": chance * TAU,
				"edge": on_edge
			}
		)
	return bugs


## Seeds one mass's beetles at its centre (pixels). Called once, when the clump lands.
func place(block: int, centre: Vector2, seed: float) -> void:
	var bugs := layout(seed)
	var base := block * BUGS_PER_BLOCK
	var origin := Vector3(centre.x * _units, 0.0, centre.y * _units)
	for index in BUGS_PER_BLOCK:
		var bug := bugs[index]
		var unit: Vector2 = bug.unit
		multimesh.set_instance_transform(base + index, Transform3D(Basis(), origin))
		multimesh.set_instance_color(base + index, Color(bug.shade, bug.heading, bug.size))
		multimesh.set_instance_custom_data(
			base + index, Color(bug.phase, unit.x, unit.y, float(block))
		)
	multimesh.visible_instance_count = maxi(
		multimesh.visible_instance_count, (block + 1) * BUGS_PER_BLOCK
	)


## Pushes every mass's current radius (metres) to the shader.
func set_radius(block: int, radius_metres: float) -> void:
	_radii[block] = radius_metres


func apply_radii() -> void:
	_material.set_shader_parameter("radii", _radii)


func clear() -> void:
	_radii.fill(0.0)
	if multimesh != null:
		multimesh.visible_instance_count = 0
		apply_radii()


static func _hash(value: float) -> float:
	return fposmod(sin(value * 12.9898) * 43758.5453, 1.0)


## A low-poly beetle (roughly 200 triangles): shell, head, six legs and two feelers.
func _beetle_mesh() -> Mesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sphere := SphereMesh.new()
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.radius = 1.0
	sphere.height = 2.0
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var shell := Transform3D(Basis().scaled(Vector3(0.21, 0.11, 0.30)), Vector3(0, 0.11, 0.04))
	tool.append_from(sphere, 0, shell)
	tool.append_from(
		sphere, 0, Transform3D(Basis().scaled(Vector3(0.11, 0.08, 0.10)), Vector3(0, 0.09, -0.28))
	)
	for side in [-1.0, 1.0]:
		for pair in 3:
			var z := -0.10 + pair * 0.15
			var leg_basis := Basis(Vector3.UP, side * (0.5 - pair * 0.45)).scaled(
				Vector3(0.34, 0.025, 0.025)
			)
			tool.append_from(box, 0, Transform3D(leg_basis, Vector3(side * 0.24, 0.05, z)))
		var feeler := Basis(Vector3.UP, side * 0.5).scaled(Vector3(0.22, 0.015, 0.015))
		tool.append_from(box, 0, Transform3D(feeler, Vector3(side * 0.12, 0.13, -0.44)))
	tool.generate_normals()
	return tool.commit()
