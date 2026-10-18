extends LanDiscovery
## Discovery double: records listening and any beacon use, and lists scripted games.

var listening := false
## The session runs the host beacon, so the app must never touch it.
var beacon_used := false


func start_beacon(_name: String, _port: int, _players: int, _max_players: int) -> void:
	beacon_used = true


func update_beacon(_players: int) -> void:
	beacon_used = true


func stop_beacon() -> void:
	beacon_used = true


func start_listening() -> void:
	listening = true


func stop_listening() -> void:
	listening = false


func set_games(list: Array) -> void:
	games.assign(list)
	games_changed.emit()
