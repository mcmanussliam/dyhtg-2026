class_name SprayView
extends Node3D
## Lit 3D foam spheres, pooled in one draw and clipped to the spray's physical reach.

const BALL_COUNT := 240
const PIXELS_PER_UNIT := RenderStyle.PIXELS_PER_UNIT
const VIEW_DIRECTION := Vector3(0, 0.72, 0.694)

var _balls: MultiMesh
var _positions := PackedVector3Array()
var _sizes := PackedFloat32Array()
var _opacity := PackedFloat32Array()
var _scatter := PackedVector2Array()
var _seeds := PackedFloat32Array()
var _order: Array[int] = []


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 24
	sphere.rings = 12
	_balls = MultiMesh.new()
	_balls.transform_format = MultiMesh.TRANSFORM_3D
	_balls.use_colors = true
	_balls.mesh = sphere
	_balls.instance_count = BALL_COUNT
	var renderer := MultiMeshInstance3D.new()
	renderer.multimesh = _balls
	var surface := ShaderMaterial.new()
	surface.shader = preload("res://game/chair/art/spray.gdshader")
	renderer.material_override = surface
	renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(renderer)
	_positions.resize(BALL_COUNT)
	_sizes.resize(BALL_COUNT)
	_opacity.resize(BALL_COUNT)
	for index in BALL_COUNT:
		var seed := fposmod(sin(float(index) * 127.1 + 7.3) * 43758.5453, 1.0)
		_seeds.append(seed)
		var angle := float(index) * 2.399963
		var radius := sqrt(seed)
		_scatter.append(Vector2(cos(angle), sin(angle)) * radius)
		_order.append(index)


func update_plume(
	chair: Chair, nozzle: Vector3, clock: float, origin: Vector3 = Vector3.ZERO
) -> void:
	var forward_2d := Vector2.from_angle(chair.aim_angle)
	var floor_distance := (Vector2(nozzle.x - origin.x, nozzle.z - origin.z)).dot(forward_2d)
	var length := maxf(chair.spray_reach / PIXELS_PER_UNIT - floor_distance, 0.0)
	visible = chair.spraying and length > 0.02
	if not visible:
		return
	var forward := Vector3(forward_2d.x, 0, forward_2d.y)
	var side := Vector3(-forward.z, 0, forward.x)
	var cone := tan(deg_to_rad(chair.tuning.half_angle_degrees))
	for index in BALL_COUNT:
		var seed := fposmod(_seeds[index] + chair.seat * 0.381966, 1.0)
		var phase := (
			float(index) / BALL_COUNT
			+ seed * 0.23
			+ clock * lerpf(1.45, 1.85, seed)
			+ chair.seat * 0.137
		)
		var t := fposmod(phase, 1.0)
		var life_seed := fposmod(sin(seed * 91.7 + floorf(phase) * 37.1) * 17453.37, 1.0)
		var radius := minf(lerpf(0.050, 0.215, t) * lerpf(0.72, 1.18, seed), length * 0.24)
		var travel := lerpf(radius, maxf(radius, length - radius), t)
		var spread := cone * travel * (0.74 + sin(clock * 1.7 + chair.seat * 2.1) * 0.04)
		var scatter := (
			_scatter[index].rotated(chair.seat * 1.719 + sin(t * 5.0 + seed * TAU) * 0.25)
			* lerpf(0.65, 0.95, seed)
		)
		var offset := side * scatter.x * spread + Vector3.UP * scatter.y * spread * 0.65
		var fringe := index % 10 == 0
		if fringe:
			var outward := -1.0 if scatter.x < 0 else 1.0
			offset = (
				side * outward * cone * travel * lerpf(1.05, 1.45, seed)
				+ Vector3.UP * scatter.y * spread * 0.65
			)
		_positions[index] = nozzle + forward * travel + offset
		_sizes[index] = radius
		var fade_end := lerpf(0.76, 1.0, life_seed)
		var fade_start := fade_end - lerpf(0.20, 0.40, seed)
		var fade := 1.0 - smoothstep(fade_start, fade_end, t)
		fade *= 1.0 - smoothstep(0.45, 1.0, scatter.length())
		if fringe:
			fade = (1.0 - smoothstep(fade_start, fade_end, t)) * lerpf(0.35, 0.60, seed)
		_opacity[index] = fade * smoothstep(0.0, 0.008, t)
	# Transparency needs back-to-front instance order in the fixed camera view.
	_order.sort_custom(
		func(a: int, b: int) -> bool:
			return _positions[a].dot(VIEW_DIRECTION) < _positions[b].dot(VIEW_DIRECTION)
	)
	for slot in BALL_COUNT:
		var index := _order[slot]
		var transform := Transform3D(
			Basis.IDENTITY.scaled(Vector3.ONE * _sizes[index]), _positions[index]
		)
		_balls.set_instance_transform(slot, transform)
		_balls.set_instance_color(slot, Color(1, 1, 1, _opacity[index]))
