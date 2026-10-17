class_name FaultyFloorView
extends RefCounted
## One batched floor, per-panel native support, and shared meshes for falling slabs.

const DEPTH := 0.65
const MAX_DEBRIS := 36

var _stage: OfficeStage
var _grid: FaultyFloorGrid
var _world: Node3D
var _units := 1.0 / RenderStyle.PIXELS_PER_UNIT
var _floor: MultiMeshInstance3D
var _colliders: Array[CollisionShape3D] = []
var _top: ShaderMaterial
var _slab: ArrayMesh
var _pieces: Array[FallingStagePiece] = []
var _warmup: MeshInstance3D


func configure(
	stage: OfficeStage, grid: FaultyFloorGrid, world: Node3D, units: float, warning: float
) -> void:
	_stage = stage
	_grid = grid
	_world = world
	_units = units
	_top = ShaderMaterial.new()
	_top.shader = preload("res://game/stage/faulty_floors/faulty_floor.gdshader")
	_top.set_shader_parameter("units", units)
	_top.set_shader_parameter("warning_duration", warning)
	var sides := ShaderMaterial.new()
	sides.shader = preload("res://game/stage/shared/art/cylinder.gdshader")
	sides.set_shader_parameter("fade_start", 6.0)
	sides.set_shader_parameter("fade_end", 18.0)
	var half := grid.cell_size * 0.5
	var polygon := PackedVector2Array(
		[Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]
	)
	_slab = FractureGeometry.slab(polygon, units, DEPTH, _top, sides)
	var body := StaticBody3D.new()
	body.name = "OfficeFloor"
	body.add_to_group("stage_floor")
	world.add_child(body)
	var origin := stage.to_global(stage.center) * units
	body.position = Vector3(origin.x, 0, origin.y)
	body.rotation.y = -stage.global_rotation
	_floor = MultiMeshInstance3D.new()
	_floor.name = "FloorPanels"
	_floor.multimesh = MultiMesh.new()
	_floor.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_floor.multimesh.use_custom_data = true
	_floor.multimesh.mesh = _slab
	_floor.multimesh.instance_count = grid.states.size()
	body.add_child(_floor)
	var shape := BoxShape3D.new()
	shape.size = Vector3(grid.cell_size.x * units, DEPTH, grid.cell_size.y * units)
	for index in grid.states.size():
		var center := grid.cell_rect(index).get_center()
		var local := (center - stage.center) * units
		_floor.multimesh.set_instance_transform(
			index, Transform3D(Basis.IDENTITY, Vector3(local.x, 0, local.y))
		)
		_floor.multimesh.set_instance_custom_data(index, Color(-1, center.x, center.y, 1))
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = Vector3(local.x, -DEPTH / 2, local.y)
		body.add_child(collision)
		_colliders.append(collision)
		if grid.states[index] == FaultyFloorGrid.State.GONE:
			_remove(index)
		elif grid.states[index] == FaultyFloorGrid.State.WARNING:
			warn(index)
	_warmup = ModelGeometry.instance(world, _fall_mesh(Vector2.ZERO), Vector3.ZERO, null)
	_warmup.name = "FloorDebrisWarmup"
	_warmup.hide()


func warn(index: int) -> void:
	var center := _grid.cell_rect(index).get_center()
	_floor.multimesh.set_instance_custom_data(
		index, Color(_grid.armed_at[index], center.x, center.y, 1)
	)


func update_clock(clock: float) -> void:
	_top.set_shader_parameter("floor_clock", clock)


func drop(index: int) -> void:
	_remove(index)
	for slot in range(_pieces.size() - 1, -1, -1):
		if not is_instance_valid(_pieces[slot]):
			_pieces.remove_at(slot)
	if _pieces.size() >= MAX_DEBRIS:
		var oldest := _pieces.pop_front() as FallingStagePiece
		_world.remove_child(oldest)
		oldest.queue_free()
	var body := FallingStagePiece.new()
	body.name = "FallingFloorPanel"
	body.collision_layer = 0
	body.collision_mask = 0
	body.mass = 8
	_world.add_child(body)
	var center := _grid.cell_rect(index).get_center()
	var point := _stage.to_global(center) * _units
	body.position = Vector3(point.x, 0, point.y)
	body.rotation.y = -_stage.global_rotation
	ModelGeometry.instance(body, _fall_mesh(center), Vector3.ZERO, null)
	var collision := CollisionShape3D.new()
	collision.shape = _colliders[index].shape
	collision.position.y = -DEPTH / 2
	body.add_child(collision)
	body.linear_velocity.y = -0.2
	body.angular_velocity = Vector3(sin(index * 1.7), 0.1, cos(index * 2.3)) * 0.12
	_pieces.append(body)


func set_active(active: bool) -> void:
	for piece in _pieces:
		if is_instance_valid(piece):
			piece.freeze = not active


func set_render_warmup(enabled: bool) -> void:
	_warmup.visible = enabled


func _remove(index: int) -> void:
	_colliders[index].disabled = true
	_floor.multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO)))


func _fall_mesh(center: Vector2) -> ArrayMesh:
	# Only lightweight material metadata differs; all debris shares the slab geometry.
	var mesh := _slab.duplicate() as ArrayMesh
	var material := _top.duplicate() as ShaderMaterial
	material.set_shader_parameter("instanced", false)
	material.set_shader_parameter("tile_origin", center)
	mesh.surface_set_material(0, material)
	return mesh
