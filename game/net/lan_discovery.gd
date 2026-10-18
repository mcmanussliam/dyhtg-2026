class_name LanDiscovery
extends Node
## LAN discovery: guests broadcast queries, hosts reply directly to each guest.
## Beacons also go to 127.0.0.1 so two instances on one machine find each other.

signal games_changed

const QUERY := "dilly_dallying:discover:1"
const PORT := 7778
const GAME_ID := "dilly_dallying"
const INTERVAL_MSEC := 1000
const EXPIRY_MSEC := 3000
const MAX_PACKET := 1024
const TARGET_REFRESH_MSEC := 10000

## Hosts heard recently: { "address": String, "port": int, "name": String,
## "players": int, "max": int }. Entries expire after a few silent seconds.
var games: Array[Dictionary] = []
## Override for isolated discovery tests; production always uses PORT.
var discovery_port := PORT

var _targets := PackedStringArray(["255.255.255.255", "127.0.0.1"])
var _target_thread: Thread
var _next_query := 0
var _query_logged := false
var _rejected := {}
var _next_target_refresh := 0
var _send_warned := false
var _beacon: PacketPeerUDP
var _announcement := {}
var _next_beacon := 0
var _listening := false
var _listener: PacketPeerUDP
var _next_bind := 0
var _bind_warned := false
## Beacon ID -> { "game": Dictionary in `games`, "heard": msec }.
var _heard := {}
var _json := JSON.new()


func _ready() -> void:
	_update_processing()


func _exit_tree() -> void:
	stop_beacon()
	stop_listening()
	if _target_thread != null:
		_target_thread.wait_to_finish()


## Host: announce this game about once a second until stopped.
func start_beacon(name: String, port: int, players: int, max_players: int) -> void:
	if _beacon == null:
		_next_target_refresh = 0
		_send_warned = false
		_beacon = PacketPeerUDP.new()
		_beacon.set_broadcast_enabled(true)
		# Explicit IPv4 sockets avoid platform differences with dual-stack binds.
		var error := _beacon.bind(discovery_port, "0.0.0.0")
		if error != OK:
			push_warning(
				(
					"[LAN] Cannot open host discovery port %d: %s"
					% [discovery_port, error_string(error)]
				)
			)
			_beacon.close()
			_beacon = null
			return
		_query_logged = false
		print(
			(
				"[LAN] Host listening on UDP %d; local IPv4: %s; version %s"
				% [discovery_port, _local_ipv4(), _game_version()]
			)
		)
		_announcement = {
			"game": GAME_ID,
			"id": "%d-%d" % [Time.get_ticks_usec(), randi()],
			"protocol": NetSession.PROTOCOL_VERSION,
			"version": _game_version(),
		}
	_announcement.name = MachineName.clean(name)
	_announcement.port = port
	_announcement.players = players
	_announcement.max = max_players
	_next_beacon = 0
	_update_processing()


func update_beacon(players: int) -> void:
	if _beacon != null and _announcement.players != players:
		_announcement.players = players
		_next_beacon = 0


func stop_beacon() -> void:
	if _beacon != null:
		_beacon.close()
	_beacon = null
	_update_processing()


## Client: listen for announcements and keep `games` current.
func start_listening() -> void:
	_listening = true
	_next_bind = 0
	_next_query = 0
	_next_target_refresh = 0
	_send_warned = false
	_rejected.clear()
	_update_processing()


func stop_listening() -> void:
	_listening = false
	if _listener != null:
		_listener.close()
	_listener = null
	_bind_warned = false
	_heard.clear()
	if not games.is_empty():
		games.clear()
		games_changed.emit()
	_update_processing()


func is_listening() -> bool:
	return _listener != null


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	_refresh_targets(now)
	if _beacon != null:
		_reply_to_queries()
	if _beacon != null and now >= _next_beacon:
		_next_beacon = now + INTERVAL_MSEC
		var packet := JSON.stringify(_announcement).to_utf8_buffer()
		_send_broadcast(_beacon, packet)
	if not _listening:
		return
	if _listener == null and now >= _next_bind:
		_bind(now)
	var changed := false
	if _listener != null:
		if now >= _next_query:
			_next_query = now + INTERVAL_MSEC
			_send_broadcast(_listener, QUERY.to_utf8_buffer())
		changed = _receive(now)
	for id in _heard.keys():
		if now - int(_heard[id].heard) > EXPIRY_MSEC:
			games.erase(_heard[id].game)
			_heard.erase(id)
			changed = true
	if changed:
		games_changed.emit()


