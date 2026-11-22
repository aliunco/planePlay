extends Node
## LAN transport: two devices on the same network play a match over UDP (ENet).
##
## Registered as the `Lan` autoload, so the node path is identical on both
## devices and RPCs can address it directly.
##
## WHAT TRAVELS
## Only one player's *input* per tick, never positions: both devices run the
## exact same simulation (same planes, same seed-free logic), so sending the
## intent keeps the two worlds in lockstep. Input packets are small and
## reliable, which matters because a dropped launch/turn packet would leave the
## two simulations disagreeing forever. A health/state heartbeat also travels
## a few times per second so a desync can be detected and reported.
##
## Roles: the host is player 1 (the left airplane), the client is player 2.
## Each device's camera follows its own airplane.

signal peer_joined()
signal peer_left()
signal failed(reason: String)
signal rematch_requested()
## A host answered a LAN discovery probe: this is its address.
signal host_found(address: String)
signal remote_input(input: PlaneInput)
signal remote_state(state: Dictionary)
## A bomb the other pilot dropped. Both devices then watch the same thing fall;
## only the device that dropped it decides who the blast hurts.
signal bomb_dropped(at: Vector2, velocity: Vector2, owner_id: int)
## A flare burst the other pilot burned. It deals no damage, but the homing rounds
## on this device chase it instead of the aircraft, so it has to be mirrored.
signal flares_launched(at: Vector2, direction: Vector2, owner_id: int)
## The other pilot lit a shield bubble. It is drawn here too, so both screens
## agree on why a round did nothing.
signal shield_used(owner_id: int, seconds: float)
## The host's key for this session: drop routes, the opening sky and the time of
## day all come from it, so both screens play the same match. The host's fighter
## rides along with it, because both ends have to simulate the same airframes.
signal session_seeded(seed_value: int, plane_index: int)
## A hit the other pilot's device decided landed on one of the airplanes.
## `victim_id` names the airplane that has to take the damage.
signal damage_received(victim_id: int, amount: int, hit_id: int)
## The owner of a damaged airplane confirming it applied the hit.
signal hit_acknowledged(victim_id: int, hit_id: int)

enum Role { NONE, HOST, CLIENT }

const DEFAULT_PORT: int = 27777
const MAX_CLIENTS: int = 1

## LAN discovery: the host answers a broadcast probe on its own port, so the
## other pilot's menu can fill in the address instead of typing it.
const DISCOVERY_PORT: int = DEFAULT_PORT + 1
const DISCOVERY_PROBE: String = "SKYDUEL_WHO"
const DISCOVERY_REPLY: String = "SKYDUEL_HOST"
const DISCOVERY_INTERVAL: float = 0.5

const PING_INTERVAL: float = 0.5

var role: Role = Role.NONE

## Connection quality, sampled by the ping/pong pair below.
var rtt_ms: int = 0
var jitter_ms: int = 0
var loss_percent: int = 0

var _peer: ENetMultiplayerPeer
var _status: String = "Not connected"
var _wired: bool = false
var _discovery_host: PacketPeerUDP
var _discovery_client: PacketPeerUDP
var _search_remaining: float = 0.0
var _search_timer: float = 0.0

var _ping_timer: float = 0.0
var _window_timer: float = 0.0
var _pings_sent: int = 0
var _pongs_received: int = 0


func _ready() -> void:
	# Keep measuring while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Autoloads live for the whole session; wire the MultiplayerAPI once.
	if not _wired:
		_wired = true
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.connected_to_server.connect(_on_connected_to_server)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- Session -----------------------------------------------------------------

func host(port: int = DEFAULT_PORT) -> bool:
	close()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_CLIENTS)
	if error != OK:
		_status = "Could not host on port %d (error %d)" % [port, error]
		if error == ERR_CANT_CREATE:
			# ENet cannot open its socket: the port is taken, or the app was built
			# without the INTERNET permission (permissions/internet in the export
			# preset), which is the usual cause on Android.
			_status += " - port busy, or this build has no INTERNET permission"
		print("LAN host failed: ", _status)
		failed.emit(_status)
		return false
	print("LAN hosting on port %d" % port)

	_peer = peer
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	_status = "Hosting on port %d" % port
	_stop_search()
	_start_discovery_listener()
	return true


func join(address: String, port: int = DEFAULT_PORT) -> bool:
	close()
	var clean := address.strip_edges()
	if clean.is_empty():
		clean = "127.0.0.1"
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(clean, port)
	if error != OK:
		_status = "Could not reach %s:%d (error %d)" % [clean, port, error]
		if error == ERR_CANT_CREATE:
			_status += " - this build may have no INTERNET permission"
		print("LAN join failed: ", _status)
		failed.emit(_status)
		return false
	print("LAN joining %s:%d" % [clean, port])

	_peer = peer
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	_status = "Connecting to %s:%d..." % [clean, port]
	_stop_search()
	return true


