@tool
class_name ComputerBugsStage
extends OfficeStage
## Clumps of bugs fall from the ceiling. Each drop is announced by a red marker on the
## floor, lands as a black mush that keeps expanding, and joins its neighbours until the
## whole room is infected. Anyone struck by a falling clump, or touching the mush, is
## eliminated. All timing runs on the live round clock.

enum Phase { WARNING, FALLING, MUSH }

## A clump's footprint when it lands; it then swells towards MAX_RADIUS.
const IMPACT_RADIUS := 85.0
const MAX_RADIUS := 290.0
const MAX_MUSH := 48
const POOL := 8
const ZONE_UPDATE_TICKS := 2
## A landing clump squashes flat over this long while the mush blooms outwards.
const SPLAT_SECONDS := 0.3
## Nobody dies until the splat has actually started.
const LETHAL_DELAY := 0.14
const FALL_HEIGHT := 14.0
const FALL_SPEED := 30.0
## Mush clumps fuse like metaballs. The kernel and threshold are shared with mush.gdshader.
const FIELD_REACH := 1.35
const FIELD_THRESHOLD := 0.2038
const MUSH_SHADER = preload("res://game/stage/computer_bugs/mush.gdshader")

@export_range(0.5, 10.0, 0.5) var first_drop := 2.0
@export_range(0.5, 10.0, 0.1) var drop_interval := 3.2
@export_range(0.2, 5.0, 0.1) var minimum_drop := 0.7
@export_range(5.0, 120.0, 1.0) var escalation_seconds := 45.0
@export_range(0.4, 3.0, 0.1) var warning_seconds := 1.5
@export_range(0.4, 3.0, 0.1) var minimum_warning := 0.9
@export_range(5.0, 90.0, 1.0) var growth_seconds := 28.0

var clumps: Array[Dictionary] = []
var drops_total := 0
var _chairs: Array[Chair] = []
var _elapsed := 0.0
var _next_drop := 0.0
var _random := RandomNumberGenerator.new()
var _units := 1.0 / RenderStyle.PIXELS_PER_UNIT
var _blob_material: ShaderMaterial
var _blob: MeshInstance3D
var _coverables: Array[Dictionary] = []
var _radii_dirty := false
var _zone_tick := 0
var _beetles: BugMassView
var _next_block := 0
var _zone_data := PackedVector4Array()
var _markers: Array[MeshInstance3D] = []
var _falling: Array[MeshInstance3D] = []
var _free_slots: Array[int] = []


func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return
	_random.randomize()
	_reset_slots()


func bind_participants(chairs: Array[Chair]) -> void:
	_chairs = chairs


func start_round() -> void:
	if not round_running:
		_elapsed = 0.0
		_next_drop = first_drop
		drops_total = 0
		clumps.clear()
		_next_block = 0
		if is_instance_valid(_beetles):
			_beetles.clear()
		_reset_slots()
		_refresh()
	super.start_round()


func _reset_slots() -> void:
	_free_slots.clear()
	for slot in POOL:
		_free_slots.append(slot)


func spawn_pose(index: int, _count: int) -> Transform2D:
	# Seats start in the open aisles between the desk benches.
	var points := [
		Vector2(760, 130),
		Vector2(1060, 700),
		Vector2(1060, 130),
		Vector2(760, 700),
		Vector2(400, 420),
		Vector2(760, 420),
		Vector2(1060, 420),
		Vector2(150, 250),
		Vector2(650, 250),
		Vector2(650, 600)
	]
	var point: Vector2 = points[index % points.size()]
	return Transform2D((center - point).angle() + PI, to_global(point))


func difficulty() -> float:
	return clampf(_elapsed / maxf(escalation_seconds, 1), 0, 1)


## Drops start leisurely and come faster and faster, easing towards the minimum gap.
func current_interval() -> float:
	return lerpf(drop_interval, minimum_drop, 1.0 - pow(1.0 - difficulty(), 2.0))


func current_warning() -> float:
	return lerpf(warning_seconds, minimum_warning, difficulty())


func mush_count() -> int:
	var total := 0
	for clump in clumps:
		total += 1 if clump.phase == Phase.MUSH else 0
	return total


