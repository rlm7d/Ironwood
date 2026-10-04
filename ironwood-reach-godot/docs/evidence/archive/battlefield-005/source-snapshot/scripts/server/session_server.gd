extends Node

## Native authority for one bounded, in-memory battlefield approval room.
const Battle = preload("res://scripts/simulation/battle.gd")
const Rules = preload("res://scripts/shared/rules.gd")
const ROOM: String = "REACH-01"
const PORT: int = 8775
const MAX_PACKET_BYTES: int = 8192
const MAX_CONNECTIONS: int = 16
const MAX_MESSAGES_PER_POLL: int = 64
const MAX_MESSAGES_PER_CLIENT_POLL: int = 8
const MAX_MESSAGES_PER_SECOND: int = 60
const MAX_COMMANDS_PER_ROLE: int = 4096
const MAX_STALE_REVISIONS: int = 400
const JOIN_TIMEOUT_MS: int = 10000
const STEP_SECONDS: float = 1.0 / 20.0
const SNAPSHOT_SECONDS: float = 1.0 / 10.0

var _listener: TCPServer = TCPServer.new()
var _battle: Object
var _clients: Dictionary = {}
var _seats: Dictionary = {}
var _next_connection: int = 1
var _step_time: float = 0.0
var _snapshot_time: float = 0.0

func _ready() -> void:
	_battle = Battle.new()
	_battle.call("initialize", 7)
	for role: String in Rules.ROLES:
		_seats[role] = {"token": "", "connection_id": "", "sequence": 0, "ledger": {}}
	var error: Error = _listener.listen(PORT, "127.0.0.1")
	if error != OK:
		push_error("Battlefield authority could not bind loopback port %d: %s" % [PORT, error_string(error)])
		get_tree().quit(1)
		return
	print(JSON.stringify({"event": "authority_ready", "host": "127.0.0.1", "port": PORT,
		"room": ROOM, "build_id": Rules.BUILD_ID, "protocol": Rules.PROTOCOL}))

func _process(delta: float) -> void:
	_accept_connections()
	_poll_clients()
	_step_time += minf(delta, 0.25)
	var steps: int = 0
	while _step_time >= STEP_SECONDS and steps < 5:
		_battle.call("step")
		_step_time -= STEP_SECONDS
		steps += 1
	_snapshot_time += delta
	if _snapshot_time >= SNAPSHOT_SECONDS:
		_snapshot_time = 0.0
		_broadcast_snapshot()

func _exit_tree() -> void:
	for value: Variant in _clients.values():
		var client: Dictionary = value
		var peer: WebSocketPeer = client.peer
		peer.close(1001, "authority_stopped")
	_listener.stop()

func _accept_connections() -> void:
	var accepted: int = 0
	while _listener.is_connection_available() and accepted < 4:
		accepted += 1
		var stream: StreamPeerTCP = _listener.take_connection()
		if _clients.size() >= MAX_CONNECTIONS:
			stream.disconnect_from_host()
			continue
		var peer: WebSocketPeer = WebSocketPeer.new()
		peer.inbound_buffer_size = 16384
		peer.outbound_buffer_size = 262144
		peer.max_queued_packets = 64
		var error: Error = peer.accept_stream(stream)
		if error != OK:
			stream.disconnect_from_host()
			continue
		var connection_id: String = "connection-%06d" % _next_connection
		_next_connection += 1
		var at: int = Time.get_ticks_msec()
		_clients[connection_id] = {"peer": peer, "stream": stream, "role": "",
			"started_ms": at, "rate_started_ms": at, "rate_count": 0}

func _poll_clients() -> void:
	var handled: int = 0
	var ids: Array = _clients.keys()
	for value: Variant in ids:
		var connection_id: String = str(value)
		var client: Dictionary = _clients[connection_id]
		var peer: WebSocketPeer = client.peer
		peer.poll()
		var state: WebSocketPeer.State = peer.get_ready_state()
		if state == WebSocketPeer.STATE_CLOSED:
			_remove_client(connection_id)
			continue
		if str(client.role).is_empty() and Time.get_ticks_msec() - int(client.started_ms) >= JOIN_TIMEOUT_MS:
			_reject(connection_id, "join_timeout", true)
			var stream: StreamPeerTCP = client.stream
			stream.disconnect_from_host()
			_remove_client(connection_id)
			continue
		if state != WebSocketPeer.STATE_OPEN:
			continue
		var client_handled: int = 0
		while peer.get_available_packet_count() > 0 and handled < MAX_MESSAGES_PER_POLL and client_handled < MAX_MESSAGES_PER_CLIENT_POLL:
			var packet: PackedByteArray = peer.get_packet()
			handled += 1
			client_handled += 1
			if not _within_rate_limit(client):
				_reject(connection_id, "rate_limited", true)
				break
			if packet.size() > MAX_PACKET_BYTES:
				_reject(connection_id, "packet_too_large", true)
				break
			if not peer.was_string_packet():
				_reject(connection_id, "text_json_required", true)
				break
			var text: String = packet.get_string_from_utf8()
			if not _json_nesting_safe(text):
				_reject(connection_id, "invalid_message", true)
				break
			var parser: JSON = JSON.new()
			if parser.parse(text) != OK:
				_reject(connection_id, "malformed_json", true)
				break
			var message: Variant = parser.data
			if not message is Dictionary or not _bounded_json(message):
				_reject(connection_id, "invalid_message", true)
				break
			_handle_message(connection_id, message)
			if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
				break