func close() -> void:
	if _peer != null:
		multiplayer.multiplayer_peer = null
		_peer.close()
		_peer = null
	_stop_discovery_listener()
	_stop_search()
	role = Role.NONE
	_status = "Not connected"
	rtt_ms = 0
	jitter_ms = 0
	loss_percent = 0
	_ping_timer = 0.0
	_window_timer = 0.0
	_pings_sent = 0
	_pongs_received = 0


func is_connected_to_peer() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## True only once the other device is really there: a freshly created server is
## already "connected", but with nobody on the other end yet.
func has_peer() -> bool:
	if not is_connected_to_peer():
		return false
	return not multiplayer.get_peers().is_empty()


func is_host() -> bool:
	return role == Role.HOST


func status_text() -> String:
	return _status


## Short readout for the HUD, e.g. "18 ms" or "18 ms  ·  2% loss".
func connection_quality_text() -> String:
	if not is_connected_to_peer():
		return ""
	var text := "%d ms" % rtt_ms
	if loss_percent >= 2:
		text += "  ·  %d%% loss" % loss_percent
	return text


# --- Connection quality -------------------------------------------------------

func _process(delta: float) -> void:
	_poll_discovery_host()
	_poll_host_search(delta)
	if not has_peer():
		return
	_ping_timer += delta
	if _ping_timer >= PING_INTERVAL:
		_ping_timer = 0.0
		_pings_sent += 1
		_net_ping.rpc(Time.get_ticks_msec())

	_window_timer += delta
	if _window_timer >= 2.0:
		_window_timer = 0.0
		if _pings_sent > 0:
			var lost := 1.0 - float(_pongs_received) / float(_pings_sent)
			# Smooth so the reading does not flicker on a single stray packet.
			loss_percent = int(round(lerpf(float(loss_percent), clampf(lost, 0.0, 1.0) * 100.0, 0.5)))
		_pings_sent = 0
		_pongs_received = 0


@rpc("any_peer", "call_remote", "unreliable")
func _net_ping(stamp: int) -> void:
	if multiplayer.get_remote_sender_id() == 0:
		return
	_net_pong.rpc(stamp)


@rpc("any_peer", "call_remote", "unreliable")
func _net_pong(stamp: int) -> void:
	if multiplayer.get_remote_sender_id() == 0:
		return
	_pongs_received += 1
	var sample := maxi(0, Time.get_ticks_msec() - stamp)
	if rtt_ms == 0:
		rtt_ms = sample
		jitter_ms = 0
		return
	jitter_ms = int(round(lerpf(float(jitter_ms), absf(float(sample - rtt_ms)), 0.3)))
	rtt_ms = int(round(lerpf(float(rtt_ms), float(sample), 0.4)))


## Best-guess address to type on the other device.
func local_address_hint() -> String:
	for address in IP.get_local_addresses():
		if address.begins_with("10.") or address.begins_with("192.168.") or address.begins_with("172."):
			return address
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127."):
			return address
	return "127.0.0.1"


# --- LAN discovery -----------------------------------------------------------
##
## A broadcast probe keeps the other pilot from having to type an address: the
## host answers on DISCOVERY_PORT, the searcher reads the reply's IP and fills it
## into the join field. Plain UDP on the local network, so it needs no service
## discovery daemon and no permissions beyond INTERNET. It is best effort: on
## networks that block broadcast the field still takes a typed address.

## Answers probes while hosting, straight back to whoever asked.
func _start_discovery_listener() -> void:
	_stop_discovery_listener()
	var socket := PacketPeerUDP.new()
	socket.set_broadcast_enabled(true)
	if socket.bind(DISCOVERY_PORT) != OK:
		print("LAN discovery unavailable: could not listen on port %d" % DISCOVERY_PORT)
		return
	_discovery_host = socket


func _stop_discovery_listener() -> void:
	if _discovery_host != null:
		_discovery_host.close()
		_discovery_host = null


func _poll_discovery_host() -> void:
	if _discovery_host == null:
		return
	while _discovery_host.get_available_packet_count() > 0:
		var packet := _discovery_host.get_packet()
		var sender := _discovery_host.get_packet_ip()
		# The probe comes from the searcher's own socket, not from the discovery
		# port, so the answer has to go back to that source port.
		var sender_port := _discovery_host.get_packet_port()
		if packet.get_string_from_utf8() != DISCOVERY_PROBE:
			continue
		if sender.is_empty() or sender == "0.0.0.0" or sender_port <= 0:
			continue
		_discovery_host.set_dest_address(sender, sender_port)
		_discovery_host.put_packet(("%s %d" % [DISCOVERY_REPLY, DEFAULT_PORT]).to_utf8_buffer())