## A landed clump swells from its impact footprint towards MAX_RADIUS, fast at first.
func mush_radius(clump: Dictionary) -> float:
	var age := maxf(_elapsed - clump.landed, 0.0)
	if age < SPLAT_SECONDS:
		# The splat: the mass bursts outwards from a small core to its full footprint.
		var burst := smoothstep(0.0, 1.0, age / SPLAT_SECONDS)
		return lerpf(IMPACT_RADIUS * 0.4, IMPACT_RADIUS, burst)
	var grown := 1.0 - pow(1.0 - clampf((age - SPLAT_SECONDS) / growth_seconds, 0.0, 1.0), 2.0)
	return lerpf(IMPACT_RADIUS, MAX_RADIUS, grown)


func tick_hazards(delta: float) -> void:
	if not round_running:
		return
	_elapsed += maxf(delta, 0)
	if _elapsed >= _next_drop and mush_count() + _pending() < MAX_MUSH:
		if _announce_drop():
			_next_drop = _elapsed + current_interval() * _random.randf_range(0.85, 1.15)
		else:
			_next_drop = _elapsed + 0.25
	for clump in clumps:
		_advance(clump, delta)
	_strike_chairs()
	_refresh()


func _pending() -> int:
	var total := 0
	for clump in clumps:
		total += 1 if clump.phase != Phase.MUSH else 0
	return total


func _advance(clump: Dictionary, delta: float) -> void:
	match clump.phase:
		Phase.WARNING:
			clump.timer += delta
			if clump.timer >= clump.warning:
				clump.phase = Phase.FALLING
				clump.height = FALL_HEIGHT
		Phase.FALLING:
			clump.height -= FALL_SPEED * delta
			if clump.height <= 0.0:
				clump.height = 0.0
				clump.phase = Phase.MUSH
				clump.landed = _elapsed
				clump.block = _next_block
				_next_block = mini(_next_block + 1, MAX_MUSH - 1)
				if is_instance_valid(_beetles):
					_beetles.place(clump.block, clump.position, clump.seed)
		Phase.MUSH:
			# The squashed clump hides once its splat is over, freeing its pool slot.
			if not clump.freed and _elapsed - clump.landed >= SPLAT_SECONDS:
				clump.freed = true
				_free_slots.append(clump.slot)


func _announce_drop() -> bool:
	if _free_slots.is_empty():
		return false
	var slot: int = _free_slots.pop_back()
	clumps.append(
		{
			"position": _choose_target(),
			"phase": Phase.WARNING,
			"timer": 0.0,
			"warning": current_warning(),
			"height": FALL_HEIGHT,
			"landed": INF,
			"slot": slot,
			"seed": _random.randf(),
			"block": -1,
			"freed": false
		}
	)
	drops_total += 1
	return true


## New clumps are drawn to the existing mush and to the players, so the infection creeps
## outwards and joins up instead of landing at random.
func _choose_target() -> Vector2:
	var roll := _random.randf()
	var landed: Array[Dictionary] = []
	for clump in clumps:
		if clump.phase == Phase.MUSH:
			landed.append(clump)
	var point := Vector2.ZERO
	if not landed.is_empty() and roll < 0.55:
		var source: Dictionary = landed[_random.randi_range(0, landed.size() - 1)]
		point = (
			source.position
			+ (
				Vector2.from_angle(_random.randf() * TAU)
				* mush_radius(source)
				* _random.randf_range(1.0, 1.7)
			)
		)
	elif roll < 0.82:
		var living: Array[Chair] = []
		for chair in _chairs:
			if is_instance_valid(chair) and chair.active and not chair.falling:
				living.append(chair)
		if not living.is_empty():
			var chair := living[_random.randi_range(0, living.size() - 1)]
			point = chair.global_position + chair.linear_velocity * 0.45
		else:
			point = to_global(center)
	else:
		point = to_global(
			(
				center
				+ Vector2(
					_random.randf_range(-half_size.x, half_size.x),
					_random.randf_range(-half_size.y, half_size.y)
				)
			)
		)
	return _clamp_inside(point)


func _clamp_inside(world_point: Vector2) -> Vector2:
	var inset := Vector2.ONE * (IMPACT_RADIUS + 20.0)
	return to_global(
		center + (to_local(world_point) - center).clamp(-half_size + inset, half_size - inset)
	)


