class_name GameApp
extends Node
## Owns screen lifetime and translates menu intentions into match operations.

@export var config: MatchConfig = MatchConfig.new()
var settings := GameSettings.new()
var settings_path := "user://settings.cfg"
var appearance_path := "user://character_appearance.cfg"
var match_controller: MatchController
var current_menu: TwoKeyMenu
var screen: Control
var _ui: CanvasLayer
var _guard := false
var _pending_action: Callable
var _backdrop: HomeBackdrop


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not appearance_path.is_empty():
		config.appearance = CharacterAppearance.load_profile(appearance_path)
	if not settings_path.is_empty():
		settings = GameSettings.load_profile(settings_path)
		settings.apply(get_tree().root)
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
	_pending_action = Callable()
	_guard = false
	current_menu = null
	_backdrop = null
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
	_build_office_page()
	current_menu.set_items(PackedStringArray(["Play", "Customise", "Settings", "Quit"]))
	current_menu.activated.connect(_home_action)
	_guard_transition()


func show_setup() -> void:
	_clear_screen()
	_build_office_page(null, 368)
	_setup_labels()
	current_menu.activated.connect(_setup_action)
	_guard_transition()


func show_map_selection() -> void:
	_clear_screen()
	var menu := MapSelectionMenu.new()
	menu.config = config
	menu.back_requested.connect(func(): show_setup.call_deferred())
	_build_office_page(menu, 368)
	current_menu.offset_right = 800
	_guard_transition()


func _build_office_page(menu: TwoKeyMenu = null, menu_height: int = 292) -> void:
	screen = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.add_child(screen)
	_backdrop = HomeBackdrop.new()
	_backdrop.character_colour = config.player_colour
	_backdrop.skin = config.appearance.resolved_skin()
	_backdrop.hat_id = config.appearance.hat_id
	screen.add_child(_backdrop)
	current_menu = menu if menu != null else TwoKeyMenu.new()
	screen.add_child(current_menu)
	current_menu.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	current_menu.offset_left = 32
	current_menu.offset_right = 472
	current_menu.offset_top = -menu_height - 32
	current_menu.offset_bottom = -32


func show_customisation() -> void:
	_clear_screen()
	_build_office_page(null, 222)
	_customisation_labels()
	current_menu.activated.connect(_customisation_action)
	_guard_transition()


func _customisation_labels() -> void:
	current_menu.set_items(
		PackedStringArray(["Hat", "Top", "Colour", "Back"]),
		PackedStringArray(
			[
				config.appearance.hat_label(),
				config.appearance.body_label(),
				config.appearance.colour_label(),
				""
			]
		)
	)


func _customisation_action(index: int) -> void:
	if index == 3:
		show_home.call_deferred()
		return
	if index == 0:
		config.appearance.cycle_hat()
		_backdrop.set_hat(config.appearance.hat_id)
	elif index == 1:
		config.appearance.cycle_body()
		_backdrop.set_skin(config.appearance.resolved_skin())
	elif index == 2:
		config.appearance.cycle_colour()
		_backdrop.set_colour(config.player_colour)
	else:
		return
	_customisation_labels()
	if not appearance_path.is_empty():
		var error := config.appearance.save_profile(appearance_path)
		if error != OK:
			push_warning("Could not save character appearance: %s" % error_string(error))


func _setup_labels() -> void:
	var labels := PackedStringArray(
		[
			"Players %d" % config.player_count,
			"First to %d wins" % config.wins_needed,
			"Select maps",
			"Start match",
			"Back",
		]
	)
	current_menu.set_items(labels)
	current_menu.set_item_enabled(3, not config.stages.is_empty())


func _home_action(index: int) -> void:
	match index:
		0:
			show_setup.call_deferred()
		1:
			show_customisation.call_deferred()
		2:
			show_settings.call_deferred()
		3:
			get_tree().quit()


func _setup_action(index: int) -> void:
	match index:
		0:
			config.player_count = (
				MatchConfig.MIN_PLAYERS
				if config.player_count >= MatchConfig.MAX_PLAYERS
				else config.player_count + 1
			)
			_setup_labels()
		1:
			config.wins_needed = config.wins_needed % 5 + 1
			_setup_labels()
		2:
			show_map_selection.call_deferred()
		3:
			_guard_transition(_start_match)
		4:
			show_home.call_deferred()


func _start_match() -> void:
	if config.stages.is_empty():
		return
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
			_continue_round.call_deferred()
		&"home":
			show_home.call_deferred()


func _continue_round() -> void:
	_clear_screen()
	match_controller.continue_round()


func show_settings() -> void:
	_clear_screen()
	var menu := SettingsMenu.new()
	menu.settings = settings
	menu.profile_path = settings_path
	menu.apply_changes = not settings_path.is_empty()
	menu.back_requested.connect(func(): show_home.call_deferred())
	_build_office_page(menu, 128)
	current_menu.offset_right = 582
	_guard_transition()
