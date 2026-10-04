extends Node

const Rules = preload("res://scripts/shared/rules.gd")
signal snapshot_received(state: Dictionary)
signal notice(message: String)
signal connection_changed(connected: bool)
signal result_received(result: Dictionary)

var endpoint: String = "ws://127.0.0.1:8775"
var room: String = "REACH-01"
var role: String = ""
var token: String = ""
var sequence: int = 0
var revision: int = 0
var peer: WebSocketPeer
var joined: bool = false
var sent_join: bool = false
var pending: Dictionary = {}
var last_command: Dictionary = {}
var state: Dictionary = {}
var storage_ok: bool = true
var closed_reported: bool = false

func _ready() -> void:
    if OS.has_feature("web"):
        var configured = JavaScriptBridge.eval("new URL(location.href).searchParams.get('server')", true)
        if configured != null and str(configured).begins_with("wss://"):
            endpoint = str(configured)
        elif configured != null and str(configured).begins_with("ws://127.0.0.1:"):
            endpoint = str(configured)

func storage_key() -> String:
    # A seat belongs to one authority; changing ?server must not reuse its token.
    var authority_scope: String = (endpoint + "|" + str(Rules.PROTOCOL)).sha256_text()
    return "ironwood-" + Rules.BUILD_ID + "-" + authority_scope + "-" + room + "-" + role

func read_storage() -> Dictionary:
    if not OS.has_feature("web"):
        return {}
    var expression: String = "(function(){try{return localStorage.getItem(" + JSON.stringify(storage_key()) + ");}catch(e){return '__unavailable__';}})()"
    var saved = JavaScriptBridge.eval(expression, true)
    if saved == "__unavailable__":
        storage_ok = false
        notice.emit("Browser storage is unavailable; reconnect works until this page closes.")
        return {}
    if saved == null:
        return {}
    var parsed = JSON.parse_string(str(saved))
    return parsed if parsed is Dictionary else {}

func save_storage() -> void:
    if not OS.has_feature("web") or not storage_ok:
        return
    var record: Dictionary = {"token": token, "sequence": sequence, "pending": pending}
    var expression: String = "(function(){try{localStorage.setItem(" + JSON.stringify(storage_key()) + "," + JSON.stringify(JSON.stringify(record)) + ");return true;}catch(e){return false;}})()"
    var success = JavaScriptBridge.eval(expression, true)
    if success != true:
        storage_ok = false
        notice.emit("Browser storage is unavailable; keep this page open to retain your seat.")

func join(new_role: String) -> void:
    if new_role not in ["Builder", "General"]:
        return
    if joined and role != new_role:
        notice.emit("This page already owns a seat. Use the other browser for the other role.")
        return
    role = new_role
    var saved: Dictionary = read_storage()
    token = str(saved.get("token", token))
    sequence = int(saved.get("sequence", 0))
    pending = saved.get("pending", {})
    reconnect()

func reconnect() -> void:
    if role.is_empty():
        notice.emit("Choose Builder or General first.")
        return
    if peer != null:
        peer.close()
    peer = WebSocketPeer.new()
    peer.inbound_buffer_size = 262144
    peer.outbound_buffer_size = 65536
    sent_join = false
    joined = false
    closed_reported = false
    var error: int = peer.connect_to_url(endpoint)
    if error != OK:
        notice.emit("Cannot connect to the battle server. Check its address.")
    else:
        notice.emit("Connecting " + role + "…")

func drop_link() -> void:
    if peer != null:
        peer.close(1000, "Player requested trial disconnect")
    joined = false
    connection_changed.emit(false)
    notice.emit("Disconnected. Your seat and purchases are retained; reconnect to resume.")

func _process(_delta: float) -> void:
    if peer == null:
        return
    peer.poll()
    if peer.get_ready_state() == WebSocketPeer.STATE_CLOSED:
        if not closed_reported:
            joined = false
            closed_reported = true
            connection_changed.emit(false)
            notice.emit("Connection closed. Reconnect to recover your seat.")
        return
    if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
        return
    if not sent_join:
        sent_join = true
        peer.send_text(JSON.stringify({"type": "join", "protocol": Rules.PROTOCOL, "build_id": Rules.BUILD_ID, "room": room, "role": role, "token": token}))
    var count: int = 0
    while peer.get_available_packet_count() > 0 and count < 64:
        count += 1
        var packet: PackedByteArray = peer.get_packet()
        if packet.size() > 262144:
            continue
        var message = JSON.parse_string(packet.get_string_from_utf8())
        if message is Dictionary:
            receive(message)

func receive(message: Dictionary) -> void:
    match str(message.get("type", "")):
        "welcome":
            token = str(message.get("token", ""))
            var server_sequence: int = int(message.get("sequence", 0))
            joined = true
            connection_changed.emit(true)
            notice.emit(role + " joined. Ready when both players are prepared.")
            if not pending.is_empty():
                var pending_sequence: int = int(pending.get("seq", 0))
                if pending_sequence <= server_sequence:
                    peer.send_text(JSON.stringify({"type": "command_status", "seq": pending_sequence}))
                elif pending_sequence == server_sequence + 1:
                    # An explicit retry keeps the same identity and payload.
                    peer.send_text(JSON.stringify(pending))
                else:
                    pending = {}
                    notice.emit("Pending order cannot be reconciled; inspect the current battlefield.")
            sequence = server_sequence
            save_storage()
        "snapshot":
            if message.get("build_id", "") != Rules.BUILD_ID:
                notice.emit("This game and server are different builds; reload the matching candidate.")
                return
            state = message
            revision = int(message.get("revision", 0))
            snapshot_received.emit(state)
        "result":
            var result_sequence: int = int(message.get("seq", 0))
            sequence = maxi(sequence, result_sequence)
            if result_sequence == int(pending.get("seq", -1)):
                pending = {}
                save_storage()
            result_received.emit(message)
        "error":
            notice.emit("Server: " + str(message.get("code", message.get("error", message.get("reason", "request rejected")))).replace("_", " "))

func command(payload: Dictionary) -> void:
    if not joined or peer == null or peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
        notice.emit("Join a seat before issuing an order.")
        return
    if not pending.is_empty():
        notice.emit("Waiting for the last order. Reconnect if the connection was interrupted.")
        return
    sequence += 1
    pending = {"type": "command", "seq": sequence, "expected_revision": revision, "payload": payload}
    last_command = pending.duplicate(true)
    save_storage()
    peer.send_text(JSON.stringify(pending))

func retry_last() -> void:
    if joined and not last_command.is_empty():
        peer.send_text(JSON.stringify(last_command))