## Sum of every landed clump's smooth falloff at a point. Overlapping clumps fuse: the
## mass is wider than either circle where they meet. A lone clump covers exactly its
## own radius, and `extra` inflates every radius for safety margins.
func danger_field(world_point: Vector2, extra: float = 0.0, lethal: bool = false) -> float:
	var total := 0.0
	for clump in clumps:
		if clump.phase != Phase.MUSH:
			continue
		# A fresh splat is visible for a moment before it can hurt anyone.
		if lethal and _elapsed - clump.landed < LETHAL_DELAY:
			continue
		var reach := (mush_radius(clump) + extra) * FIELD_REACH
		var d2: float = clump.position.distance_squared_to(world_point)
		if d2 >= reach * reach:
			continue
		var falloff := 1.0 - d2 / (reach * reach)
		total += falloff * falloff
	return total


func in_mush(world_point: Vector2, extra: float = 0.0, lethal: bool = false) -> bool:
	return danger_field(world_point, extra, lethal) >= FIELD_THRESHOLD


## Is the point under a clump that has been announced or is on its way down?
func under_drop(world_point: Vector2, extra: float = 0.0) -> bool:
	for clump in clumps:
		if (
			clump.phase != Phase.MUSH
			and clump.position.distance_to(world_point) < IMPACT_RADIUS + extra
		):
			return true
	return false


## Fraction of the office floor currently covered, sampled on a coarse grid.
func coverage() -> float:
	var hits := 0
	var samples := 0
	for x in range(0, 24):
		for y in range(0, 24):
			var local := (
				center
				- half_size
				+ Vector2(
					(x + 0.5) / 24.0 * half_size.x * 2.0, (y + 0.5) / 24.0 * half_size.y * 2.0
				)
			)
			samples += 1
			hits += 1 if in_mush(to_global(local)) else 0
	return float(hits) / samples


func _strike_chairs() -> void:
	for chair in _chairs:
		if not is_instance_valid(chair) or not chair.active or chair.falling:
			continue
		# A clump in flight never kills: it must splat first, then the mass reaches the chair.
		if not in_mush(chair.global_position, 0.0, true):
			continue
		var source := Vector2.INF
		var nearest := INF
		for clump in clumps:
			if clump.phase != Phase.MUSH:
				continue
			var distance: float = clump.position.distance_to(chair.global_position)
			if distance < nearest:
				nearest = distance
				source = clump.position
		# The mass bowls the chair clear of it rather than silently deleting it.
		var away := (chair.global_position - source).normalized()
		if away.length_squared() < 0.5:
			away = Vector2.RIGHT
		var planar := away * 16.0
		chair.set_knockout_launch(
			Vector3(planar.x, 9.0, planar.y), Vector3(away.y, 0.5, -away.x) * 8.0
		)
		elimination_requested.emit(chair.seat, &"bugs")


func is_safe(world_point: Vector2, margin: float = 0.0) -> bool:
	if not super.is_safe(world_point, margin):
		return false
	return (
		not in_mush(world_point, 30.0 + margin * 0.4)
		and not under_drop(world_point, 40.0 + margin * 0.4)
	)


func is_path_safe(from: Vector2, destination: Vector2, margin: float = 0.0) -> bool:
	for step in range(1, 5):
		if not is_safe(from.lerp(destination, step / 4.0), margin):
			return false
	return true


func safe_target(world_point: Vector2, margin: float = 90.0) -> Vector2:
	var point := super.safe_target(world_point, margin)
	for pass_index in 6:
		if is_safe(point, margin):
			break
		# Retreat away from the heart of the nearest clump, then re-check.
		var nearest := Vector2.INF
		var nearest_distance := INF
		var reach := IMPACT_RADIUS
		for clump in clumps:
			var distance: float = clump.position.distance_to(point)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest = clump.position
				reach = mush_radius(clump) if clump.phase == Phase.MUSH else IMPACT_RADIUS
		if not is_finite(nearest.x):
			break
		var away := (point - nearest).normalized()
		if away.length_squared() < 0.5:
			away = Vector2.RIGHT
		point = super.safe_target(nearest + away * (reach + 120.0 + margin * 0.4), margin)
	return point


