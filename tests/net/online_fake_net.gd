extends NetSession
## In-memory NetSession for match tests. Linked fakes deliver on a later physics frame,
## through a real Variant encode/decode, with optional latency and loss for unreliable
## messages. Delivery stays ordered, like `unreliable_ordered` and reliable channels.

var fake_peer: int = 1
var fake_online: bool = true
var fake_host: Node
var fake_clients: Array = []
## Extra physics frames before an unreliable message arrives.
var fake_latency: int = 0
## Fraction of unreliable messages lost.
var fake_drop_rate: float = 0.0
## Largest encoded payload received per message kind.
var fake_largest: Dictionary = {}
## Messages received per kind.
var fake_received: Dictionary = {}
var fake_ended_matches: int = 0
var _fake_random := RandomNumberGenerator.new()
var _fake_queue: Array = []
var _fake_frame: int = 0


func _init() -> void:
	_fake_random.seed = 7
	# Deliver before match controllers run, so each frame sees the previous frame's sends.
	process_physics_priority = -100


static func fake_link(host_net: Node, client_nets: Array) -> void:
	host_net.fake_peer = 1
	host_net.fake_clients = client_nets.duplicate()
	for client in client_nets:
		client.fake_host = host_net


## Host: forget a client (it disconnected); the host hears peer_left.
func fake_drop_client(client: Node) -> void:
	fake_clients.erase(client)
	client.fake_host = null
	peer_left.emit(client.fake_peer)


## Host: the session returns to its lobby (a no-op here beyond counting).
func end_match() -> void:
	fake_ended_matches += 1


func is_online() -> bool:
	return fake_online


func is_host() -> bool:
	return fake_peer == 1


func local_peer() -> int:
	return fake_peer


func send_to_host(kind: StringName, payload: Variant, reliable := true) -> void:
	if not is_host() and is_instance_valid(fake_host):
		fake_host.fake_enqueue(kind, payload, fake_peer, reliable)


func broadcast(kind: StringName, payload: Variant, reliable := true) -> void:
	if not is_host():
		return
	for client in fake_clients:
		if is_instance_valid(client):
			client.fake_enqueue(kind, payload, fake_peer, reliable)


func fake_enqueue(kind: StringName, payload: Variant, from_peer: int, reliable: bool) -> void:
	var bytes := var_to_bytes(payload)
	fake_largest[kind] = maxi(fake_largest.get(kind, 0), bytes.size())
	if not reliable and _fake_random.randf() < fake_drop_rate:
		return
	var due := _fake_frame + (0 if reliable else fake_latency)
	_fake_queue.append([due, kind, bytes, from_peer])


func _physics_process(_delta: float) -> void:
	_fake_frame += 1
	while not _fake_queue.is_empty() and _fake_queue[0][0] < _fake_frame:
		var message: Array = _fake_queue.pop_front()
		fake_received[message[1]] = fake_received.get(message[1], 0) + 1
		message_received.emit(message[1], bytes_to_var(message[2]), message[3])
