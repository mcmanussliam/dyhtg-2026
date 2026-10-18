class_name GameApp
extends Node
## Owns screen lifetime and translates menu intentions into match and session operations.

## Office-page menus sit this far in from the bottom-left corner.
const MENU_INSET := Vector2(56, 56)
## Rows a page shows before scrolling; nine fit inside the inset at 1280 × 800.
const MAX_VISIBLE_ROWS := 9
## Names of the AI-only colours that follow the customisation palette in MatchState.
const EXTRA_COLOUR_NAMES := ["Teal", "Lime", "Slate"]

@export var config: MatchConfig = MatchConfig.new()
var settings := GameSettings.new()
var settings_path := "user://settings.cfg"
var appearance_path := "user://character_appearance.cfg"
## Session and discovery children; tests may assign doubles before `_ready`.
var net: NetSession
var discovery: LanDiscovery
## ENet is unavailable on the Web build, so Multiplayer is disabled there.
var web_build := OS.has_feature("web")
## Online matches are created from this script; tests may assign a double.
var match_script: Script = MatchController
var match_controller: MatchController
var current_menu: TwoKeyMenu
var screen: Control
var _ui: CanvasLayer
var _guard := false
var _pending_action: Callable
var _backdrop: HomeBackdrop
var _page := &""
var _page_reason := ""
## Host lobby setup, also the config the lobby's map selection edits.
var _lobby_config: MatchConfig
var _lobby_first_option := 0
var _join_targets: Array[Dictionary] = []
var _in_session := false
var _joining := false
var _online_match := false
var _final_result := false


func _ready() -> void:
	if not appearance_path.is_empty():
		config.appearance = CharacterAppearance.load_profile(appearance_path)
	if not settings_path.is_empty():
		settings = GameSettings.load_profile(settings_path)
		settings.apply(get_tree().root)
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)
	_add_session()
	show_home()
	_apply_command_line(parse_command_line(OS.get_cmdline_user_args()))


func _add_session() -> void:
	if net == null:
		net = NetSession.new()
	net.name = "NetSession"
	add_child(net)
	if discovery == null:
		discovery = LanDiscovery.new()
	discovery.name = "LanDiscovery"
	add_child(discovery)
	net.lobby_changed.connect(_on_lobby_changed)
	net.match_started.connect(_on_match_started)
	net.session_closed.connect(_on_session_closed)
	discovery.games_changed.connect(_on_games_changed)


## Demo flags: `--host` and `--join=<ip>`. Player labels are generic.
static func parse_command_line(args: PackedStringArray) -> Dictionary:
	var options := {"host": false, "join": ""}
	for arg in args:
		if arg == "--host":
			options.host = true
		elif arg.begins_with("--join="):
			options.join = arg.trim_prefix("--join=").strip_edges()
	return options


func _apply_command_line(options: Dictionary) -> void:
	if web_build:
		return
	if options.host:
		_host_game()
	elif not String(options.join).is_empty():
		_join_game(options.join, NetSession.DEFAULT_PORT)


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
	_page = &""
	if is_instance_valid(screen):
		_ui.remove_child(screen)
		screen.queue_free()
	screen = null


func _clear_match() -> void:
	if is_instance_valid(match_controller):
		remove_child(match_controller)
		match_controller.queue_free()
	match_controller = null
	_online_match = false


func show_home() -> void:
	_clear_screen()
	_clear_match()
	_build_office_page(null, TwoKeyMenu.height_for(4))
	current_menu.set_items(PackedStringArray(["Play", "Customise", "Settings", "Quit"]))
	current_menu.activated.connect(_home_action)
	_guard_transition()


func show_setup() -> void:
	_clear_screen()
	_build_office_page(null, TwoKeyMenu.height_for(5))
	_setup_labels()
	current_menu.activated.connect(_setup_action)
	_guard_transition()


## Online, the host's lobby maps are edited and every toggle is sent to the session.
func show_map_selection(online := false) -> void:
	_clear_screen()
	var menu := MapSelectionMenu.new()
	menu.config = _lobby_config if online else config
	if online:
		menu.back_requested.connect(func(): show_lobby.call_deferred())
	else:
		menu.back_requested.connect(func(): show_setup.call_deferred())
	_build_office_page(menu, TwoKeyMenu.height_for(5))
	current_menu.offset_right = MENU_INSET.x + 768
	if online:
		_page = &"lobby_maps"
		menu.activated.connect(func(_index: int) -> void: _push_setup())
	_guard_transition()