func _within_rate_limit(client: Dictionary) -> bool:
	var at: int = Time.get_ticks_msec()
	if at - int(client.rate_started_ms) >= 1000:
		client.rate_started_ms = at
		client.rate_count = 0
	client.rate_count = int(client.rate_count) + 1
	return int(client.rate_count) <= MAX_MESSAGES_PER_SECOND

func _handle_message(connection_id: String, message: Dictionary) -> void:
	var type_value: Variant = message.get("type")
	if not type_value is String:
		_reject(connection_id, "message_type_required")
		return
	var message_type: String = type_value
	if message_type == "join":
		_join(connection_id, message)
		return
	var role: String = str(_clients[connection_id].role)
	if role.is_empty():
		_reject(connection_id, "join_required")
		return
	match message_type:
		"command":
			_command(connection_id, role, message)
		"command_status":
			_command_status(connection_id, role, message)
		"ping":
			if not _fields_allowed(message, ["type", "id"]):
				_reject(connection_id, "invalid_ping")
				return
			var id: Variant = message.get("id", 0)
			if not (id is String and str(id).length() <= 64) and not _integer(id, 0, 2147483647):
				_reject(connection_id, "invalid_ping")
				return
			_send(connection_id, {"type": "pong", "id": id, "revision": _revision()})
		_:
			_reject(connection_id, "unknown_message_type")

func _join(connection_id: String, message: Dictionary) -> void:
	if not str(_clients[connection_id].role).is_empty():
		_reject(connection_id, "already_joined")
		return
	if not _fields_allowed(message, ["type", "protocol", "build_id", "room", "role", "token"]):
		_reject(connection_id, "invalid_join", true)
		return
	if not _integer(message.get("protocol"), 1, 2147483647) or int(message.protocol) != Rules.PROTOCOL:
		_reject(connection_id, "protocol_mismatch", true)
		return
	if message.get("build_id") != Rules.BUILD_ID:
		_reject(connection_id, "build_mismatch", true)
		return
	if message.get("room") != ROOM:
		_reject(connection_id, "unknown_room", true)
		return
	var role_value: Variant = message.get("role")
	if not role_value is String or not Rules.ROLES.has(role_value):
		_reject(connection_id, "unknown_role", true)
		return
	var role: String = role_value
	var token_value: Variant = message.get("token", "")
	if not token_value is String or (str(token_value).length() != 0 and str(token_value).length() != 64):
		_reject(connection_id, "invalid_resume_token", true)
		return
	var token: String = token_value
	var seat: Dictionary = _seats[role]
	if not str(seat.connection_id).is_empty():
		_reject(connection_id, "seat_occupied", true)
		return
	var resumed: bool = not str(seat.token).is_empty()
	if resumed:
		if token.is_empty():
			_reject(connection_id, "seat_reserved", true)
			return
		if not _tokens_equal(token, str(seat.token)):
			_reject(connection_id, "invalid_resume_token", true)
			return
	elif not token.is_empty():
		_reject(connection_id, "invalid_resume_token", true)
		return
	else:
		var crypto: Crypto = Crypto.new()
		var random_bytes: PackedByteArray = crypto.generate_random_bytes(32)
		if random_bytes.size() != 32:
			_reject(connection_id, "entropy_unavailable", true)
			return
		seat.token = random_bytes.hex_encode()
	seat.connection_id = connection_id
	_clients[connection_id].role = role
	_battle.call("set_connected", role, true)
	_send(connection_id, {"type": "welcome", "protocol": Rules.PROTOCOL,
		"build_id": Rules.BUILD_ID, "room": ROOM, "role": role, "token": seat.token,
		"connection_id": connection_id, "sequence": seat.sequence, "resumed": resumed})
	print(JSON.stringify({"event": "seat_connected", "connection_id": connection_id, "role": role, "resumed": resumed}))
	_broadcast_snapshot()

