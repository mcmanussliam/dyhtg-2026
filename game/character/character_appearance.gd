class_name CharacterAppearance
extends Resource
## Cosmetic selections, separate from UI and match rules. Random resolves once per selection.

const NONE := &"none"
const RANDOM := &"random"
const COLOUR_IDS: Array[StringName] = [
	RANDOM, &"yellow", &"mint", &"pink", &"blue", &"lilac", &"coral", &"cream"
]
const COLOUR_NAMES := ["Random", "Yellow", "Mint", "Pink", "Blue", "Lilac", "Coral", "Cream"]
const PALETTE: Array[Color] = [
	Color("f4d782"),
	Color("72d9ae"),
	Color("f498b0"),
	Color("94b9f4"),
	Color("b3a0e0"),
	Color("ed956f"),
	Color("e8e1c1")
]

@export var hat_id: StringName = NONE
@export var body_id: StringName = NONE
@export var chair_id: StringName = NONE
@export var colour_id: StringName = RANDOM:
	set(value):
		colour_id = value
		_has_resolved_colour = false

var _resolved_colour := Color.TRANSPARENT
var _has_resolved_colour := false


func resolved_colour() -> Color:
	if not _has_resolved_colour:
		var index := COLOUR_IDS.find(colour_id)
		if index > 0:
			_resolved_colour = PALETTE[index - 1]
		else:
			var choices := PALETTE.duplicate()
			choices.erase(_resolved_colour)
			_resolved_colour = choices.pick_random()
		_has_resolved_colour = true
	return _resolved_colour


func colour_label() -> String:
	return COLOUR_NAMES[maxi(COLOUR_IDS.find(colour_id), 0)]


func cycle_colour() -> void:
	colour_id = COLOUR_IDS[(COLOUR_IDS.find(colour_id) + 1) % COLOUR_IDS.size()]


func validated_copy() -> CharacterAppearance:
	var copy := CharacterAppearance.new()
	# Only registered cosmetic IDs can reach a match.
	copy.hat_id = hat_id if hat_id in CharacterHats.IDS else NONE
	copy.colour_id = colour_id if colour_id in COLOUR_IDS else RANDOM
	for skin in SkinCatalog.definitions():
		if skin.is_valid() and skin.id == body_id:
			copy.body_id = body_id
	copy._resolved_colour = resolved_colour()
	copy._has_resolved_colour = true
	return copy


static func load_profile(path: String) -> CharacterAppearance:
	var appearance := CharacterAppearance.new()
	var file := ProfileStore.load_file(path)
	var saved: Variant = file.get_value("appearance", "colour", String(RANDOM))
	if saved is String or saved is StringName:
		var id := StringName(saved)
		appearance.colour_id = id if id in COLOUR_IDS else RANDOM
	var body: Variant = file.get_value("appearance", "body", String(NONE))
	if body is String or body is StringName:
		for skin in SkinCatalog.definitions():
			if skin.is_valid() and skin.id == StringName(body):
				appearance.body_id = skin.id
	var hat: Variant = file.get_value("appearance", "hat", String(NONE))
	if (hat is String or hat is StringName) and StringName(hat) in CharacterHats.IDS:
		appearance.hat_id = StringName(hat)
	return appearance


func save_profile(path: String) -> Error:
	var file := ConfigFile.new()
	var validated := validated_copy()
	file.set_value("appearance", "hat", String(validated.hat_id))
	file.set_value("appearance", "body", String(validated.body_id))
	file.set_value("appearance", "chair", String(validated.chair_id))
	file.set_value("appearance", "colour", String(validated.colour_id))
	return ProfileStore.save_file(file, path)


func resolved_skin() -> CharacterSkin:
	for skin in SkinCatalog.definitions():
		if skin.is_valid() and skin.id == body_id:
			return skin
	return SkinCatalog.default_definition()


func body_label() -> String:
	return "None" if body_id == NONE else resolved_skin().display_name


func cycle_body() -> void:
	var choices: Array[StringName] = [NONE]
	for skin in SkinCatalog.definitions():
		if skin.id != SkinCatalog.default_definition().id:
			choices.append(skin.id)
	body_id = choices[(choices.find(body_id) + 1) % choices.size()]


func hat_label() -> String:
	return CharacterHats.NAMES[maxi(CharacterHats.IDS.find(hat_id), 0)]


func cycle_hat() -> void:
	hat_id = CharacterHats.IDS[(CharacterHats.IDS.find(hat_id) + 1) % CharacterHats.IDS.size()]
