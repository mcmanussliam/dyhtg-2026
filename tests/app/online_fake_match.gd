extends MatchController
## Match double: records the online start and forwarded result actions, simulates nothing.

var online_start: Array = []
var result_actions: Array[StringName] = []
var match_over := false


func _init() -> void:
	# The match layer adds `round_began`; a stub without it gets an equivalent here.
	if not has_signal(&"round_began"):
		add_user_signal(&"round_began", [{"name": "round_number", "type": TYPE_INT}])


func start_online(net: NetSession, roster: Array, setup: Dictionary) -> void:
	online_start = [net, roster, setup]


func handle_result_action(action: StringName) -> void:
	result_actions.append(action)


func is_match_over() -> bool:
	return match_over
