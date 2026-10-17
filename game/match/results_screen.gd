class_name ResultsScreen
extends Control
## Only character models and earned stars; the final score adds confetti.

signal action_requested(action: StringName)

const ROUND_DISPLAY_SECONDS := 3.0
const FINAL_DISPLAY_SECONDS := 5.0

var _elapsed := 0.0
var _action_sent := false
var _content: Control
var _participants: Array[Dictionary] = []
var _winner_id := -1
var _final_result := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not _participants.is_empty():
		_build()


func present(
	participants: Array[Dictionary],
	winner_id: int,
	_target_wins: int,
	final_result: bool,
	_round_number: int
) -> void:
	_elapsed = 0.0
	_action_sent = false
	set_process(true)
	_participants = participants.duplicate(true)
	_winner_id = winner_id
	_final_result = final_result
	if is_inside_tree():
		_build()


func _build() -> void:
	if is_instance_valid(_content):
		remove_child(_content)
		_content.queue_free()
	_content = Control.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(background)
	var column := GridContainer.new()
	column.columns = 2 if _participants.size() > 5 else 1
	var rows := ceili(float(_participants.size()) / column.columns)
	column.position = Vector2(
		94 if column.columns == 2 else 360, (800.0 - rows * 144.0 + 12.0) / 2.0
	)
	column.add_theme_constant_override("h_separation", 32)
	column.add_theme_constant_override("v_separation", 12)
	_content.add_child(column)
	for participant in _participants:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 40)
		column.add_child(row)
		var character := ScoreCharacter.new()
		character.colour = participant.colour
		character.skin = participant.get("skin", SkinCatalog.default_definition())
		character.hat_id = participant.get("hat_id", &"none")
		row.add_child(character)
		var tokens := WinTokens.new()
		tokens.token_count = participant.wins
		tokens.animate_newest = participant.id == _winner_id
		tokens.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tokens)
	if _final_result:
		_content.add_child(VictoryConfetti.new())


func _unhandled_input(event: InputEvent) -> void:
	if _action_sent or not is_visible_in_tree() or event.is_echo():
		return
	if event.is_action_pressed("menu_next"):
		get_viewport().set_input_as_handled()
		_request_action(&"home")
	elif event.is_action_pressed("menu_activate"):
		get_viewport().set_input_as_handled()
		_request_action(&"home" if _final_result else &"continue")


func _process(delta: float) -> void:
	if _participants.is_empty() or _action_sent:
		return
	_elapsed += delta
	var duration := FINAL_DISPLAY_SECONDS if _final_result else ROUND_DISPLAY_SECONDS
	if _elapsed >= duration:
		_request_action(&"home" if _final_result else &"continue")


func _request_action(action: StringName) -> void:
	if _action_sent:
		return
	_action_sent = true
	set_process(false)
	action_requested.emit(action)
