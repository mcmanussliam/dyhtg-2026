class_name SprayView
extends Node3D
## Lit 3D foam spheres, pooled in one draw and clipped to the spray's physical reach.

const BALL_COUNT := 240
const PIXELS_PER_UNIT := RenderStyle.PIXELS_PER_UNIT
const VIEW_DIRECTION := Vector3(0, 0.72, 0.694)

static var _sphere: SphereMesh
static var _surface: ShaderMaterial

var _balls: MultiMesh
var _positions := PackedVector3Array()
var _sizes := PackedFloat32Array()
var _opacity := PackedFloat32Array()
var _scatter := PackedVector2Array()
var _seeds := PackedFloat32Array()
var _sort_keys := PackedInt64Array()
var _buffer := PackedFloat32Array()
# Per-ball terms fixed by the seat, kept in double precision like the inline maths.
var _prepared_seat := -1
var _ball_seed := PackedFloat64Array()
var _phase_base := PackedFloat64Array()
var _phase_rate := PackedFloat64Array()
var _radius_scale := PackedFloat64Array()
var _seed_turn := PackedFloat64Array()
var _scatter_scale := PackedFloat64Array()
var _fade_span := PackedFloat64Array()
var _fringe_reach := PackedFloat64Array()
var _fringe_opacity := PackedFloat64Array()


func _ready() -> void:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 24
		_sphere.rings = 12
		_surface = ShaderMaterial.new()
		_surface.shader = preload("res://game/chair/art/spray.gdshader")
	_balls = MultiMesh.new()
	_balls.transform_format = MultiMesh.TRANSFORM_3D
	_balls.use_colors = true
	_balls.mesh = _sphere
	_balls.instance_count = BALL_COUNT
	var renderer := MultiMeshInstance3D.new()
	renderer.multimesh = _balls
	renderer.material_override = _surface
	renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(renderer)
	_positions.resize(BALL_COUNT)
	_sizes.resize(BALL_COUNT)
	_opacity.resize(BALL_COUNT)
	_sort_keys.resize(BALL_COUNT)
	_buffer.resize(BALL_COUNT * 16)
	for slot in BALL_COUNT:
		for channel in [12, 13, 14]:
			_buffer[slot * 16 + channel] = 1.0
	for index in BALL_COUNT:
		var seed := fposmod(sin(float(index) * 127.1 + 7.3) * 43758.5453, 1.0)
		_seeds.append(seed)
		var angle := float(index) * 2.399963
		var radius := sqrt(seed)
		_scatter.append(Vector2(cos(angle), sin(angle)) * radius)


func warm_up_rendering(nozzle: Vector3) -> void:
	# A real, in-view instance compiles the MultiMesh transparency path. Gameplay
	# state stays untouched, and the regular update restores the complete buffer.
	visible = true
	_balls.visible_instance_count = 1
	_balls.set_instance_transform(0, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.05), nozzle))
	_balls.set_instance_color(0, Color.WHITE)