func _remove_client(connection_id: String) -> void:
	if not _clients.has(connection_id):
		return
	var role: String = str(_clients[connection_id].role)
	if not role.is_empty() and str(_seats[role].connection_id) == connection_id:
		_seats[role].connection_id = ""
		_battle.call("set_connected", role, false)
		print(JSON.stringify({"event": "seat_disconnected", "connection_id": connection_id, "role": role}))
	_clients.erase(connection_id)
	if not role.is_empty():
		_broadcast_snapshot()

func _command(connection_id: String, role: String, message: Dictionary) -> void:
	if not _fields_allowed(message, ["type", "seq", "expected_revision", "payload"]) or not _integer(message.get("seq"), 1, 2147483647) or not _integer(message.get("expected_revision"), 0, 2147483647) or not message.get("payload") is Dictionary:
		_reject(connection_id, "invalid_command_envelope")
		return
	var sequence: int = int(message.seq)
	var expected_revision: int = int(message.expected_revision)
	var payload: Dictionary = message.payload.duplicate(true)
	# JSON numbers arrive as floats. Normalize only validated integer fields.
	for field: String in ["socket", "slot"]:
		if payload.has(field) and _integer(payload[field], 0, 2147483647):
			payload[field] = int(payload[field])
	var canonical: String = JSON.stringify(payload, "", true, true)
	var seat: Dictionary = _seats[role]
	var ledger: Dictionary = seat.ledger
	if ledger.has(sequence):
		var cached: Dictionary = ledger[sequence]
		if cached.canonical != canonical:
			_reject(connection_id, "command_id_conflict", false, {"seq": sequence, "sequence": seat.sequence})
			return
		var replay: Dictionary = cached.reply.duplicate(true)
		replay.replayed = true
		_send(connection_id, replay)
		return
	if sequence != int(seat.sequence) + 1:
		_reject(connection_id, "sequence_gap", false, {"seq": sequence, "sequence": seat.sequence})
		return
	if ledger.size() >= MAX_COMMANDS_PER_ROLE:
		_reject(connection_id, "ledger_full", false, {"seq": sequence, "sequence": seat.sequence})
		return
	var outcome: Dictionary = {}
	var failure: String = _validate_payload(payload)
	if not failure.is_empty():
		outcome = {"ok": false, "error": failure}
	elif expected_revision > _revision():
		outcome = {"ok": false, "error": "future_revision"}
	elif _revision() - expected_revision > MAX_STALE_REVISIONS:
		outcome = {"ok": false, "error": "stale_revision"}
	else:
		outcome = _battle.call("command", role, payload)
	var reply: Dictionary = {"type": "result", "seq": sequence, "revision": _revision(),
		"ok": bool(outcome.get("ok", false)), "result": outcome.duplicate(true), "replayed": false}
	ledger[sequence] = {"canonical": canonical, "reply": reply.duplicate(true)}
	seat.sequence = sequence
	_send(connection_id, reply)
	_broadcast_snapshot()

func _command_status(connection_id: String, role: String, message: Dictionary) -> void:
	if not _fields_allowed(message, ["type", "seq"]) or not _integer(message.get("seq"), 1, 2147483647):
		_reject(connection_id, "invalid_command_status")
		return
	var sequence: int = int(message.seq)
	var seat: Dictionary = _seats[role]
	var ledger: Dictionary = seat.ledger
	if not ledger.has(sequence):
		_reject(connection_id, "unknown_command", false, {"seq": sequence, "sequence": seat.sequence})
		return
	var replay: Dictionary = ledger[sequence].reply.duplicate(true)
	replay.replayed = true
	_send(connection_id, replay)

func _validate_payload(payload: Dictionary) -> String:
	var action_value: Variant = payload.get("action")
	if not action_value is String:
		return "action_required"
	var action: String = action_value
	match action:
		"ready":
			if not _fields_allowed(payload, ["action", "value"]) or not payload.get("value") is bool:
				return "invalid_readiness"
		"confirm", "cancel":
			if not _fields_allowed(payload, ["action"]):
				return "invalid_payload"
		"reserve":
			if not _fields_allowed(payload, ["action", "kind", "socket", "building"]) or not _id(payload.get("kind")):
				return "invalid_purchase"
			if payload.has("socket") and not _integer(payload.socket, 0, Rules.SOCKETS.size() - 1):
				return "invalid_socket"
			if payload.has("building") and not _id(payload.building):
				return "invalid_building_id"
			if not payload.has("socket") and not payload.has("building"):
				return "purchase_target_required"
		"order":
			if not _fields_allowed(payload, ["action", "units", "mode", "x", "z"]) or not _ids(payload.get("units")):
				return "invalid_units"
			if not ["move", "attack_move", "stop"].has(payload.get("mode")):
				return "invalid_order"
			if payload.mode != "stop" and not _coordinates(payload):
				return "invalid_position"
			if (payload.has("x") or payload.has("z")) and not _coordinates(payload):
				return "invalid_position"
		"ability":
			if not _fields_allowed(payload, ["action", "slot", "units", "building", "x", "z"]) or not _integer(payload.get("slot"), 0, 1):
				return "invalid_ability_slot"
			if payload.has("units") and not _ids(payload.units):
				return "invalid_units"
			if payload.has("building") and not _id(payload.building):
				return "invalid_building_id"
			if (payload.has("x") or payload.has("z")) and not _coordinates(payload):
				return "invalid_position"
		_:
			return "unknown_action"
	return ""