func _bind(now: int) -> void:
	var socket := PacketPeerUDP.new()
	socket.set_broadcast_enabled(true)
	var error := socket.bind(0, "0.0.0.0")
	if error == OK:
		_listener = socket
		print(
			(
				"[LAN] Searching from UDP %d; local IPv4: %s; version %s"
				% [socket.get_local_port(), _local_ipv4(), _game_version()]
			)
		)
		return
	# Retry if the OS temporarily cannot create a socket.
	_next_bind = now + INTERVAL_MSEC
	if not _bind_warned:
		_bind_warned = true
		push_warning("[LAN] Cannot open discovery socket: %s; retrying." % error_string(error))


func _receive(now: int) -> bool:
	var changed := false
	while _listener.get_available_packet_count() > 0:
		var packet := _listener.get_packet()
		var address := _listener.get_packet_ip()
		var data := _parse(packet)
		if data.is_empty():
			if not _rejected.has(address):
				_rejected[address] = true
				push_warning(
					(
						"[LAN] Rejected announcement from %s; check both game versions match (%s)."
						% [address, _game_version()]
					)
				)
			continue
		var game := {
			"address": address,
			"port": int(data.port),
			"name": MachineName.clean(str(data.name)),
			"players": int(data.players),
			"max": int(data.max),
		}
		var id := str(data.id)
		if id in _heard:
			# Keep the first source address so a beacon heard twice never flickers.
			var known: Dictionary = _heard[id].game
			game.address = known.address
			if known != game:
				known.merge(game, true)
				changed = true
			_heard[id].heard = now
		else:
			print("[LAN] Found %s at %s:%d" % [game.name, address, game.port])
			games.append(game)
			_heard[id] = {"game": game, "heard": now}
			changed = true
	return changed


## A well-formed announcement from this game and version, or {}.
func _parse(packet: PackedByteArray) -> Dictionary:
	if packet.size() > MAX_PACKET or _json.parse(packet.get_string_from_utf8()) != OK:
		return {}
	var data: Variant = _json.data
	if not data is Dictionary:
		return {}
	for key in ["game", "id", "protocol", "version", "name", "port", "players", "max"]:
		if not data.has(key):
			return {}
	for key in ["protocol", "port", "players", "max"]:
		if not (data[key] is float or data[key] is int):
			return {}
	if (
		str(data.game) != GAME_ID
		or int(data.protocol) != NetSession.PROTOCOL_VERSION
		or str(data.version) != _game_version()
		or int(data.port) < 1
		or int(data.port) > 65535
	):
		return {}
	return data


func _update_processing() -> void:
	set_process(_beacon != null or _listening)


static func _game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## Godot exposes interface addresses but not subnet masks. Ask the OS for its
## actual broadcasts: replacing the last octet with 255 breaks non-/24 networks.
## Refresh while hosting so switching Wi-Fi does not require reopening the lobby.
static func _broadcast_targets() -> PackedStringArray:
	var output: Array = []
	var result := -1
	if OS.get_name() == "macOS":
		result = OS.execute("/sbin/ifconfig", PackedStringArray(), output)
	elif OS.get_name() == "Linux":
		result = OS.execute("ip", PackedStringArray(["-4", "-o", "addr", "show", "up"]), output)
	elif OS.get_name() == "Windows":
		result = OS.execute(
			"powershell.exe",
			PackedStringArray(
				[
					"-NoProfile",
					"-NonInteractive",
					"-Command",
					(
						"Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred | "
						+ "ForEach-Object { '{0}/{1}' -f $_.IPAddress,$_.PrefixLength }"
					)
				]
			),
			output
		)
	var targets := PackedStringArray()
	if result == 0 and not output.is_empty():
		if OS.get_name() == "Windows":
			targets = _parse_windows_broadcasts(str(output[0]))
		else:
			targets = _parse_broadcasts(str(output[0]))
	# Preserve discovery on platforms where interface broadcasts are unavailable.
	if targets.is_empty():
		targets.append("255.255.255.255")
	targets.append("127.0.0.1")
	return targets


