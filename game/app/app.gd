class_name GameApp
extends Node
## Owns screen lifetime and translates menu intentions into match operations.

var config := MatchConfig.new()
var match_controller: MatchController
var current_menu: TwoKeyMenu
var screen: Control
var _ui: CanvasLayer
var _guard := false
var _pending_action: Callable
var _setup := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)
	show_home()


func _process(_delta: float) -> void:
	if _guard and not _arrows_held():
		_guard = false
		if is_instance_valid(current_menu):
			current_menu.set_process_unhandled_input(true)
		if _pending_action.is_valid():
			var action := _pending_action
			_pending_action = Callable()
			action.call()


func _input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.physical_keycode == KEY_ESCAPE
		and event.pressed
		and not event.echo
		and is_instance_valid(match_controller)
		and is_instance_valid(match_controller.round)
		and match_controller.round.phase != RoundController.Phase.FINISHED
	):
		get_tree().paused = not get_tree().paused
		get_viewport().set_input_as_handled()
		return
	if _guard and (event.is_action("menu_next") or event.is_action("menu_activate")):
		get_viewport().set_input_as_handled()


func _arrows_held() -> bool:
	return Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_RIGHT)


func _guard_transition(action: Callable = Callable()) -> void:
	_guard = true
	_pending_action = action
	if is_instance_valid(current_menu):
		current_menu.set_process_unhandled_input(false)


func _clear_screen() -> void:
	current_menu = null
	if is_instance_valid(screen):
		_ui.remove_child(screen)
		screen.queue_free()
	screen = null


func _clear_match() -> void:
	get_tree().paused = false
	if is_instance_valid(match_controller):
		remove_child(match_controller)
		match_controller.queue_free()
	match_controller = null


func show_home() -> void:
	_clear_screen()
	_clear_match()
	_setup = false
	_build_office_page()
	current_menu.set_items(PackedStringArray(["Play", "Quit"]))
	current_menu.activated.connect(_home_action)
	_guard_transition()


func show_setup() -> void:
	_clear_screen()
	_setup = true
	_build_office_page()
	_setup_labels()
	current_menu.activated.connect(_setup_action)
	_guard_transition()


func _build_office_page() -> void:
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(screen)
	screen.add_child(HomeBackdrop.new())
	current_menu = TwoKeyMenu.new()
	current_menu.position = Vector2(90, 270 if _setup else 330)
	current_menu.size = Vector2(440, 292 if _setup else 140)
	screen.add_child(current_menu)


func _setup_labels() -> void:
	(
		current_menu
		. set_items(
			PackedStringArray(
				[
					"AI opponents: %d" % config.ai_count,
					"First to: %d wins" % config.wins_needed,
					"Start match",
					"Back",
				]
			)
		)
	)


func _home_action(index: int) -> void:
	if index == 0:
		show_setup.call_deferred()
	else:
		get_tree().quit()


func _setup_action(index: int) -> void:
	match index:
		0:
			config.ai_count = config.ai_count % 3 + 1
			_setup_labels()
		1:
			config.wins_needed = config.wins_needed % 5 + 1
			_setup_labels()
		2:
			_guard_transition(_start_match)
		3:
			show_home.call_deferred()


func _start_match() -> void:
	_clear_screen()
	_clear_match()
	match_controller = MatchController.new()
	match_controller.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(match_controller)
	match_controller.results_ready.connect(_show_results)
	match_controller.start(config)


func _show_results(
	participants: Array[Dictionary],
	winner_id: int,
	target_wins: int,
	final_result: bool,
	round_number: int
) -> void:
	_clear_screen()
	var results := ResultsScreen.new()
	screen = results
	_ui.add_child(results)
	results.present(participants, winner_id, target_wins, final_result, round_number)
	results.action_requested.connect(_result_action)
	_guard_transition()


func _result_action(action: StringName) -> void:
	match action:
		&"continue":
			_guard_transition(_continue_round)
		&"rematch":
			_guard_transition(_start_match)
		&"home":
			show_home.call_deferred()


func _continue_round() -> void:
	_clear_screen()
	match_controller.continue_round()
