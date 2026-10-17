class_name SkinCatalog
extends RefCounted
## Explicit, stable content registration; profile files never load arbitrary paths.

const PATHS := [
	"res://game/character/skins/default.tres",
	"res://game/character/skins/jpmorgan_tshirt.tres",
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