func show_play() -> void:
	_show_list_page(&"play")
	current_menu.set_items(PackedStringArray(["Single player", "Multiplayer", "Back"]))
	current_menu.set_item_enabled(1, not web_build)
	_fit_menu(3)
	current_menu.activated.connect(_play_action)
	_guard_transition()


func show_multiplayer(reason := "") -> void:
	_show_list_page(&"multiplayer")
	var labels := PackedStringArray(["Host game", "Join game", "Back"])
	var info := PackedInt32Array()
	if not reason.is_empty():
		labels.insert(0, reason)
		info.append(0)
	current_menu.set_items(labels, PackedStringArray(), info)
	_fit_menu(labels.size())
	current_menu.activated.connect(_multiplayer_action.bind(info.size()))
	_guard_transition()


## Games heard on the LAN, refreshed as discovery changes, then Back.
func show_join(reason := "") -> void:
	_show_list_page(&"join", true)
	_page_reason = reason
	discovery.start_listening()
	_join_labels()
	current_menu.activated.connect(_join_action)
	_guard_transition()


## Players with their resolved colours, then host options or read-only host settings.
func show_lobby() -> void:
	_show_list_page(&"lobby", true)
	current_menu.offset_right = MENU_INSET.x + 768
	_lobby_first_option = 0
	net.set_local_appearance(config.appearance)
	_lobby_labels()
	current_menu.activated.connect(_lobby_action)
	_guard_transition()


func _show_list_page(page: StringName, scrollable := false) -> void:
	_clear_screen()
	var menu := TwoKeyMenu.new()
	menu.scrollable = scrollable
	_build_office_page(menu, 0)
	_page = page


func _fit_menu(rows: int) -> void:
	current_menu.offset_top = (-TwoKeyMenu.height_for(mini(rows, MAX_VISIBLE_ROWS)) - MENU_INSET.y)


func _build_office_page(menu: TwoKeyMenu, menu_height: int) -> void:
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
	current_menu.offset_left = MENU_INSET.x
	current_menu.offset_right = MENU_INSET.x + 440
	current_menu.offset_top = -menu_height - MENU_INSET.y
	current_menu.offset_bottom = -MENU_INSET.y


func show_customisation() -> void:
	_clear_screen()
	_build_office_page(null, TwoKeyMenu.height_for(4))
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
	if _in_session:
		net.set_local_appearance(config.appearance)
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
			show_play.call_deferred()
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
			show_play.call_deferred()


func _play_action(index: int) -> void:
	match index:
		0:
			show_setup.call_deferred()
		1:
			show_multiplayer.call_deferred()
		2:
			show_home.call_deferred()


func _multiplayer_action(index: int, offset: int) -> void:
	match index - offset:
		0:
			_host_game.call_deferred()
		1:
			show_join.call_deferred()
		2:
			show_play.call_deferred()


func _host_game() -> void:
	if web_build:
		return
	net.set_local_appearance(config.appearance)
	if net.host() != OK:
		show_multiplayer("Could not host game")
		return
	_in_session = true
	_joining = false
	_lobby_config = MatchConfig.new()
	_lobby_config.player_count = config.player_count
	_lobby_config.wins_needed = config.wins_needed
	_lobby_config.stages = config.stages.duplicate()
	_push_setup()
	show_lobby()


func _join_game(address: String, port: int) -> void:
	if web_build:
		return
	discovery.stop_listening()
	net.set_local_appearance(config.appearance)
	if net.join(address, port) != OK:
		show_join("Could not join game")
		return
	_in_session = true
	_joining = true
	show_lobby()


## Voluntary end (Leave, or a client's Home from results). `leave()` is silent, so the
## caller navigates.
func _leave_session() -> void:
	_in_session = false
	_joining = false
	discovery.stop_listening()
	net.leave()
	_clear_match()


