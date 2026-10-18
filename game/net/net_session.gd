class_name NetSession
extends Node
## The only multiplayer RPC endpoint: peers, lobby and message transport.
## Host-authoritative over ENet; see docs/multiplayer.md. Uses this node's own
## `multiplayer`, so each peer may live on its own SceneMultiplayer branch.

signal lobby_changed
signal match_started(roster: Array, setup: Dictionary)
signal message_received(kind: StringName, payload: Variant, from_peer: int)
signal peer_left(peer_id: int)
signal session_closed(reason: String)

enum State { OFFLINE, HOSTING, CONNECTING, JOINED }

const DEFAULT_PORT := 7777
const PROTOCOL_VERSION := 1
const MAX_PLAYERS := 10
## Seconds a client may take to connect and be welcomed before the join is abandoned
## (client side) or the silent peer is dropped (host side).
const JOIN_TIMEOUT := 5.0
## A refused peer is dropped after this delay, so its reason arrives first.
const REFUSAL_GRACE := 0.5

var lobby: Dictionary = {"players": [], "setup": {}, "in_match": false}
## Optional internal/test name; ordinary games use generic player labels.
var local_name := ""
## Hosts announce the lobby to LAN join lists while it is joinable.
var announce := true

var _state := State.OFFLINE
var _api: MultiplayerAPI
var _peer: ENetMultiplayerPeer
var _session := 0
var _port := 0
var _refusal := ""
var _hat_id := CharacterAppearance.NONE
var _top_id := CharacterAppearance.NONE
var _colour_id := CharacterAppearance.RANDOM
var _protocol := PROTOCOL_VERSION
var _version := str(ProjectSettings.get_setting("application/config/version", ""))
var _discovery: LanDiscovery


func _exit_tree() -> void:
	leave()