func update_plume(
	chair: Chair, nozzle: Vector3, clock: float, origin: Vector3 = Vector3.ZERO
) -> void:
	var forward_2d := Vector2.from_angle(chair.aim_angle)
	var floor_distance := (Vector2(nozzle.x - origin.x, nozzle.z - origin.z)).dot(forward_2d)
	var length := maxf(chair.spray_reach / PIXELS_PER_UNIT - floor_distance, 0.0)
	visible = chair.spraying and chair.jet_strength > 0 and length > 0.02
	if not visible:
		return
	var forward := Vector3(forward_2d.x, 0, forward_2d.y)
	var side := Vector3(-forward.z, 0, forward.x)
	var cone := tan(deg_to_rad(chair.tuning.half_angle_degrees))
	var spread_scale := 0.74 + sin(clock * 1.7 + chair.seat * 2.1) * 0.04
	if chair.seat != _prepared_seat:
		_prepare_seat(chair.seat)
	var phase_offset := chair.seat * 0.137
	var turn := chair.seat * 1.719
	var visible_count := 0
	for index in BALL_COUNT:
		var seed := _ball_seed[index]
		var phase := _phase_base[index] + clock * _phase_rate[index] + phase_offset
		var t := fposmod(phase, 1.0)
		var life_seed := fposmod(sin(seed * 91.7 + floorf(phase) * 37.1) * 17453.37, 1.0)
		var radius := minf(
			lerpf(0.050, 0.215, t) * _radius_scale[index] * chair.size_scale, length * 0.24
		)
		var travel := lerpf(radius, maxf(radius, length - radius), t)
		var spread := cone * travel * spread_scale
		var scatter := (
			_scatter[index].rotated(turn + sin(t * 5.0 + _seed_turn[index]) * 0.25)
			* _scatter_scale[index]
		)
		var offset := side * scatter.x * spread + Vector3.UP * scatter.y * spread * 0.65
		var fringe := index % 10 == 0
		if fringe:
			var outward := -1.0 if scatter.x < 0 else 1.0
			offset = (
				side * outward * cone * travel * _fringe_reach[index]
				+ Vector3.UP * scatter.y * spread * 0.65
			)
		_positions[index] = nozzle + forward * travel + offset
		_sizes[index] = radius * lerpf(0.35, 1.0, chair.jet_strength)
		var fade_end := lerpf(0.76, 1.0, life_seed)
		var fade_start := fade_end - _fade_span[index]
		var fade := 1.0 - smoothstep(fade_start, fade_end, t)
		fade *= 1.0 - smoothstep(0.45, 1.0, scatter.length())
		if fringe:
			fade = (1.0 - smoothstep(fade_start, fade_end, t)) * _fringe_opacity[index]
		_opacity[index] = fade * smoothstep(0.0, 0.008, t) * chair.jet_strength
		# Native integer sorting avoids thousands of script comparator calls per jet.
		# 0.00001-unit depth precision is below any visible ordering difference.
		if _opacity[index] > 0.0:
			var depth := int(floorf(_positions[index].dot(VIEW_DIRECTION) * 100000.0))
			_sort_keys[index] = (depth << 8) | index
			visible_count += 1
		else:
			_sort_keys[index] = 0x7FFFFFFFFFFFFFFF
	_sort_keys.sort()
	_balls.visible_instance_count = visible_count
	for slot in visible_count:
		var index := int(_sort_keys[slot] & 255)
		var base := slot * 16
		# Three transform rows followed by RGBA, uploaded in one RenderingServer call.
		_buffer[base] = _sizes[index]
		_buffer[base + 5] = _sizes[index]
		_buffer[base + 10] = _sizes[index]
		_buffer[base + 3] = _positions[index].x
		_buffer[base + 7] = _positions[index].y
		_buffer[base + 11] = _positions[index].z
		_buffer[base + 15] = _opacity[index]
	_balls.buffer = _buffer


func _prepare_seat(seat: int) -> void:
	_prepared_seat = seat
	_ball_seed.resize(BALL_COUNT)
	_phase_base.resize(BALL_COUNT)
	_phase_rate.resize(BALL_COUNT)
	_radius_scale.resize(BALL_COUNT)
	_seed_turn.resize(BALL_COUNT)
	_scatter_scale.resize(BALL_COUNT)
	_fade_span.resize(BALL_COUNT)
	_fringe_reach.resize(BALL_COUNT)
	_fringe_opacity.resize(BALL_COUNT)
	for index in BALL_COUNT:
		var seed := fposmod(_seeds[index] + seat * 0.381966, 1.0)
		_ball_seed[index] = seed
		_phase_base[index] = float(index) / BALL_COUNT + seed * 0.23
		_phase_rate[index] = lerpf(1.45, 1.85, seed)
		_radius_scale[index] = lerpf(0.72, 1.18, seed)
		_seed_turn[index] = seed * TAU
		_scatter_scale[index] = lerpf(0.65, 0.95, seed)
		_fade_span[index] = lerpf(0.20, 0.40, seed)
		_fringe_reach[index] = lerpf(1.05, 1.45, seed)
		_fringe_opacity[index] = lerpf(0.35, 0.60, seed)
