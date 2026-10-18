extends RefCounted
## Every hat fits every top; cosmetics stay visual-only and IDs stay stable.

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
const NEW_HATS: Array[StringName] = [
	&"beanie",
	&"bucket_hat",
	&"crown",
	&"party_hat",
	&"wizard_hat",
	&"chef_hat",
	&"propeller_cap",
	&"headphones",
	&"bunny_ears",
	&"halo",
	&"sunglasses",
]
const NEW_TOPS := {
	&"puffer_vest": CharacterSkin.Garment.PUFFER_VEST,
	&"waistcoat": CharacterSkin.Garment.WAISTCOAT,
	&"fleece_vest": CharacterSkin.Garment.FLEECE_VEST,
	&"tie": CharacterSkin.Garment.TIE,
	&"bow_tie": CharacterSkin.Garment.BOW_TIE,
	&"scarf": CharacterSkin.Garment.SCARF,
}


func run(tree: SceneTree, check: Callable) -> void:
	_check_registration(check)
	_check_profiles(check)
	_check_matrix(check)
	await _check_visual_only(tree, check)


func _check_registration(check: Callable) -> void:
	check.call(
		CharacterHats.IDS.slice(0, HAT_PREFIX.size()) == HAT_PREFIX,
		"Existing hat IDs keep their order"
	)
	check.call(CharacterHats.NAMES.size() == CharacterHats.IDS.size(), "Every hat has a name")
	var unique_hats := {}
	for hat in CharacterHats.IDS:
		unique_hats[hat] = true
	check.call(unique_hats.size() == CharacterHats.IDS.size(), "Hat IDs are unique")
	check.call(&"cowboy_hat" not in CharacterHats.IDS, "The rejected cowboy hat stays out")
	for hat in NEW_HATS:
		check.call(hat in CharacterHats.IDS, "New hat is registered: %s" % hat)
	check.call(
		(
			CharacterSkin.Garment.TANK_TOP == 4
			and CharacterSkin.Garment.HIGH_VIS == 6
			and CharacterSkin.Garment.PUFFER_VEST == 8
			and CharacterSkin.Garment.SCARF == 15
		),
		"Garment kinds keep their authored numbers"
	)
	var skins := {}
	for skin in SkinCatalog.definitions():
		skins[skin.id] = skin
	check.call(
		skins.size() == SkinCatalog.PATHS.size(), "Every registered top is valid with a unique ID"
	)
	for id in NEW_TOPS:
		var path := "res://game/character/skins/%s/%s.tres" % [id, id]
		check.call(path in SkinCatalog.PATHS, "New top is registered explicitly: %s" % id)
		check.call(
			skins.has(id) and skins[id].garment == NEW_TOPS[id] and skins[id].garment_mesh != null,
			"New top provides its own shell and garment kind: %s" % id
		)
		check.call(
			skins.has(id) and skins[id].body_mesh == SkinCatalog.default_definition().body_mesh,
			"New top keeps the shared body mesh: %s" % id
		)


func _check_profiles(check: Callable) -> void:
	var path := "user://cosmetic_matrix_test_%d.cfg" % Time.get_ticks_usec()
	var appearance := CharacterAppearance.new()
	for hat in NEW_HATS:
		appearance.hat_id = hat
		appearance.save_profile(path)
		check.call(
			CharacterAppearance.load_profile(path).hat_id == hat, "Hat survives reload: %s" % hat
		)
	for id in NEW_TOPS:
		appearance.body_id = id
		appearance.save_profile(path)
		var loaded := CharacterAppearance.load_profile(path)
		check.call(
			loaded.body_id == id and loaded.body_label() == loaded.resolved_skin().display_name,
			"Top survives reload: %s" % id
		)
	var removed := ConfigFile.new()
	removed.set_value("appearance", "hat", 42)
	removed.set_value("appearance", "body", ["puffer_vest"])
	ProfileStore.save_file(removed, path)
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
	var tint := CharacterAppearance.PALETTE[3]
	var built := 0
	var failures := PackedStringArray()
	for skin in SkinCatalog.definitions():
		for hat in CharacterHats.IDS:
			var model := ChairModel.new()
			model.build(tint, skin, hat)
			var ok := (
				model.body.has_node("ContinuousBody")
				and model.body.has_node("Hat") == (hat != &"none")
				and (
					model.body.has_node("Clothing") == (skin.garment != CharacterSkin.Garment.NONE)
				)
			)
			if not ok:
				failures.append("%s+%s" % [skin.id, hat])
			built += 1
			model.free()
	check.call(
		failures.is_empty() and built == SkinCatalog.PATHS.size() * CharacterHats.IDS.size(),
		"Every hat builds with every top: %s" % ", ".join(failures)
	)
	# Shared immutable shells; per-character fabric materials.
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


func _check_visual_only(tree: SceneTree, check: Callable) -> void:
	var scene := load("res://game/chair/chair.tscn") as PackedScene
	var reference := _physics_signature(tree, scene, SkinCatalog.default_definition(), &"none")
	var matches := true
	for skin in SkinCatalog.definitions():
		for hat in [&"none", &"wizard_hat", &"headphones"]:
			if _physics_signature(tree, scene, skin, hat) != reference:
				matches = false
	check.call(matches, "Cosmetics never change chair mass, collision or tuning")
	await tree.process_frame


func _physics_signature(
	tree: SceneTree, scene: PackedScene, skin: CharacterSkin, hat: StringName
) -> Array:
	var chair := scene.instantiate() as Chair
	chair.skin = skin
	chair.hat_id = hat
	tree.root.add_child(chair)
	var shape := (chair.get_node("CollisionShape2D") as CollisionShape2D).shape as CapsuleShape2D
	var signature := [
		chair.mass,
		chair.inertia,
		chair.size_scale,
		shape.radius,
		shape.height,
		chair.collision_layer,
		chair.collision_mask,
		chair.tuning,
	]
	chair.free()
	return signature
