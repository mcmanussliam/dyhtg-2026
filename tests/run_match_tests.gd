extends SceneTree
## Match, stage and two-key menu regression runner.

const SUITES = [
	preload("res://tests/test_match_state.gd"),
	preload("res://tests/test_stage.gd"),
	preload("res://tests/test_props.gd"),
	preload("res://tests/test_render_resources.gd"),
	preload("res://tests/test_pilot.gd"),
	preload("res://tests/test_menu.gd"),
	preload("res://tests/test_fall.gd"),
	preload("res://tests/test_round_flow.gd"),
	preload("res://tests/test_round_render.gd"),
	preload("res://tests/test_pilot_physics.gd"),
	preload("res://tests/test_app_flow.gd"),
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