## Broadcasts a probe for a few seconds; a host that answers arrives as
## `host_found`. Safe to call when nothing is listening: it simply expires.
func search_for_host(duration: float = 6.0) -> void:
	if is_connected_to_peer() or role != Role.NONE:
		return
	if _discovery_client == null:
		var socket := PacketPeerUDP.new()
		socket.set_broadcast_enabled(true)
		if socket.bind(DISCOVERY_PORT + 1) != OK and socket.bind(0) != OK:
			print("LAN discovery unavailable: could not open a search socket")
			return
		_discovery_client = socket
	_search_remaining = duration
	_search_timer = 0.0
	_send_probe()


## Stops an in-flight search (and the socket it was using).
func stop_host_search() -> void:
	_stop_search()


func _send_probe() -> void:
	if _discovery_client == null:
		return
	for address in _broadcast_addresses():
		_discovery_client.set_dest_address(address, DISCOVERY_PORT)
		_discovery_client.put_packet(DISCOVERY_PROBE.to_utf8_buffer())


## The subnet broadcast addresses worth trying: routers happily drop
## 255.255.255.255, so each local interface's own broadcast goes out too.
func _broadcast_addresses() -> Array[String]:
	var addresses: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.count(".") != 3 or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue
		var parts := ip.split(".")
		var subnet := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if not addresses.has(subnet):
			addresses.append(subnet)
	if addresses.is_empty():
		addresses.append("255.255.255.255")
	return addresses


func _poll_host_search(delta: float) -> void:
	if _discovery_client == null:
		return
	while _discovery_client.get_available_packet_count() > 0:
		var packet := _discovery_client.get_packet()
		var sender := _discovery_client.get_packet_ip()
		if not packet.get_string_from_utf8().begins_with(DISCOVERY_REPLY):
			continue
		if sender.is_empty() or sender == "0.0.0.0":
			continue
		_stop_search()
		print("LAN discovery found a host at ", sender)
		host_found.emit(sender)
		return
	if _search_remaining <= 0.0:
		return
	_search_remaining -= delta
	_search_timer -= delta
	if _search_timer <= 0.0:
		_search_timer = DISCOVERY_INTERVAL
		_send_probe()
	if _search_remaining <= 0.0:
		_stop_search()


func _stop_search() -> void:
	_search_remaining = 0.0
	if _discovery_client != null:
		_discovery_client.close()
		_discovery_client = null


# --- Sending -----------------------------------------------------------------

## Sends this device's own intent for the current tick.
func send_input(input: PlaneInput) -> void:
	if not is_connected_to_peer() or input == null:
		return
	_net_input.rpc(
		input.turn,
		input.fire,
		input.launch,
		input.throttle,
		input.bomb,
		input.boost,
		input.flare,
		input.shield
	)


## Tells the other device about a bomb leaving a belly, so neither pilot sees a
## bomb appear out of nowhere. Reliable: a bomb that only exists on one screen is
## unfair rather than merely ugly.
func send_bomb(at: Vector2, velocity: Vector2, owner_id: int) -> void:
	if not is_connected_to_peer():
		return
	_net_bomb.rpc(at.x, at.y, velocity.x, velocity.y, owner_id)


## Tells the other device about a burst of flares, so its homing rounds can be
## pulled off the pilot who burned them. Reliable: a countermeasure that only
## exists on one screen would be worse than none at all.
func send_flares(at: Vector2, direction: Vector2, owner_id: int) -> void:
	if not is_connected_to_peer():
		return
	_net_flares.rpc(at.x, at.y, direction.x, direction.y, owner_id)


## Tells the other device that a shield went up, so its copy of the plane wears
## the same bubble.
func send_shield(owner_id: int, seconds: float) -> void:
	if not is_connected_to_peer():
		return
	_net_shield.rpc(owner_id, seconds)


## Hands the guest the session key and the host's fighter, so both devices roll
## the same drops, the same day and the same airframes. Sent once at the start of
## a match.
func send_session_seed(seed_value: int, plane_index: int) -> void:
	if not is_connected_to_peer():
		return
	_net_session_seed.rpc(seed_value, plane_index)


## Asks the other device for a rematch; the peer answers with the same call.
func request_rematch() -> void:
	if is_connected_to_peer():
		_net_rematch.rpc()


@rpc("any_peer", "call_remote", "reliable")
func _net_rematch() -> void:
	if multiplayer.get_remote_sender_id() == 0:
		return
	rematch_requested.emit()


