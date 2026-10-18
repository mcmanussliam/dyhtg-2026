class_name SkinCatalog
extends RefCounted
## Explicit, stable content registration; profile files never load arbitrary paths.

const PATHS := [
	"res://game/character/skins/default/default.tres",
	"res://game/character/skins/jpmorgan/jpmorgan_tshirt.tres",
	"res://game/character/skins/hoodie/hoodie.tres",
	"res://game/character/skins/jpmorgan/jpmorgan_hoodie.tres",
	"res://game/character/skins/tshirt/tshirt.tres",
	"res://game/character/skins/tank_top/tank_top.tres",
	"res://game/character/skins/high_vis/high_vis.tres",
	"res://game/character/skins/puffer_vest/puffer_vest.tres",
	"res://game/character/skins/waistcoat/waistcoat.tres",
	"res://game/character/skins/fleece_vest/fleece_vest.tres",
	"res://game/character/skins/tie/tie.tres",
	"res://game/character/skins/bow_tie/bow_tie.tres",
	"res://game/character/skins/scarf/scarf.tres",
]


static func default_definition() -> CharacterSkin:
	return load(PATHS[0]) as CharacterSkin


static func definitions() -> Array[CharacterSkin]:
	var skins: Array[CharacterSkin] = []
	for path in PATHS:
		var skin := load(path) as CharacterSkin
		if skin != null and skin.is_valid():
			skins.append(skin)
	return skins
