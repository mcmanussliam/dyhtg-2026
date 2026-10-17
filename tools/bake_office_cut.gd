extends SceneTree
## Offline, capped boolean intersections. No CSG nodes enter production scenes.
## Run: godot --headless --path . --script tools/bake_office_cut.gd

const SCALE := 43.0
const CENTRE := Vector2(640, 422)
const RADIUS := 480.0 / SCALE
const PRESETS := [
	{
		"source": "res://game/props/bookshelf_visual.tscn",
		"position": Vector2(925, 60),
		"rotation": 0.0,
		"output": "res://game/stage/art/cut_bookshelf.res",
	},
	{
		"source": "res://game/props/desk_visual.tscn",
		"position": Vector2(175, 270),
		"rotation": 0.0,
		"output": "res://game/stage/art/cut_desk.res",
	},
	{
		"source": "res://game/props/desk_visual.tscn",
		"position": Vector2(190, 210),
		"rotation": PI,
		"output": "res://game/stage/art/cut_rear_desk.res",
	},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://game/stage/art")
	for preset in PRESETS:
		await _bake(preset)
	quit()


func _bake(preset: Dictionary) -> void:
	var source := (load(preset.source) as PackedScene).instantiate() as Node3D
	root.add_child(source)
	var meshes := source.find_children("*", "MeshInstance3D", true, false)
	var pose := Transform3D(
		Basis(Vector3.UP, -float(preset.rotation)),
		Vector3(preset.position.x / SCALE, 0, preset.position.y / SCALE)
	)
	var clip_centre := pose.affine_inverse() * Vector3(CENTRE.x / SCALE, 0, CENTRE.y / SCALE)
	var boolean := CSGCombiner3D.new()
	boolean.calculate_tangents = false
	root.add_child(boolean)
	var source_union := CSGCombiner3D.new()
	boolean.add_child(source_union)
	for instance: MeshInstance3D in meshes:
		var original := CSGMesh3D.new()
		original.mesh = instance.mesh
		original.transform = source.global_transform.affine_inverse() * instance.global_transform
		original.material = instance.get_active_material(0)
		source_union.add_child(original)
	var clip := CSGMesh3D.new()
	clip.operation = CSGShape3D.OPERATION_INTERSECTION
	clip.mesh = ColumnGeometry.build(RADIUS, 8.0)
	clip.transform = Transform3D(pose.basis.inverse(), clip_centre + Vector3(0, 3, 0))
	clip.material = (meshes[0] as MeshInstance3D).get_active_material(0)
	boolean.add_child(clip)
	await process_frame
	await process_frame
	var generated := boolean.get_meshes()
	if generated.size() != 2 or not generated[1] is ArrayMesh:
		push_error("Boolean bake failed: %s" % preset.source)
		quit(1)
		return
	var result := generated[1] as ArrayMesh
	var caps := result.get_surface_count()
	boolean.queue_free()
	result.set_meta("source_scene", preset.source)
	result.set_meta("map_position", preset.position)
	result.set_meta("map_rotation", preset.rotation)
	result.set_meta("stage_center", CENTRE)
	result.set_meta("stage_radius", RADIUS * SCALE)
	result.set_meta("stage_outline", ColumnGeometry.outline(RADIUS * SCALE))
	var status := ResourceSaver.save(result, preset.output)
	print(
		"BAKED ",
		preset.output,
		" surfaces=",
		caps,
		" status=",
		status,
		" bounds=",
		result.get_aabb()
	)
	source.queue_free()
	await process_frame