func _coordinates(payload: Dictionary) -> bool:
	if not _number(payload.get("x")) or not _number(payload.get("z")):
		return false
	var x: float = float(payload.x)
	var z: float = float(payload.z)
	return x >= float(Rules.MAP_BOUNDS.min_x) and x <= float(Rules.MAP_BOUNDS.max_x) and z >= float(Rules.MAP_BOUNDS.min_z) and z <= float(Rules.MAP_BOUNDS.max_z)

func _id(value: Variant) -> bool:
	return value is String and not str(value).is_empty() and str(value).length() <= 64

func _ids(value: Variant) -> bool:
	if not value is Array or value.is_empty() or value.size() > 32:
		return false
	var seen: Dictionary = {}
	for item: Variant in value:
		if not _id(item) or seen.has(item):
			return false
		seen[item] = true
	return true

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return _number(value) and float(value) == floorf(float(value)) and float(value) >= minimum and float(value) <= maximum

func _fields_allowed(value: Dictionary, allowed: Array) -> bool:
	for key: Variant in value:
		if not key is String or not allowed.has(key):
			return false
	return true

func _json_nesting_safe(text: String) -> bool:
	# Reject excessive nesting before invoking the engine's JSON parser.
	var depth: int = 0
	var quoted: bool = false
	var escaped: bool = false
	for index: int in range(text.length()):
		var character: int = text.unicode_at(index)
		if quoted:
			if escaped:
				escaped = false
			elif character == 92:
				escaped = true
			elif character == 34:
				quoted = false
		elif character == 34:
			quoted = true
		elif character == 91 or character == 123:
			depth += 1
			if depth > 10:
				return false
		elif character == 93 or character == 125:
			depth -= 1
			if depth < 0:
				return false
	return depth == 0 and not quoted

func _bounded_json(value: Variant, depth: int = 0) -> bool:
	if depth > 10:
		return false
	if value == null or value is bool:
		return true
	if value is int or value is float:
		return _number(value)
	if value is String:
		return str(value).length() <= 2048
	if value is Array:
		if value.size() > 32:
			return false
		for item: Variant in value:
			if not _bounded_json(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		if value.size() > 16:
			return false
		for key: Variant in value:
			if not key is String or str(key).length() > 64 or not _bounded_json(value[key], depth + 1):
				return false
		return true
	return false

func _tokens_equal(left: String, right: String) -> bool:
	var a: PackedByteArray = left.to_utf8_buffer()
	var b: PackedByteArray = right.to_utf8_buffer()
	if a.size() != 64 or b.size() != 64:
		return false
	var difference: int = 0
	for i: int in range(64):
		difference |= a[i] ^ b[i]
	return difference == 0

func _revision() -> int:
	return int(_battle.get("revision"))

func _snapshot() -> Dictionary:
	var packet: Dictionary = _battle.call("snapshot")
	packet.type = "snapshot"
	packet.room = ROOM
	packet.server_build = Rules.BUILD_ID
	packet.protocol = Rules.PROTOCOL
	packet.connections = {}
	for role: String in Rules.ROLES:
		packet.connections[role] = str(_seats[role].connection_id)
	return packet

func _broadcast_snapshot() -> void:
	var packet: Dictionary = _snapshot()
	for value: Variant in _clients.keys():
		var connection_id: String = str(value)
		if not str(_clients[connection_id].role).is_empty():
			_send(connection_id, packet)

func _send(connection_id: String, packet: Dictionary) -> void:
	if not _clients.has(connection_id):
		return
	var peer: WebSocketPeer = _clients[connection_id].peer
	if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		peer.send_text(JSON.stringify(packet, "", true, true))

func _reject(connection_id: String, code: String, close_connection: bool = false, details: Dictionary = {}) -> void:
	var packet: Dictionary = {"type": "error", "code": code, "revision": _revision()}
	packet.merge(details, false)
	_send(connection_id, packet)
	if close_connection and _clients.has(connection_id):
		var peer: WebSocketPeer = _clients[connection_id].peer
		peer.close(1008, code)