func create_presentation(parent: Node3D, units_per_pixel: float) -> void:
	var existing := parent.get_children()
	super.create_presentation(parent, units_per_pixel)
	_units = units_per_pixel
	# The mush is a normal world-space surface drawn before any other transparent object,
	# so characters and spray always sit on top of it. Floor decal first.
	_blob_material = ShaderMaterial.new()
	_blob_material.shader = MUSH_SHADER
	_blob_material.render_priority = -50
	_zone_data.resize(MAX_MUSH)
	_blob_material.set_shader_parameter("zones", _zone_data)
	_blob_material.set_shader_parameter("zone_count", 0)
	var floor_plane := PlaneMesh.new()
	floor_plane.size = half_size * 2 * units_per_pixel
	_blob = MeshInstance3D.new()
	_blob.name = "BugMush"
	_blob.mesh = floor_plane
	_blob.material_override = _blob_material
	_blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var floor_centre := to_global(center) * units_per_pixel
	_blob.position = Vector3(floor_centre.x, 0.014, floor_centre.y)
	_blob.hide()
	parent.add_child(_blob)
	# Real beetles, in one draw call, line the edges and fill the middle of every mass.
	_beetles = BugMassView.new()
	parent.add_child(_beetles)
	_beetles.build(
		MAX_MUSH,
		units_per_pixel,
		Rect2(to_global(center - half_size + Vector2.ONE * 14), half_size * 2 - Vector2.ONE * 28)
	)
	# Every prop, wall piece and wall fixture gets one cover shell, sized to the whole object
	# and wearing the same mush. Shells stay hidden until the mass reaches them.
	_coverables.clear()
	for child in parent.get_children():
		if (
			child in existing
			or child == _blob
			or child == _beetles
			or child.is_in_group("stage_floor")
		):
			continue
		_add_cover(child)
	# Red floor markers, in the same flat translucent style as the bull's charge lane.
	var warning := ModelGeometry.material(Color(0.95, 0.32, 0.15, 0.30))
	warning.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warning.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var disc := CylinderMesh.new()
	disc.top_radius = IMPACT_RADIUS * units_per_pixel
	disc.bottom_radius = disc.top_radius
	disc.height = 0.008
	var clump_mesh := _clump_mesh()
	for slot in POOL:
		var marker := MeshInstance3D.new()
		marker.mesh = disc
		marker.material_override = warning
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.hide()
		parent.add_child(marker)
		_markers.append(marker)
		var drop := MeshInstance3D.new()
		drop.mesh = clump_mesh
		drop.hide()
		parent.add_child(drop)
		_falling.append(drop)
	_refresh()


func _add_cover(root: Node3D) -> void:
	var bounds := AABB()
	var found := false
	var inverse := root.global_transform.affine_inverse()
	for node in [root] + root.find_children("*", "GeometryInstance3D", true, false):
		if not (node is MeshInstance3D or node is MultiMeshInstance3D):
			continue
		var local: AABB = inverse * node.global_transform * node.get_aabb()
		bounds = local if not found else bounds.merge(local)
		found = true
	# Flat decals (carpets) lie under the floor mush already.
	if not found or bounds.size.y < 0.08:
		return
	var shell := MeshInstance3D.new()
	shell.name = "MushCover"
	var box := BoxMesh.new()
	box.size = bounds.size * 1.05 + Vector3.ONE * 0.04
	shell.mesh = box
	shell.material_override = _blob_material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.position = bounds.get_center()
	shell.hide()
	root.add_child(shell)
	var middle: Vector3 = root.global_transform * bounds.get_center()
	_coverables.append(
		{
			"node": shell,
			"position": Vector2(middle.x, middle.z) / _units,
			"reach": Vector2(bounds.size.x, bounds.size.z).length() * 0.5 / _units
		}
	)


