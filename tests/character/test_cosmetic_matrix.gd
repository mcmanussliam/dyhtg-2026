extends RefCounted
## The cosmetic catalogue: stable registration, every hat with every top, shared
## immutable assets with per-character materials, and no effect on movement.

const HAT_PREFIX: Array[StringName] = [
	&"none",
	&"traffic_cone",
	&"top_hat",
	&"cap",
	&"mohawk",
	&"glasses",
	&"bald_side_hair",
	&"hot_dog",
	&"construction_helmet",
]


func run(tree: SceneTree, check: Callable) -> void:
	_check_registration(check)
	_check_profiles(check)
	_check_matrix(check)
	_check_sharing(check)
	await _check_visual_only(tree, check)


func _check_registration(check: Callable) -> void:
	check.call(
		CharacterHats.IDS.slice(0, HAT_PREFIX.size()) == HAT_PREFIX,
		"Earlier hat IDs keep their order; new hats only append"
	)
	check.call(CharacterHats.NAMES.size() == CharacterHats.IDS.size(), "Every hat has a name")
	var hats := {}
	for hat in CharacterHats.IDS:
		hats[hat] = true
	check.call(hats.size() == CharacterHats.IDS.size(), "Hat IDs are unique")
	check.call(&"cowboy_hat" not in CharacterHats.IDS, "The rejected cowboy hat stays out")
	check.call(
		(
			CharacterSkin.Garment.TANK_TOP == 4
			and CharacterSkin.Garment.HIGH_VIS == 6
			and CharacterSkin.Garment.PUFFER_VEST == 8
			and CharacterSkin.Garment.SCARF == 15
		),
		"Garment kinds keep their authored numbers"
	)
	var tops := {}
	for skin in SkinCatalog.definitions():
		tops[skin.id] = true
	check.call(
		tops.size() == SkinCatalog.PATHS.size(), "Every registered top is valid with a unique ID"
	)


func _check_profiles(check: Callable) -> void:
	var path := "user://cosmetic_matrix_test_%d.cfg" % Time.get_ticks_usec()
	var appearance := CharacterAppearance.new()
	var lost := PackedStringArray()
	for hat in CharacterHats.IDS:
		appearance.hat_id = hat
		appearance.save_profile(path)
		if CharacterAppearance.load_profile(path).hat_id != hat:
			lost.append(hat)
	for skin in SkinCatalog.definitions():
		if skin.id == SkinCatalog.default_definition().id:
			continue
		appearance.body_id = skin.id
		appearance.save_profile(path)
		var loaded := CharacterAppearance.load_profile(path)
		if loaded.body_id != skin.id or loaded.body_label() != skin.display_name:
			lost.append(skin.id)
	check.call(lost.is_empty(), "Every hat and top survives a profile reload: %s" % lost)
	var malformed := ConfigFile.new()
	malformed.set_value("appearance", "hat", 42)
	malformed.set_value("appearance", "body", ["puffer_vest"])
	ProfileStore.save_file(malformed, path)
	var fallback := CharacterAppearance.load_profile(path)
	check.call(
		(
			fallback.hat_id == CharacterAppearance.NONE
			and fallback.body_id == CharacterAppearance.NONE
		),
		"Malformed cosmetic values fall back to None"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check_matrix(check: Callable) -> void:
	var body_mesh := SkinCatalog.default_definition().body_mesh
	var detailed := [CharacterSkin.Garment.HOODIE, CharacterSkin.Garment.BOW_TIE]
	var failures := PackedStringArray()
	var built := 0
	for skin in SkinCatalog.definitions():
		for hat in CharacterHats.IDS:
			var model := ChairModel.new()
			model.build(CharacterAppearance.PALETTE[3], skin, hat)
			var clothing := model.body.get_node_or_null("Clothing") as MeshInstance3D
			var dressed := skin.garment != CharacterSkin.Garment.NONE
			var ok := (
				(model.body.get_node("ContinuousBody") as MeshInstance3D).mesh == body_mesh
				and model.body.has_node("Hat") == (hat != &"none")
				and (clothing != null) == dressed
				and model.body.has_node("GarmentDetails") == (skin.garment in detailed)
			)
			if ok and dressed:
				var fabric := clothing.material_override as ShaderMaterial
				ok = (
					clothing.mesh == skin.garment_mesh
					and fabric.get_shader_parameter("garment_kind") == skin.garment
					and fabric.get_shader_parameter("has_logo") == (skin.chest_logo != null)
				)
			if not ok:
				failures.append("%s+%s" % [skin.id, hat])
			built += 1
			model.free()
	check.call(
		failures.is_empty() and built == SkinCatalog.PATHS.size() * CharacterHats.IDS.size(),
		"Every hat builds with every top over the shared body: %s" % ", ".join(failures)
	)


func _check_sharing(check: Callable) -> void:
	var skin := load("res://game/character/skins/waistcoat/waistcoat.tres") as CharacterSkin
	var first := ChairModel.new()
	first.build(CharacterAppearance.PALETTE[0], skin, &"crown")
	var second := ChairModel.new()
	second.build(CharacterAppearance.PALETTE[4], skin, &"crown")
	var a := first.body.get_node("Clothing") as MeshInstance3D
	var b := second.body.get_node("Clothing") as MeshInstance3D
	check.call(
		a.mesh == b.mesh and a.material_override != b.material_override,
		"Characters share garment meshes but own their materials"
	)
	check.call(
		(
			a.material_override.get_shader_parameter("clothing_colour")
			!= b.material_override.get_shader_parameter("clothing_colour")
		),
		"Each character keeps its own garment tint"
	)
	first.free()
	second.free()


## Identical steering with different cosmetics must trace identical paths.
func _check_visual_only(tree: SceneTree, check: Callable) -> void:
	var arena := Node2D.new()
	tree.root.add_child(arena)
	var outfits := [
		[SkinCatalog.default_definition(), &"none"],
		[load("res://game/character/skins/puffer_vest/puffer_vest.tres"), &"wizard_hat"],
		[load("res://game/character/skins/scarf/scarf.tres"), &"headphones"],
	]
	var chairs: Array[Chair] = []
	for index in outfits.size():
		var chair := (load("res://game/chair/chair.tscn") as PackedScene).instantiate() as Chair
		chair.skin = outfits[index][0]
		chair.hat_id = outfits[index][1]
		chair.position = Vector2(index * 4000, 0)
		chair.configure(index, Color("94b9f4"), Vector2.RIGHT)
		arena.add_child(chair)
		chair.prepare_round()
		chair.start_extinguisher_ramp(0.0)
		chair.begin_round()
		chairs.append(chair)
	for frame in 120:
		for chair in chairs:
			chair.command.turn = 1.0 if frame % 60 < 30 else -0.4
			chair.step(1.0 / 60.0)
		await tree.physics_frame
	var matches := true
	for chair in chairs:
		matches = (
			matches
			and (
				(chair.position - Vector2(chair.seat * 4000, 0)).distance_to(chairs[0].position)
				< 0.01
			)
			and is_equal_approx(chair.rotation, chairs[0].rotation)
			and is_equal_approx(chair.mass, chairs[0].mass)
		)
	check.call(
		matches and chairs[0].position.length() > 100,
		"Cosmetics never change chair mass, movement or steering"
	)
	arena.queue_free()
	await tree.process_frame
