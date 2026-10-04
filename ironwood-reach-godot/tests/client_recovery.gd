extends SceneTree

## Automated native-client integration, supplementary to real browser play.
## Run against a FRESH loopback authority, then restart it before human/browser use:
## godot --headless --path game --script ../tests/client_recovery.gd
## The test does not start a server or exercise browser localStorage.
## Pending-state assignments below are narrowly scoped test fixtures representing
## an unacknowledged saved command; normal UI/network code contains no test hooks.
const Net = preload("res://scripts/client/net_client.gd")
const ENDPOINT: String = "ws://127.0.0.1:8775"
const WAIT_MS: int = 6000

var builder: Node
var general: Node
var builder_results: Array[Dictionary] = []
var general_results: Array[Dictionary] = []
var general_snapshots: int = 0
var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	builder = Net.new()
	general = Net.new()
	builder.endpoint = ENDPOINT
	general.endpoint = ENDPOINT
	builder.result_received.connect(func(reply: Dictionary) -> void: builder_results.append(reply.duplicate(true)))
	general.result_received.connect(func(reply: Dictionary) -> void: general_results.append(reply.duplicate(true)))
	general.snapshot_received.connect(func(_state: Dictionary) -> void: general_snapshots += 1)
	root.add_child(builder)
	root.add_child(general)
	builder.join("Builder")
	general.join("General")
	if not await _until(func() -> bool: return builder.joined and general.joined and not builder.state.is_empty() and not general.state.is_empty(), "production clients join fresh authority"):
		_finish()
		return
	_check(builder.sequence == 0 and general.sequence == 0 and int(general.state.get("spent", -1)) == 0 and general.state.get("reservations", {}).is_empty(), "fresh room has no commands or purchases")
	if not failures.is_empty():
		_finish()
		return
	_check(builder.peer != general.peer and builder.role == "Builder" and general.role == "General", "production clients use independent transports and bound roles")
	var saved_builder_token: String = str(builder.token)
	var saved_general_token: String = str(general.token)
	_check(not saved_builder_token.is_empty() and not saved_general_token.is_empty() and saved_builder_token != saved_general_token, "seats have distinct in-memory reconnect credentials; values are never logged")

	builder.command({"action": "ready", "value": true})
	general.command({"action": "ready", "value": true})
	if not await _until(func() -> bool: return builder.pending.is_empty() and general.pending.is_empty() and general.state.get("status", "") == "playing", "normal production ready commands start authoritative play"):
		_finish()
		return
	_check(_result(builder_results, 1).get("ok", false) and _result(general_results, 1).get("ok", false), "both ready commands receive successful production result signals")
	_check(builder.sequence == 1 and general.sequence == 1, "ready acknowledgments leave independent client sequences at one")

	# FIRST FIXTURE: the application created and persisted N+1, but transport
	# failed before sending it. We first prove the real socket and server seat are
	# disconnected, then restore that precise pending envelope only inside this test.
	if not await _disconnect_builder("disconnect before server accepts the pending purchase"):
		_finish()
		return
	var base_sequence: int = int(builder.sequence)
	var reservation_sequence: int = base_sequence + 1
	var unsent: Dictionary = {"type": "command", "seq": reservation_sequence,
		"expected_revision": int(general.revision),
		"payload": {"action": "reserve", "kind": "tower", "socket": 0}}
	builder.pending = unsent.duplicate(true)
	builder.last_command = unsent.duplicate(true)
	builder.sequence = reservation_sequence
	var reservation_result_start: int = builder_results.size()
	builder.reconnect() # Production welcome handling must resend unchanged N+1.
	if not await _until(func() -> bool: return builder.joined and builder.pending.is_empty() and not _result(builder_results, reservation_sequence, reservation_result_start).is_empty() and general.state.get("reservations", {}).has("Builder"), "welcome resends saved unaccepted command and clears its pending state"):
		_finish()
		return
	var reservation_result: Dictionary = _result(builder_results, reservation_sequence, reservation_result_start)
	_check(reservation_result.get("ok", false) and not reservation_result.get("replayed", true), "resend receives a newly applied purchase reservation")
	_check(builder.sequence == reservation_sequence, "received resend acknowledgment advances local sequence beyond welcome's earlier server sequence")
	_check(general.state.reservations.size() == 1 and int(general.state.reservations.Builder.cost) == 110 and int(general.state.get("spent", -1)) == 0, "resend holds exactly one 110-gold reservation without spending")
	_check(builder.role == "Builder" and general.role == "General" and builder.token == saved_builder_token and general.token == saved_general_token, "reconnection retains roles and original in-memory seat credentials")
	_check(bool(general.state.get("readiness", {}).get("Builder", false)), "Builder readiness survives transport replacement")

	# This distinct next command is the actual regression: before the sequence
	# recovery fix, command() reused N+1 with a new payload and the server rejected it.
	var confirmation_sequence: int = reservation_sequence + 1
	builder.command({"action": "confirm"})
	if not await _until(func() -> bool: return builder.pending.is_empty() and not _result(builder_results, confirmation_sequence).is_empty() and int(general.state.get("spent", -1)) == 110, "distinct confirmation after resend is accepted at the next command sequence"):
		_finish()
		return
	var confirmation_result: Dictionary = _result(builder_results, confirmation_sequence)
	_check(confirmation_result.get("ok", false) and not confirmation_result.get("replayed", true), "distinct confirmation succeeds instead of a command identity conflict")
	_check(builder.sequence == confirmation_sequence and int(general.state.spent) == 110 and not general.state.reservations.has("Builder") and _socket_zero_towers(general.state) == 1, "confirmation spends 110 once and creates one socket-zero tower site")

	# SECOND FIXTURE: restore the accepted confirmation as though its acknowledgment
	# had not reached saved client state. The true native reconnect path must query
	# command_status, recover a cached result, and avoid executing the purchase twice.
	var accepted_pending: Dictionary = builder.last_command.duplicate(true)
	if not await _disconnect_builder("disconnect after server accepted confirmation"):
		_finish()
		return
	builder.pending = accepted_pending
	var recovered_result_start: int = builder_results.size()
	builder.reconnect()
	if not await _until(func() -> bool: return builder.joined and builder.pending.is_empty() and not _result(builder_results, confirmation_sequence, recovered_result_start).is_empty() and bool(general.state.get("connected", {}).get("Builder", false)), "welcome queries the status of an already accepted pending command"):
		_finish()
		return
	var recovered_result: Dictionary = _result(builder_results, confirmation_sequence, recovered_result_start)
	_check(recovered_result.get("ok", false) and recovered_result.get("replayed", false), "accepted pending restoration receives cached successful result")
	_check(recovered_result.get("result", {}) == confirmation_result.get("result", {}), "status recovery preserves the original authoritative outcome")
	_check(int(general.state.get("spent", -1)) == 110 and _socket_zero_towers(general.state) == 1 and not general.state.reservations.has("Builder"), "accepted status recovery neither spends again nor creates another tower")
	_check(builder.sequence == confirmation_sequence and builder.role == "Builder" and builder.token == saved_builder_token, "cached result recovery preserves local sequence and seat identity")

	var next_sequence: int = confirmation_sequence + 1
	builder.command({"action": "ready", "value": false})
	if not await _until(func() -> bool: return builder.pending.is_empty() and not _result(builder_results, next_sequence).is_empty() and not bool(general.state.get("readiness", {}).get("Builder", true)), "a distinct command after cached recovery uses the next sequence normally"):
		_finish()
		return
	_check(_result(builder_results, next_sequence).get("ok", false) and builder.sequence == next_sequence, "post-recovery command identity continues without conflict")
	_check(general.role == "General" and general.sequence == 1 and general.token == saved_general_token, "Builder recovery does not alter the independent General client")
	_finish()


