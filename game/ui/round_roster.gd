class_name RoundRoster
extends HBoxContainer
## Static snapshots of the real character models; elimination only changes their UI tint.

const PORTRAIT_SHADER := preload("res://game/ui/roster_portrait.gdshader")

var participants: Array[Dictionary] = []
var _portraits: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	var row_width := participants.size() * 100 - 12
	offset_left = -row_width * 0.5
	offset_right = row_width * 0.5
	offset_top = -120
	offset_bottom = -32
	add_theme_constant_override("separation", 12)
	for participant in participants:
		var portrait := ScoreCharacter.new()
		portrait.colour = participant.colour
		portrait.skin = participant.get("skin", SkinCatalog.default_definition())
		portrait.display_size = Vector2(88, 88)
		portrait.animated = false
		portrait.close_up = true
		add_child(portrait)
		var tint := ShaderMaterial.new()
		tint.shader = PORTRAIT_SHADER
		portrait.material = tint
		_portraits[participant.id] = portrait


func mark_eliminated(seat: int) -> void:
	if _portraits.has(seat):
		_portraits[seat].material.set_shader_parameter("eliminated", 1.0)


func is_eliminated(seat: int) -> bool:
	return (
		_portraits.has(seat) and _portraits[seat].material.get_shader_parameter("eliminated") == 1.0
	)