func host(port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	# Spare slots let refused peers connect long enough to hear why.
	var error := peer.create_server(port, MAX_PLAYERS + 2)
	if error != OK:
		return error
	_open(peer)
	_state = State.HOSTING
	_port = port
	var players := [_player(1, LobbyRules.unique_name(_name(), []), _hat_id, _top_id, _colour_id)]
	lobby = {
		"players": players,
		"setup":
		LobbyRules.clamp_setup(
			LobbyRules.DEFAULT_PLAYER_COUNT, LobbyRules.DEFAULT_WINS, [], players.size()
		),
		"in_match": false,
	}
	_sync_lobby()
	return OK


## Connects; the session counts as online once the host's first lobby arrives.
func join(address: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		return error
	_open(peer)
	_state = State.CONNECTING
	var session := _session
	get_tree().create_timer(JOIN_TIMEOUT).timeout.connect(
		func() -> void:
			if _session == session and _state == State.CONNECTING:
				_close("Could not connect", true)
	)
	return OK


## Ends the session locally without emitting session_closed.
func leave() -> void:
	_close("", false)


func is_online() -> bool:
	return _state == State.HOSTING or _state == State.JOINED


func is_host() -> bool:
	return _state == State.HOSTING


func local_peer() -> int:
	return _api.get_unique_id() if _state != State.OFFLINE else 1


## Stores the IDs used on the next join and, when online, sends them to the host.
func set_local_appearance(appearance: CharacterAppearance) -> void:
	_hat_id = LobbyRules.valid_hat(appearance.hat_id)
	_top_id = LobbyRules.valid_top(appearance.body_id)
	_colour_id = LobbyRules.valid_colour(appearance.colour_id)
	if _state == State.HOSTING:
		_apply_appearance(1, _hat_id, _top_id, _colour_id)
	elif _state == State.JOINED:
		_appearance.rpc_id(1, _hat_id, _top_id, _colour_id)


## Host only. Values are clamped; extra seats beyond the humans are AI.
func set_setup(player_count: int, wins_needed: int, stages: Array[StringName]) -> void:
	if _state != State.HOSTING:
		return
	var setup := LobbyRules.clamp_setup(player_count, wins_needed, stages, lobby.players.size())
	if setup != lobby.setup:
		lobby.setup = setup
		_sync_lobby()


## Seats in this lobby (its Players setting): people take seats, AI fills the rest.
func lobby_size() -> int:
	return int(lobby.get("setup", {}).get("player_count", MAX_PLAYERS))


## People in the lobby; the remaining seats are AI.
func ai_seats() -> int:
	return maxi(lobby_size() - lobby.get("players", []).size(), 0)


## Host only: locks the lobby and delivers match_started on every peer, host included.
func start_match() -> void:
	if _state != State.HOSTING or lobby.in_match:
		return
	lobby.in_match = true
	_sync_lobby()
	var roster := LobbyRules.build_roster(lobby.players, lobby.setup.player_count)
	var setup := {"wins_needed": lobby.setup.wins_needed, "stages": lobby.setup.stages.duplicate()}
	for peer in _clients():
		_match.rpc_id(peer, roster, setup)
	match_started.emit(roster.duplicate(true), setup.duplicate(true))


## Host only: reopens the lobby for setup changes and joins after a match.
func end_match() -> void:
	if _state == State.HOSTING and lobby.in_match:
		lobby.in_match = false
		_sync_lobby()


## Client → host. On the host itself the message is delivered locally from peer 1.
func send_to_host(kind: StringName, payload: Variant, reliable := true) -> void:
	if _state == State.HOSTING:
		message_received.emit(kind, payload, 1)
	elif _state == State.JOINED:
		if reliable:
			_reliable.rpc_id(1, kind, payload)
		else:
			_unreliable.rpc_id(1, kind, payload)


## Host → every client in the lobby; never echoed to the host.
func broadcast(kind: StringName, payload: Variant, reliable := true) -> void:
	if _state != State.HOSTING:
		return
	for peer in _clients():
		if reliable:
			_reliable.rpc_id(peer, kind, payload)
		else:
			_unreliable.rpc_id(peer, kind, payload)


func _open(peer: ENetMultiplayerPeer) -> void:
	_session += 1
	_refusal = ""
	_peer = peer
	_api = multiplayer
	if _api is SceneMultiplayer:
		# Clients only ever talk to the host.
		(_api as SceneMultiplayer).server_relay = false
	_api.multiplayer_peer = peer
	_api.peer_connected.connect(_on_peer_connected)
	_api.peer_disconnected.connect(_on_peer_disconnected)
	_api.connected_to_server.connect(_on_connected)
	_api.connection_failed.connect(_on_connection_failed)
	_api.server_disconnected.connect(_on_server_disconnected)


func _close(reason: String, notify: bool) -> void:
	if _state == State.OFFLINE:
		return
	_session += 1
	_state = State.OFFLINE
	_api.peer_connected.disconnect(_on_peer_connected)
	_api.peer_disconnected.disconnect(_on_peer_disconnected)
	_api.connected_to_server.disconnect(_on_connected)
	_api.connection_failed.disconnect(_on_connection_failed)
	_api.server_disconnected.disconnect(_on_server_disconnected)
	_peer.close()
	_api.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer = null
	_api = null
	lobby = {"players": [], "setup": {}, "in_match": false}
	if _discovery != null:
		_discovery.stop_beacon()
	if notify:
		session_closed.emit(reason)


## Network callbacks run inside the multiplayer poll, which must not swap peers.
func _close_later(reason: String) -> void:
	_close_session.call_deferred(_session, reason)


func _close_session(session: int, reason: String) -> void:
	if _session == session:
		_close(reason, true)


func _name() -> String:
	return local_name if not MachineName.clean(local_name).is_empty() else "Player"


func _player(
	peer: int, name: String, hat_id: StringName, top_id: StringName, colour_id: StringName
) -> Dictionary:
	return {
		"peer": peer,
		"name": name,
		"hat_id": hat_id,
		"top_id": top_id,
		"colour_id": colour_id,
		"colour": Color.TRANSPARENT,
	}


func _find(peer: int) -> int:
	for index in lobby.players.size():
		if lobby.players[index].peer == peer:
			return index
	return -1


func _clients() -> Array[int]:
	var peers: Array[int] = []
	for player: Dictionary in lobby.players:
		if player.peer != 1:
			peers.append(player.peer)
	return peers


func _sync_lobby() -> void:
	LobbyRules.resolve_colours(lobby.players)
	for peer in _clients():
		_lobby.rpc_id(peer, lobby)
	_update_beacon()
	lobby_changed.emit()


func _update_beacon() -> void:
	if not announce:
		return
	if _discovery == null:
		_discovery = LanDiscovery.new()
		_discovery.name = "Discovery"
		add_child(_discovery)
	if lobby.in_match or lobby.players.is_empty():
		_discovery.stop_beacon()
	else:
		var host_name := "Lobby"
		_discovery.start_beacon(host_name, _port, lobby.players.size(), lobby_size())


func _apply_appearance(peer: int, hat_id: Variant, top_id: Variant, colour_id: Variant) -> void:
	var index := _find(peer)
	if index < 0:
		return
	var player: Dictionary = lobby.players[index]
	var hat := LobbyRules.valid_hat(hat_id)
	var top := LobbyRules.valid_top(top_id)
	var colour := LobbyRules.valid_colour(colour_id)
	if player.hat_id != hat or player.top_id != top or player.colour_id != colour:
		player.hat_id = hat
		player.top_id = top
		player.colour_id = colour
		_sync_lobby()


func _refuse(peer: int, reason: String) -> void:
	_refused.rpc_id(peer, reason)
	var session := _session
	get_tree().create_timer(REFUSAL_GRACE).timeout.connect(
		func() -> void:
			if _session == session and peer in _api.get_peers() and _find(peer) < 0:
				_peer.disconnect_peer(peer)
	)


func _on_peer_connected(peer: int) -> void:
	if _state != State.HOSTING:
		return
	var session := _session
	get_tree().create_timer(JOIN_TIMEOUT).timeout.connect(
		func() -> void:
			if _session == session and peer in _api.get_peers() and _find(peer) < 0:
				_peer.disconnect_peer(peer)
	)


func _on_peer_disconnected(peer: int) -> void:
	if _state != State.HOSTING:
		return
	var index := _find(peer)
	if index < 0:
		return
	# The entry goes even mid-match: the match keeps its own roster and the seat turns AI.
	lobby.players.remove_at(index)
	lobby.setup = LobbyRules.clamp_setup(
		lobby.setup.player_count, lobby.setup.wins_needed, lobby.setup.stages, lobby.players.size()
	)
	_sync_lobby()
	peer_left.emit(peer)


func _on_connected() -> void:
	_hello.rpc_id(1, _protocol, _version, _name(), _hat_id, _top_id, _colour_id)


func _on_connection_failed() -> void:
	_close_later("Could not connect")


func _on_server_disconnected() -> void:
	if not _refusal.is_empty():
		_close_later(_refusal)
	else:
		_close_later("Host left" if _state == State.JOINED else "Could not connect")


@rpc("any_peer", "call_remote", "reliable")
func _hello(
	protocol: Variant,
	version: Variant,
	player_name: Variant,
	hat_id: Variant,
	top_id: Variant,
	colour_id: Variant
) -> void:
	if _state != State.HOSTING:
		return
	var peer := _api.get_remote_sender_id()
	if _find(peer) >= 0:
		return
	var reason := ""
	if not protocol is int or protocol != _protocol or not version is String or version != _version:
		reason = "Different game version"
	elif lobby.in_match:
		reason = "Match in progress"
	elif lobby.players.size() >= lobby_size():
		reason = "Lobby is full"
	if not reason.is_empty():
		_refuse(peer, reason)
		return
	var name := LobbyRules.unique_name(player_name if player_name is String else "", lobby.players)
	lobby.players.append(
		_player(
			peer,
			name,
			LobbyRules.valid_hat(hat_id),
			LobbyRules.valid_top(top_id),
			LobbyRules.valid_colour(colour_id)
		)
	)
	lobby.setup = LobbyRules.clamp_setup(
		lobby.setup.player_count, lobby.setup.wins_needed, lobby.setup.stages, lobby.players.size()
	)
	_sync_lobby()


@rpc("authority", "call_remote", "reliable")
func _refused(reason: String) -> void:
	_refusal = reason
	_close_later(reason)


@rpc("authority", "call_remote", "reliable")
func _lobby(data: Dictionary) -> void:
	if _state != State.CONNECTING and _state != State.JOINED:
		return
	var setup: Dictionary = data.get("setup", {})
	if setup.has("stages"):
		setup.stages = Array(setup.stages, TYPE_STRING_NAME, &"", null)
	lobby = data
	_state = State.JOINED
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _match(roster: Array, setup: Dictionary) -> void:
	if _state != State.JOINED:
		return
	setup.stages = Array(setup.get("stages", []), TYPE_STRING_NAME, &"", null)
	match_started.emit(roster, setup)


@rpc("any_peer", "call_remote", "reliable")
func _appearance(hat_id: Variant, top_id: Variant, colour_id: Variant) -> void:
	if _state == State.HOSTING:
		_apply_appearance(_api.get_remote_sender_id(), hat_id, top_id, colour_id)


@rpc("any_peer", "call_remote", "reliable", 0)
func _reliable(kind: StringName, payload: Variant) -> void:
	_deliver(kind, payload)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _unreliable(kind: StringName, payload: Variant) -> void:
	_deliver(kind, payload)


func _deliver(kind: StringName, payload: Variant) -> void:
	var sender := _api.get_remote_sender_id()
	if _state == State.HOSTING:
		if _find(sender) < 0:
			return
	elif _state != State.JOINED or sender != 1:
		return
	message_received.emit(kind, payload, sender)