## Tells the other device that one of its airplanes was hit. Only the device that
## fired the shot calls this, so a hit is decided exactly once; reliable, because a
## lost hit would leave the two copies of a pilot with different health for good.
func send_damage(victim_id: int, amount: int, hit_id: int) -> void:
	if is_connected_to_peer():
		_net_damage.rpc(victim_id, amount, hit_id)


## Confirms a hit was applied, so the shooter can trust heartbeats again.
func send_hit_ack(victim_id: int, hit_id: int) -> void:
	if is_connected_to_peer():
		_net_hit_ack.rpc(victim_id, hit_id)


## Heartbeat describing the sending device's own airplane.
func send_state(
	position: Vector2, rotation: float, flight_state: int, health: int, alive: bool
) -> void:
	if not is_connected_to_peer():
		return
	_net_state.rpc(position.x, position.y, rotation, flight_state, health, alive)


# --- Receiving ---------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _net_input(
	turn: float,
	fire: bool,
	launch: bool,
	throttle: int,
	bomb: bool = false,
	boost: bool = false,
	flare: bool = false,
	shield: bool = false
) -> void:
	if multiplayer.get_remote_sender_id() == 0:
		return
	var input := PlaneInput.new()
	input.turn = clampf(turn, -1.0, 1.0)
	input.fire = fire
	input.launch = launch
	input.throttle = clampi(throttle, -1, 1)
	input.bomb = bomb
	input.boost = boost
	input.flare = flare
	input.shield = shield
	remote_input.emit(input)


@rpc("any_peer", "call_remote", "reliable")
func _net_bomb(x: float, y: float, vx: float, vy: float, owner_id: int) -> void:
	if multiplayer.get_remote_sender_id() == 0:
		return
	bomb_dropped.emit(Vector2(x, y), Vector2(vx, vy), clampi(owner_id, 1, 2))


@rpc("any_peer", "call_remote", "reliable")
func _net_session_seed(seed_value: int, plane_index: int) -> void:
	if multiplayer.get_remote_sender_id() == 0:
		return
	session_seeded.emit(seed_value, plane_index)


@rpc("any_peer", "call_remote", "reliable")
func _net_shield(owner_id: int, seconds: float) -> void:
	if multiplayer.get_remote_sender_id() == 0:
		return
	shield_used.emit(clampi(owner_id, 1, 2), maxf(0.0, seconds))


@rpc("any_peer", "call_remote", "reliable")
func _net_flares(x: float, y: float, dx: float, dy: float, owner_id: int) -> void:
	if multiplayer.get_remote_sender_id() == 0:
		return
	flares_launched.emit(Vector2(x, y), Vector2(dx, dy), clampi(owner_id, 1, 2))


@rpc("any_peer", "call_remote", "reliable")
func _net_damage(victim_id: int, amount: int, hit_id: int) -> void:
	if multiplayer.get_remote_sender_id() == 0:
		return
	damage_received.emit(victim_id, clampi(amount, 0, 9999), hit_id)


@rpc("any_peer", "call_remote", "reliable")
func _net_hit_ack(victim_id: int, hit_id: int) -> void:
	if multiplayer.get_remote_sender_id() == 0:
		return
	hit_acknowledged.emit(victim_id, hit_id)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _net_state(
	x: float, y: float, rotation: float, flight_state: int, health: int, alive: bool
) -> void:
	if multiplayer.get_remote_sender_id() == 0:
		return
	remote_state.emit(
		{
			"position": Vector2(x, y),
			"rotation": rotation,
			"flight_state": flight_state,
			"health": health,
			"alive": alive,
		}
	)


# --- MultiplayerAPI callbacks ------------------------------------------------

func _on_peer_connected(peer_id: int) -> void:
	if role != Role.HOST:
		return
	_status = "Pilot %d joined" % peer_id
	_start_quality_window()
	peer_joined.emit()


func _on_peer_disconnected(_peer_id: int) -> void:
	if role != Role.HOST:
		return
	_status = "The other pilot disconnected"
	peer_left.emit()


func _on_connected_to_server() -> void:
	if role != Role.CLIENT:
		return
	_status = "Connected"
	_start_quality_window()
	peer_joined.emit()


## Ignores everything before the link existed, so the first loss reading is honest.
func _start_quality_window() -> void:
	rtt_ms = 0
	jitter_ms = 0
	loss_percent = 0
	_ping_timer = 0.0
	_window_timer = 0.0
	_pings_sent = 0
	_pongs_received = 0


func _on_connection_failed() -> void:
	_status = "Could not connect - check the address and that the host is waiting"
	failed.emit(_status)
	close()


func _on_server_disconnected() -> void:
	if role != Role.CLIENT:
		return
	_status = "The host disconnected"
	peer_left.emit()
