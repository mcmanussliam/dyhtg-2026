extends RefCounted
## Appearance settings resolve once and become independent match snapshots.


func run(tree: SceneTree, check: Callable) -> void:
	var appearance := CharacterAppearance.new()
	check.call(
		(
			appearance.colour_id == CharacterAppearance.RANDOM
			and appearance.hat_id == CharacterAppearance.NONE
			and appearance.body_id == CharacterAppearance.NONE
			and appearance.chair_id == CharacterAppearance.NONE
		),
		"Appearance defaults to Random colour and no equipped cosmetics"
	)
	for hat in CharacterHats.IDS:
		check.call(appearance.hat_id == hat, "Hat cycle includes %s" % hat)
		var hat_copy := appearance.validated_copy()
		check.call(hat_copy.hat_id == hat, "Hat choice survives appearance snapshots")
		var model := ChairModel.new()
		model.build(Color("72d9ae"), appearance.resolved_skin(), hat)
		check.call(
			model.body.has_node("Hat") == (hat != &"none"),
			"Hat attachment matches the selected slot"
		)
		model.free()
		appearance.cycle_hat()
	check.call(appearance.hat_id == &"none", "Hat choices wrap back to None")
	check.call(
		CosmeticColours.logo_ink(Color.WHITE) == Color.BLACK, "Bright shirts use black logo ink"
	)
	check.call(
		CosmeticColours.logo_ink(Color.BLACK) == Color.WHITE, "Dark shirts use white logo ink"
	)
	for base in CharacterAppearance.PALETTE:
		var fabric := CosmeticColours.fabric(base)
		var ink := CosmeticColours.logo_ink(fabric)
		var lighter := maxf(
			fabric.srgb_to_linear().get_luminance(), ink.srgb_to_linear().get_luminance()
		)
		var darker := minf(
			fabric.srgb_to_linear().get_luminance(), ink.srgb_to_linear().get_luminance()
		)
		check.call(
			(lighter + 0.05) / (darker + 0.05) >= 4.5, "Palette shirt has contrasting logo ink"
		)
		check.call(
			fabric.s > base.s and fabric.v < base.v,
			"Clothing uses a richer version of its body colour"
		)
	var colour := appearance.resolved_colour()
	check.call(colour in CharacterAppearance.PALETTE, "Random resolves to a supported colour")
	check.call(appearance.resolved_colour() == colour, "Random stays stable across preview updates")
	var snapshot := appearance.validated_copy()
	check.call(
		snapshot != appearance and snapshot.resolved_colour() == colour,
		"Appearance snapshot preserves the previewed random colour"
	)
	appearance.cycle_colour()
	check.call(
		appearance.colour_id == &"yellow" and appearance.colour_label() == "Yellow",
		"Colour choices wrap from Random into named palette entries"
	)
	check.call(
		snapshot.colour_id == CharacterAppearance.RANDOM and snapshot.resolved_colour() == colour,
		"Editing customization never mutates a running match snapshot"
	)
	appearance.colour_id = &"cream"
	var cream := appearance.resolved_colour()
	appearance.colour_id = CharacterAppearance.RANDOM
	check.call(appearance.resolved_colour() != cream, "Choosing Random changes the previous colour")
	appearance.colour_id = &"missing"
	appearance.hat_id = &"unimplemented"
	appearance.body_id = &"unimplemented"
	appearance.chair_id = &"unimplemented"
	var validated := appearance.validated_copy()
	check.call(
		(
			validated.colour_id == CharacterAppearance.RANDOM
			and validated.hat_id == CharacterAppearance.NONE
			and validated.body_id == CharacterAppearance.NONE
			and validated.chair_id == CharacterAppearance.NONE
		),
		"Unsupported cosmetic IDs validate back to implemented defaults"
	)
	var config := MatchConfig.new()
	config.appearance = snapshot
	var match_config := config.validated_copy()
	check.call(
		match_config.appearance != config.appearance and match_config.player_colour == colour,
		"Match configuration owns an independent appearance snapshot"
	)
	appearance.body_id = CharacterAppearance.NONE
	appearance.cycle_body()
	check.call(
		appearance.body_id == &"jpmorgan_tshirt", "Body options include the registered T-shirt"
	)
	var shirt := appearance.resolved_skin()
	check.call(shirt.chest_logo != null, "JPMorgan skin provides its chest logo texture")
	check.call(
		shirt.body_mesh == SkinCatalog.default_definition().body_mesh,
		"T-shirt preserves the original character geometry"
	)
	check.call(appearance.body_label() == "JPMorgan", "Clothing uses its concise display name")
	var shirt_snapshot := appearance.validated_copy()
	appearance.cycle_body()
	check.call(appearance.body_id == &"hoodie", "Tops include Hoodie")
	appearance.cycle_body()
	check.call(appearance.body_id == CharacterAppearance.NONE, "Body cycles back to no clothing")
	check.call(
		shirt_snapshot.body_id == &"jpmorgan_tshirt",
		"Editing clothing leaves a running snapshot unchanged"
	)
	appearance.body_id = &"jpmorgan_tshirt"
	appearance.hat_id = &"cap"
	var path := "user://appearance_test_%d.cfg" % Time.get_ticks_usec()
	appearance.colour_id = &"blue"
	check.call(appearance.save_profile(path) == OK, "Appearance profile saves atomically")
	var loaded := CharacterAppearance.load_profile(path)
	check.call(
		(
			loaded.colour_id == &"blue"
			and loaded.resolved_colour() == appearance.resolved_colour()
			and loaded.body_id == &"jpmorgan_tshirt"
			and loaded.hat_id == &"cap"
		),
		"Named colour survives profile reload"
	)
	appearance.colour_id = CharacterAppearance.RANDOM
	check.call(
		appearance.save_profile(path) == OK, "Appearance profile safely replaces an existing save"
	)
	check.call(
		CharacterAppearance.load_profile(path).colour_id == CharacterAppearance.RANDOM,
		"Random persists as a choice rather than a permanently resolved colour"
	)
	var legacy := ConfigFile.new()
	legacy.set_value("appearance", "hat", "cowboy_hat")
	legacy.set_value("appearance", "body", "bikini")
	legacy.set_value("appearance", "colour", "blue")
	ProfileStore.save_file(legacy, path)
	var migrated := CharacterAppearance.load_profile(path)
	check.call(
		(
			migrated.hat_id == CharacterAppearance.NONE
			and migrated.body_id == CharacterAppearance.NONE
		),
		"Removed cosmetics in saved profiles fall back to None"
	)
	check.call(migrated.colour_id == &"blue", "Removed cosmetics preserve the saved colour")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await tree.process_frame