func _join_labels() -> void:
	var previous := ""
	if current_menu.chosen < _join_targets.size():
		previous = _join_key(_join_targets[current_menu.chosen])
	var labels := PackedStringArray()
	var values := PackedStringArray()
	var info := PackedInt32Array()
	_join_targets.clear()
	if not _page_reason.is_empty():
		_add_info_row(labels, values, info, _page_reason)
	if discovery.games.is_empty():
		_add_info_row(labels, values, info, "Searching…")
	for index in discovery.games.size():
		var game: Dictionary = discovery.games[index]
		labels.append("Lobby %d" % (index + 1))
		values.append("%d/%d" % [int(game.get("players", 0)), int(game.get("max", 0))])
		_join_targets.append(game)
	labels.append("Back")
	values.append("")
	_join_targets.append({})
	# Keep the cursor on the same game, or on Back, as games appear and expire.
	for index in _join_targets.size():
		if not info.has(index) and _join_key(_join_targets[index]) == previous:
			current_menu.chosen = index
	current_menu.set_items(labels, values, info)
	_fit_menu(labels.size())


func _add_info_row(
	labels: PackedStringArray, values: PackedStringArray, info: PackedInt32Array, text: String
) -> void:
	info.append(labels.size())
	labels.append(text)
	values.append("")
	_join_targets.append({})


static func _join_key(game: Dictionary) -> String:
	return "%s:%s" % [game.get("address", ""), game.get("port", "")]


func _join_action(index: int) -> void:
	var game := _join_targets[index]
	if game.is_empty():
		discovery.stop_listening()
		show_multiplayer.call_deferred()
	else:
		_join_game.call_deferred(
			String(game.get("address", "")), int(game.get("port", NetSession.DEFAULT_PORT))
		)


func _on_games_changed() -> void:
	if _page == &"join":
		_join_labels()


func _humans() -> int:
	return (net.lobby.get("players", []) as Array).size()


func _lobby_player_count() -> int:
	return clampi(
		maxi(_lobby_config.player_count, _humans()), MatchConfig.MIN_PLAYERS, NetSession.MAX_PLAYERS
	)


func _push_setup() -> void:
	var stages: Array[StringName] = []
	for definition in _lobby_config.stages:
		stages.append(definition.id)
	net.set_setup(_lobby_player_count(), _lobby_config.wins_needed, stages)


func _lobby_labels() -> void:
	var option := maxi(current_menu.chosen - _lobby_first_option, 0)
	var labels := PackedStringArray()
	var values := PackedStringArray()
	var info := PackedInt32Array()
	var players: Array = net.lobby.get("players", [])
	if players.is_empty():
		info.append(0)
		labels.append("Connecting…")
		values.append("")
	for index in players.size():
		var player: Dictionary = players[index]
		info.append(labels.size())
		var colour: Color = player.get("colour", Color.WHITE)
		var host := int(player.get("peer", 0)) == 1
		labels.append(colour_name(colour))
		values.append("Host" if host else "")
		if int(player.get("peer", 0)) == net.local_peer() and is_instance_valid(_backdrop):
			_backdrop.set_colour(colour)
	# Seats nobody has joined yet are played by AI; people joining take them over.
	if not players.is_empty():
		var seats := _lobby_player_count() if net.is_host() else net.lobby_size()
		var ai := seats - players.size()
		if ai > 0:
			info.append(labels.size())
			labels.append("AI players")
			values.append(str(ai))
	var options := PackedStringArray(["Leave"])
	if net.is_host():
		options = PackedStringArray(
			[
				"Players %d" % _lobby_player_count(),
				"First to %d wins" % _lobby_config.wins_needed,
				"Select maps",
				"Start game",
				"Leave",
			]
		)
	elif not players.is_empty():
		var setup: Dictionary = net.lobby.get("setup", {})
		var maps := (setup.get("stages", []) as Array).size()
		for text in [
			"Players %d" % int(setup.get("player_count", players.size())),
			"First to %d wins" % int(setup.get("wins_needed", 3)),
			"%d map%s" % [maps, "" if maps == 1 else "s"],
		]:
			info.append(labels.size())
			labels.append(text)
			values.append("")
	_lobby_first_option = labels.size()
	for text in options:
		labels.append(text)
		values.append("")
	current_menu.chosen = _lobby_first_option + mini(option, options.size() - 1)
	current_menu.set_items(labels, values, info)
	var start := _lobby_first_option + 3 if net.is_host() else -1
	for index in labels.size():
		current_menu.set_item_enabled(index, index != start or not _lobby_config.stages.is_empty())
	_fit_menu(labels.size())