func _disconnect_builder(description: String) -> bool:
	builder.drop_link()
	if not await _until(func() -> bool: return builder.closed_reported and builder.peer.get_ready_state() == WebSocketPeer.STATE_CLOSED and not bool(general.state.get("connected", {}).get("Builder", true)), description):
		return false
	_check(not builder.joined and general.joined and general.state.get("status", "") == "paused", "real missing Builder transport pauses the authority while General stays joined")
	var paused_tick: int = int(general.state.get("tick", -1))
	var observed: int = general_snapshots
	if not await _until(func() -> bool: return general_snapshots > observed, "General observes a further snapshot while Builder is absent"):
		return false
	_check(int(general.state.get("tick", -2)) == paused_tick, "authoritative ticks remain frozen across disconnected snapshots")
	return true


func _result(replies: Array[Dictionary], seq: int, after: int = 0) -> Dictionary:
	for index: int in range(after, replies.size()):
		if int(replies[index].get("seq", -1)) == seq:
			return replies[index]
	return {}


func _socket_zero_towers(state: Dictionary) -> int:
	var count: int = 0
	for value: Variant in state.get("buildings", []):
		var structure: Dictionary = value
		if structure.get("kind", "") == "tower" and structure.get("team", "") == "ally" and int(structure.get("socket", -1)) == 0:
			count += 1
	return count


func _until(predicate: Callable, description: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + WAIT_MS
	while Time.get_ticks_msec() < deadline:
		if bool(predicate.call()):
			_check(true, description)
			return true
		await process_frame
	_check(false, "timeout: " + description)
	return false


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
	print(JSON.stringify({"check": description, "status": "PASS" if condition else "FAIL"}))


func _finish() -> void:
	for client: Node in [builder, general]:
		if is_instance_valid(client):
			if client.peer != null:
				client.peer.close(1000, "native recovery regression finished")
			client.queue_free()
	print(JSON.stringify({"kind": "automated_native_production_client_recovery", "checks": checks,
		"failures": failures.size(), "pending_fixture_injection": true, "browser_interaction": false,
		"browser_local_storage_tested": false, "human_feedback": false, "tokens_logged": false}))
	quit(0 if failures.is_empty() else 1)