static func _parse_broadcasts(text: String) -> PackedStringArray:
	var targets := PackedStringArray()
	var pattern := RegEx.new()
	pattern.compile("(?:broadcast|brd) +([0-9]+[.][0-9]+[.][0-9]+[.][0-9]+)")
	for found in pattern.search_all(text):
		var address := found.get_string(1)
		if (
			address.is_valid_ip_address()
			and not address.begins_with("127.")
			and address != "0.0.0.0"
			and not targets.has(address)
		):
			targets.append(address)
	return targets


## Queries and replies use the same socket; replies return to the requesting port.
## Multiple Join pages can coexist, and guests do not need to own fixed port 7778.
func _reply_to_queries() -> void:
	for _packet_index in 64:
		if _beacon.get_available_packet_count() <= 0:
			break
		var packet := _beacon.get_packet()
		if packet != QUERY.to_utf8_buffer():
			continue
		var address := _beacon.get_packet_ip()
		var port := _beacon.get_packet_port()
		if not _query_logged:
			_query_logged = true
			print("[LAN] Received discovery query from %s:%d" % [address, port])
		if _beacon.set_dest_address(address, port) == OK:
			_beacon.put_packet(JSON.stringify(_announcement).to_utf8_buffer())


func _send_broadcast(socket: PacketPeerUDP, packet: PackedByteArray) -> void:
	var lan_sent := false
	var lan_attempted := false
	for target in _targets:
		if target != "127.0.0.1":
			lan_attempted = true
		if socket.set_dest_address(target, discovery_port) == OK:
			var sent := socket.put_packet(packet)
			if target != "127.0.0.1" and sent == OK:
				lan_sent = true
	if lan_attempted and not lan_sent and not _send_warned and _target_thread == null:
		_send_warned = true
		push_warning("[LAN] Broadcast sends failed; guests can use --join=<host IP>.")


## PowerShell can take seconds to start; never block the game while finding routes.
func _refresh_targets(now: int) -> void:
	if _target_thread != null and not _target_thread.is_alive():
		var targets: PackedStringArray = _target_thread.wait_to_finish()
		_target_thread = null
		if targets != _targets:
			_targets = targets
			_next_query = 0
			_next_beacon = 0
			print("[LAN] Broadcast targets: %s" % _targets)
	if _target_thread == null and now >= _next_target_refresh:
		_next_target_refresh = now + TARGET_REFRESH_MSEC
		_target_thread = Thread.new()
		if _target_thread.start(_broadcast_targets) != OK:
			_target_thread = null


static func _local_ipv4() -> PackedStringArray:
	var addresses := PackedStringArray()
	for address in IP.get_local_addresses():
		if not address.contains(":") and not address.begins_with("127."):
			addresses.append(address)
	return addresses


static func _parse_windows_broadcasts(text: String) -> PackedStringArray:
	var targets := PackedStringArray()
	for line in text.split("\n"):
		var fields := line.strip_edges().split("/")
		if fields.size() != 2 or not fields[0].is_valid_ip_address():
			continue
		if fields[0].contains(":") or fields[0].begins_with("127."):
			continue
		if not fields[1].is_valid_int():
			continue
		var prefix := int(fields[1])
		if prefix < 1 or prefix > 30:
			continue
		var address := 0
		for octet in fields[0].split("."):
			address = (address << 8) | int(octet)
		var broadcast := address | ((1 << (32 - prefix)) - 1)
		var target := (
			"%d.%d.%d.%d"
			% [
				(broadcast >> 24) & 255,
				(broadcast >> 16) & 255,
				(broadcast >> 8) & 255,
				broadcast & 255
			]
		)
		if not targets.has(target):
			targets.append(target)
	return targets
