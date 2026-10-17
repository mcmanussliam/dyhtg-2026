extends SceneTree
## Match, stage and two-key menu regression runner.

const SUITES = [
	preload("res://tests/input/test_pit_pilot_physics.gd"),
	preload("res://tests/stage/test_bull_stage.gd"),
	preload("res://tests/chair/test_gap_physics.gd"),
	preload("res://tests/stage/test_pit_stage.gd"),
	preload("res://tests/props/test_loose_props.gd"),
	preload("res://tests/chair/test_edge_survival.gd"),
	preload("res://tests/content/test_content_definitions.gd"),
	preload("res://tests/match/test_result_progression.gd"),
	preload("res://tests/match/test_spectator_speed.gd"),
	preload("res://tests/settings/test_settings.gd"),
	preload("res://tests/chair/test_movement_dynamics.gd"),
	preload("res://tests/match/test_match_state.gd"),
	preload("res://tests/character/test_character_appearance.gd"),
	preload("res://tests/stage/test_stage.gd"),
	preload("res://tests/props/test_props.gd"),
	preload("res://tests/render/test_render_resources.gd"),
	preload("res://tests/input/test_pilot.gd"),
	preload("res://tests/ui/test_menu.gd"),
	preload("res://tests/chair/test_fall.gd"),
	preload("res://tests/match/test_round_flow.gd"),
	preload("res://tests/match/test_round_render.gd"),
	preload("res://tests/input/test_pilot_physics.gd"),
	preload("res://tests/app/test_app_flow.gd"),
	preload("res://tests/match/test_large_roster.gd"),
	preload("res://tests/input/test_deadlock_physics.gd"),
	preload("res://tests/stage/test_crumbling_stages.gd"),
	preload("res://tests/input/test_crowded_crumbling_physics.gd"),
	preload("res://tests/props/test_falling_prop_collision.gd"),
	preload("res://tests/stage/test_hr_training.gd"),
	preload("res://tests/stage/test_faulty_floors.gd"),
	preload("res://tests/stage/test_under_construction.gd"),
	preload("res://tests/ui/test_portrait_framing.gd"),
	preload("res://tests/ui/test_map_selection.gd"),
]

var _checks: int = 0
var _failures := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	for script in SUITES:
		await script.new().run(self, _check)
	print("Match checks: %d; failures: %d" % [_checks, _failures.size()])
	for failure in _failures:
		push_error(failure)
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)