func _lobby_action(index: int) -> void:
	var option := index - _lobby_first_option
	if not net.is_host():
		if option == 0:
			_leave_session()
			show_multiplayer.call_deferred()
		return
	match option:
		0:
			_lobby_config.player_count = (
				maxi(_humans(), MatchConfig.MIN_PLAYERS)
				if _lobby_player_count() >= NetSession.MAX_PLAYERS
				else _lobby_player_count() + 1
			)
			_push_setup()
			_lobby_labels()
		1:
			_lobby_config.wins_needed = _lobby_config.wins_needed % 5 + 1
			_push_setup()
			_lobby_labels()
		2:
			show_map_selection.call_deferred(true)
		3:
			if not _lobby_config.stages.is_empty():
				net.start_match()
		4:
			_leave_session()
			show_multiplayer.call_deferred()


func _on_lobby_changed() -> void:
	if not _in_session:
		return
	if _joining:
		for player: Dictionary in net.lobby.get("players", []):
			_joining = _joining and int(player.get("peer", 0)) != net.local_peer()
	if _page == &"lobby":
		_lobby_labels()


## Every peer, host included: replace the menus with the online match.
func _on_match_started(roster: Array, setup: Dictionary) -> void:
	if not _in_session:
		return
	_joining = false
	_clear_screen()
	_clear_match()
	match_controller = match_script.new() as MatchController
	add_child(match_controller)
	_online_match = true
	match_controller.results_ready.connect(_show_results)
	match_controller.online_finished.connect(_on_online_finished)
	if match_controller.has_signal(&"round_began"):
		match_controller.connect(&"round_began", _on_online_round_began)
	match_controller.start_online(net, roster, setup)


func _on_online_finished() -> void:
	_return_to_lobby.call_deferred()


func _return_to_lobby() -> void:
	_clear_match()
	if _in_session:
		show_lobby()


func _on_session_closed(reason: String) -> void:
	if not _in_session:
		return
	var refused := _joining
	_in_session = false
	_joining = false
	discovery.stop_listening()
	_close_session.call_deferred(refused, reason)


func _close_session(refused: bool, reason: String) -> void:
	_clear_match()
	if refused:
		show_join(reason)
	else:
		show_multiplayer(reason)


## Display name for a resolved lobby or roster colour.
static func colour_name(colour: Color) -> String:
	for index in MatchState.COLOURS.size():
		if MatchState.COLOURS[index].is_equal_approx(colour):
			if index < CharacterAppearance.PALETTE.size():
				return CharacterAppearance.COLOUR_NAMES[index + 1]
			return EXTRA_COLOUR_NAMES[index - CharacterAppearance.PALETTE.size()]
	return ""


func _start_match() -> void:
	if config.stages.is_empty():
		return
	_clear_screen()
	_clear_match()
	match_controller = MatchController.new()
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
	_final_result = final_result
	var results := ResultsScreen.new()
	screen = results
	_ui.add_child(results)
	results.present(participants, winner_id, target_wins, final_result, round_number)
	results.action_requested.connect(_result_action)
	_guard_transition()


func _result_action(action: StringName) -> void:
	if _online_match:
		_online_result_action(action)
		return
	match action:
		&"continue":
			_continue_round.call_deferred()
		&"home":
			show_home.call_deferred()


## Only the host's choice advances everyone; its next round (`round_began`) closes the
## results. A client's Home mid-match leaves the session; once the match is over every
## peer waits for `online_finished` instead, because that screen requests Home itself.
func _online_result_action(action: StringName) -> void:
	var over: bool = (
		match_controller.call(&"is_match_over")
		if match_controller.has_method(&"is_match_over")
		else _final_result
	)
	var waits_for_round := match_controller.has_signal(&"round_began") and not net.is_host()
	match_controller.handle_result_action(action)
	if action == &"continue":
		if not waits_for_round:
			_clear_screen.call_deferred()
	elif action == &"home" and not net.is_host() and not over:
		_leave_session()
		show_multiplayer.call_deferred()


func _on_online_round_began(_round_number: int) -> void:
	if screen is ResultsScreen:
		_clear_screen()


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
	_build_office_page(menu, TwoKeyMenu.height_for(SettingsMenu.LABELS.size()))
	current_menu.offset_right = MENU_INSET.x + 550
	_guard_transition()