## A lumpy black ball of bugs with spiky legs, baked into one mesh.
func _clump_mesh() -> Mesh:
	var source := Node3D.new()
	var black := ModelGeometry.material(Color(0.015, 0.017, 0.022), 0.35, 0.3)
	var radius := IMPACT_RADIUS * _units
	ModelGeometry.ellipsoid(
		source,
		Vector3(0, radius * 0.55, 0),
		Vector3(radius * 0.62, radius * 0.5, radius * 0.62),
		black
	)
	for lobe in 9:
		var angle := lobe * TAU / 9.0
		var lift := 0.35 + 0.35 * fposmod(sin(lobe * 12.9) * 43.7, 1.0)
		var size := 0.32 + 0.16 * fposmod(sin(lobe * 7.3) * 91.1, 1.0)
		ModelGeometry.ellipsoid(
			source,
			Vector3(cos(angle) * radius * 0.5, radius * lift, sin(angle) * radius * 0.5),
			Vector3.ONE * radius * size,
			black
		)
	for leg in 22:
		var angle := leg * 2.399
		var lift := 0.2 + 0.7 * fposmod(sin(leg * 5.1) * 77.7, 1.0)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		ModelGeometry.cylinder(
			source,
			Vector3(0, radius * lift, 0) + direction * radius * 0.55,
			Vector3(0, radius * (lift + 0.18), 0) + direction * radius * 0.95,
			0.025,
			black,
			0.008
		)
	var mesh := StaticModelBatcher.bake_direct(source)
	source.free()
	return mesh


func set_render_warmup(enabled: bool) -> void:
	# First-use shader and mesh paths draw under the black title card.
	if _markers.is_empty():
		return
	if enabled:
		_markers[0].show()
		_falling[0].show()
		_blob.show()
		_blob_material.set_shader_parameter("zone_count", 1)
	else:
		_refresh()


func _refresh() -> void:
	if _markers.is_empty():
		return
	for slot in POOL:
		_markers[slot].hide()
		_falling[slot].hide()
	for clump in clumps:
		var point: Vector2 = clump.position * _units
		var slot: int = clump.slot
		if clump.phase == Phase.MUSH:
			var age: float = _elapsed - clump.landed
			if age < SPLAT_SECONDS:
				# The splat: the fallen clump squashes flat as the mass bursts outwards.
				var squash := smoothstep(0.0, 1.0, age / SPLAT_SECONDS)
				_falling[slot].position = Vector3(point.x, 0.0, point.y)
				_falling[slot].scale = Vector3(
					1.0 + 0.8 * squash, 1.0 - 0.85 * squash, 1.0 + 0.8 * squash
				)
				_falling[slot].show()
			continue
		_markers[slot].position = Vector3(point.x, 0.02, point.y)
		_markers[slot].show()
		if clump.phase == Phase.FALLING:
			_falling[slot].position = Vector3(point.x, clump.height, point.y)
			_falling[slot].scale = Vector3.ONE
			_falling[slot].rotation.y = clump.seed * TAU + clump.height * 0.4
			_falling[slot].show()
	# Radii drive the beetles' smooth outward glide, so they go to the GPU every tick.
	for clump in clumps:
		if clump.phase == Phase.MUSH and clump.block >= 0:
			if is_instance_valid(_beetles):
				_beetles.set_radius(clump.block, mush_radius(clump) * _units)
	if is_instance_valid(_beetles):
		_beetles.apply_radii()
	_zone_tick += 1
	if _zone_tick >= ZONE_UPDATE_TICKS or not round_running:
		_zone_tick = 0
		_refresh_mush()


## Zone data changes slowly, so it is pushed at a fraction of the physics rate.
func _refresh_mush() -> void:
	var count := 0
	for clump in clumps:
		if clump.phase == Phase.MUSH and count < MAX_MUSH:
			var position: Vector2 = clump.position * _units
			var reach := mush_radius(clump) * _units * FIELD_REACH
			_zone_data[count] = Vector4(position.x, position.y, 1.0 / (reach * reach), clump.seed)
			count += 1
	_blob.visible = count > 0
	if count > 0:
		_blob_material.set_shader_parameter("zones", _zone_data)
		_blob_material.set_shader_parameter("zone_count", count)
	# Furniture and walls switch their cover shell on once, when the mass first reaches them.
	for entry in _coverables:
		if not entry.node.visible and in_mush(entry.position, maxf(entry.reach * 0.6 - 10.0, 0.0)):
			entry.node.show()
