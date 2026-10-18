extends NetSession
## Scriptable session double for app tests: no sockets; every request is recorded.

var host_result := OK
var join_result := OK
var calls: Array = []
var setups: Array[Dictionary] = []
var appearance_sends := 0
## Appearance sends counted when the latest host() or join() began.
var appearance_before_connect := -1
var start_requests := 0
var _fake_online := false
var _fake_hosting := false
var _fake_peer := 1


func host(port: int = DEFAULT_PORT) -> Error:
	calls.append(["host", port])
	appearance_before_connect = appearance_sends
	if host_result == OK:
		_fake_online = true
		_fake_hosting = true
		_fake_peer = 1
		set_players([player(1, "Studio Mac", CharacterAppearance.PALETTE[0])])
	return host_result


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	calls.append(["join", address, port])
	appearance_before_connect = appearance_sends
	if join_result == OK:
		_fake_online = true
		_fake_hosting = false
		_fake_peer = 2
		lobby = {"players": [], "setup": {}, "in_match": false}
	return join_result


## Silent, like the real session: no session_closed.
func leave() -> void:
	calls.append(["leave"])
	_fake_online = false
	_fake_hosting = false


func is_online() -> bool:
	return _fake_online


func is_host() -> bool:
	return _fake_hosting


func local_peer() -> int:
	return _fake_peer


func set_local_appearance(_appearance: CharacterAppearance) -> void:
	appearance_sends += 1


func set_setup(player_count: int, wins_needed: int, stages: Array[StringName]) -> void:
	var setup := {"player_count": player_count, "wins_needed": wins_needed, "stages": stages}
	setups.append(setup)
	lobby.setup = setup
	lobby_changed.emit()


func start_match() -> void:
	start_requests += 1


func called(method: String) -> bool:
	return calls.any(func(call: Array) -> bool: return call[0] == method)


## Replace the lobby's players as a host broadcast would.
func set_players(players: Array) -> void:
	lobby.players = players
	lobby_changed.emit()


static func player(peer: int, display_name: String, colour: Color) -> Dictionary:
	return {
		"peer": peer,
		"name": display_name,
		"hat_id": &"none",
		"top_id": &"none",
		"colour_id": &"random",
		"colour": colour,
	}
