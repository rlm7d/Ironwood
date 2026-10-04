#!/usr/bin/env python3
"""Generate an isolated disposable Godot capability fixture, never the game.

Usage: python3 generate_probe.py --build-id v1 --spin-rate 1.0
Native: godot --path /tmp/ironwood-capability-probe
Authority: godot --headless --path /tmp/ironwood-capability-probe -- --server
Checks: godot --headless --path /tmp/ironwood-capability-probe -- --self-test
Web: godot --headless --path /tmp/ironwood-capability-probe --export-release Web OUTPUT/index.html
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

PROJECT = '''; Generated disposable capability fixture. No production game rules.
config_version=5
[application]
config/name="Ironwood Disposable Capability Probe"
run/main_scene="res://main.tscn"
config/features=PackedStringArray("4.6")
[display]
window/size/viewport_width=960
window/size/viewport_height=640
window/size/window_width_override=960
window/size/window_height_override=640
[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
environment/defaults/default_clear_color=Color(0.045, 0.06, 0.1, 1)
'''

PRESETS = '''[preset.0]
name="Web"
platform="Web"
runnable=true
advanced_options=false
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
script_export_mode=2
[preset.0.options]
custom_template/debug=""
custom_template/release=""
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/export_icon=false
html/custom_html_shell=""
html/head_include=""
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
html/experimental_virtual_keyboard=false
progressive_web_app/enabled=false
'''

AUTHORITY = '''extends RefCounted
# Every rule in this file is disposable capability-probe policy.
# Two seats; pause shared simulation whenever a seat is missing.
var tick: int = 0
var phase: float = 0.0
var x: float = 0.0
var selected: bool = false
var actions: int = 0
var connected: Dictionary = {"Builder": false, "General": false}
var sequence: Dictionary = {"Builder": 0, "General": 0}
var counts: Dictionary = {"Builder": 0, "General": 0}
var accepted: Dictionary = {"Builder": {}, "General": {}}

func paused() -> bool:
    return not (connected["Builder"] and connected["General"])

func advance(dt: float, rate: float) -> void:
    tick += 1
    if not paused():
        phase += dt * rate

func command(role: String, seq: int, action: String) -> String:
    if role not in sequence:
        return "invalid_role"
    if seq in accepted[role]:
        return "replayed_applied" if accepted[role][seq] == action else "command_id_conflict"
    if seq <= int(sequence[role]):
        return "stale_command"
    if paused():
        return "paused"
    if action != "select" and action != ("right" if role == "Builder" else "left"):
        return "permission_denied"
    if action == "select":
        selected = not selected
    else:
        x = clampf(x + (0.35 if action == "right" else -0.35), -2.0, 2.0)
    sequence[role] = seq
    accepted[role][seq] = action
    actions += 1
    counts[role] += 1
    return "applied"

func snapshot() -> Dictionary:
    return {"type": "snapshot", "tick": tick, "phase": phase, "x": x,
        "selected": selected, "actions": actions, "paused": paused(),
        "connected": connected.duplicate(), "counts": counts.duplicate(),
        "sequence": sequence.duplicate()}
'''

MAIN = '''extends Node3D
const Authority = preload("res://authority.gd")
const Config = preload("res://probe_config.gd")
const WS_URL = "ws://127.0.0.1:8765"
var authority = Authority.new()
var server: bool = false
var tcp: TCPServer
var connections: Dictionary = {}
var slots: Dictionary = {"Builder": {"token": "", "peer": 0}, "General": {"token": "", "peer": 0}}
var next_id: int = 1
var accumulator: float = 0.0
var socket: WebSocketPeer
var role: String = "Local"
var token: String = ""
var sequence: int = 0
var last_command: Dictionary = {}
var sent_join: bool = false
var snapshot: Dictionary = {}
var local_x: float = 0.0
var local_phase: float = 0.0
var local_selected: bool = false
var local_actions: int = 0
var status: String = "Native local mode. Click cube; D/right moves; Space toggles selection."
var cube: MeshInstance3D
var camera: Camera3D
var material: StandardMaterial3D
var state_label: Label
var status_label: Label
var control_row: HBoxContainer
var replay_row: HBoxContainer

func _ready() -> void:
    var args = OS.get_cmdline_user_args()
    if "--self-test" in args:
        self_test()
        return
    server = "--server" in args
    if server:
        tcp = TCPServer.new()
        var error = tcp.listen(8765, "127.0.0.1")
        if error != OK:
            push_error("Probe authority listen failed: " + str(error))
            get_tree().quit(1)
            return
        print("Disposable capability authority listening on loopback port 8765; build " + Config.BUILD_ID)
        return
    make_scene()

func make_scene() -> void:
    camera = Camera3D.new()
    camera.position = Vector3(0, 4, 7)
    add_child(camera)
    camera.look_at(Vector3(0, 0.5, 0))
    var light = DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-55, -35, 0)
    light.light_energy = 1.5
    add_child(light)
    var floor_node = MeshInstance3D.new()
    var plane = PlaneMesh.new()
    plane.size = Vector2(7, 5)
    floor_node.mesh = plane
    var floor_material = StandardMaterial3D.new()
    floor_material.albedo_color = Color(0.12, 0.17, 0.2)
    floor_node.material_override = floor_material
    add_child(floor_node)
    cube = MeshInstance3D.new()
    cube.mesh = BoxMesh.new()
    material = StandardMaterial3D.new()
    material.albedo_color = Color(0.1, 0.7, 0.9)
    cube.material_override = material
    cube.position.y = 0.8
    add_child(cube)
    var marker = MeshInstance3D.new()
    marker.mesh = SphereMesh.new()
    marker.scale = Vector3.ONE * 0.22
    marker.position = Vector3(0.7, 0.4, 0)
    cube.add_child(marker)
    var layer = CanvasLayer.new()
    add_child(layer)
    var panel = VBoxContainer.new()
    panel.position = Vector2(16, 12)
    panel.size = Vector2(580, 210)
    layer.add_child(panel)
    var title = Label.new()
    title.text = "DISPOSABLE PROBE | " + Config.BUILD_ID + " | spin rate " + str(Config.SPIN_RATE)
    title.add_theme_font_size_override("font_size", 20)
    panel.add_child(title)
    var policy = Label.new()
    policy.text = "TOY POLICY ONLY: Builder right; General left. Missing seat pauses.\nNo economy or intended-game rules."
    panel.add_child(policy)
    control_row = HBoxContainer.new()
    panel.add_child(control_row)
    add_button("JOIN BUILDER", func(): connect_role("Builder"))
    add_button("JOIN GENERAL", func(): connect_role("General"))
    add_button("ACTION (D/A)", perform_action)
    replay_row = HBoxContainer.new()
    panel.add_child(replay_row)
    control_row = replay_row
    add_button("REPLAY LAST", replay_last)
    add_button("DROP LINK", drop_link)
    add_button("RECONNECT", reconnect)
    state_label = Label.new()
    state_label.add_theme_font_size_override("font_size", 20)
    panel.add_child(state_label)
    status_label = Label.new()
    panel.add_child(status_label)
    var help = Label.new()
    help.text = "Click moving cube to select. Native D/right moves; Space selects.\nBrowser D/A acts; Space selects. Native local mode needs no JOIN."
    panel.add_child(help)

func add_button(text: String, callback: Callable) -> void:
    var button = Button.new()
    button.text = text
    button.pressed.connect(callback)
    control_row.add_child(button)

func _process(dt: float) -> void:
    if server:
        poll_server(dt)
        return
    if not is_instance_valid(cube):
        return
    poll_client()
    var x = local_x
    var phase = local_phase
    var selected = local_selected
    if role == "Local":
        local_phase += dt
        phase = local_phase
    elif not snapshot.is_empty():
        x = float(snapshot.x)
        phase = float(snapshot.phase)
        selected = bool(snapshot.selected)
    cube.position = Vector3(x, 0.8 + sin(phase * 2) * 0.15, 0)
    # This disposable presentation setting can be rebuilt without restarting authority.
    cube.rotation.y = phase * Config.SPIN_RATE
    material.albedo_color = Color(1, 0.65, 0.1) if selected else Color(0.1, 0.7, 0.9)
    if role == "Local":
        state_label.text = "Seat LOCAL | x %.2f | angle %.2f\nselected %s | actions %d" % [x, phase * Config.SPIN_RATE, selected, local_actions]
    elif snapshot.is_empty():
        state_label.text = "Seat %s | waiting for authoritative snapshot" % role
    else:
        state_label.text = "Seat %s | tick %d | x %.2f\nselected %s | actions %d | paused %s" % [role, snapshot.tick, x, selected, snapshot.actions, snapshot.paused]
    status_label.text = status

func _unhandled_input(event: InputEvent) -> void:
    if server:
        return
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        var screen = camera.unproject_position(cube.global_position)
        if event.position.distance_to(screen) < 100:
            select_action()
    if event is InputEventKey and event.pressed and not event.echo:
        if event.physical_keycode in [KEY_D, KEY_A, KEY_RIGHT, KEY_LEFT]:
            perform_action()
        elif event.physical_keycode == KEY_SPACE:
            select_action()

func perform_action() -> void:
    if role == "Local":
        local_x = clampf(local_x + 0.35, -2.0, 2.0)
        local_actions += 1
        status = "Real keyboard/button action moved local cube."
    else:
        send_action("right" if role == "Builder" else "left")

func select_action() -> void:
    if role == "Local":
        local_selected = not local_selected
        local_actions += 1
        status = "Real mouse/Space action toggled local selection."
    else:
        send_action("select")

func connect_role(new_role: String) -> void:
    if socket != null:
        socket.close()
    role = new_role
    token = load_token(role)
    reconnect()

func reconnect() -> void:
    if role == "Local":
        return
    socket = WebSocketPeer.new()
    sent_join = false
    snapshot = {}
    var error = socket.connect_to_url(WS_URL)
    status = "Connecting " + role if error == OK else "Connection error " + str(error)

func drop_link() -> void:
    if socket != null:
        socket.close(1000, "probe disconnect")
        socket = null
        status = "Disconnected; RECONNECT restores the same disposable seat."

func poll_client() -> void:
    if socket == null:
        return
    socket.poll()
    if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
        status = "Socket closed; RECONNECT restores the same disposable seat."
        return
    if socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
        return
    if not sent_join:
        socket.send_text(JSON.stringify({"type": "join", "role": role, "token": token}))
        sent_join = true
    while socket.get_available_packet_count() > 0:
        var message = JSON.parse_string(socket.get_packet().get_string_from_utf8())
        if not message is Dictionary:
            continue
        if message.type == "welcome":
            token = message.token
            sequence = int(message.sequence)
            save_token(role, token)
            status = "Joined " + role + "; connection " + str(message.connection_id) + "; resume sequence " + str(sequence)
        elif message.type == "snapshot":
            snapshot = message
        elif message.type == "result":
            status = "Command " + str(message.seq) + ": " + str(message.result)
        elif message.type == "error":
            status = "Join refused: " + str(message.reason)

func send_action(action: String) -> void:
    if socket == null or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
        status = "Join a seat before issuing a command."
        return
    sequence += 1
    last_command = {"type": "command", "seq": sequence, "action": action}
    socket.send_text(JSON.stringify(last_command))

func replay_last() -> void:
    if not last_command.is_empty() and socket != null and socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
        socket.send_text(JSON.stringify(last_command))

func load_token(seat: String) -> String:
    if OS.has_feature("web"):
        var value = JavaScriptBridge.eval("localStorage.getItem(" + JSON.stringify("ironwood-probe-seat-" + seat) + ")", true)
        return str(value) if value != null else ""
    return ""

func save_token(seat: String, value: String) -> void:
    if OS.has_feature("web"):
        JavaScriptBridge.eval("localStorage.setItem(" + JSON.stringify("ironwood-probe-seat-" + seat) + "," + JSON.stringify(value) + ")", true)

func poll_server(dt: float) -> void:
    while tcp.is_connection_available():
        var peer = WebSocketPeer.new()
        var error = peer.accept_stream(tcp.take_connection())
        if error == OK:
            connections[next_id] = {"ws": peer, "role": ""}
            next_id += 1
    for id in connections.keys():
        var connection = connections[id]
        var peer: WebSocketPeer = connection.ws
        peer.poll()
        if peer.get_ready_state() == WebSocketPeer.STATE_CLOSED:
            print("PROBE disconnect connection=%d role=%s tick=%d actions=%d" % [id, connection.role, authority.tick, authority.actions])
            if connection.role != "" and slots[connection.role].peer == id:
                authority.connected[connection.role] = false
                slots[connection.role].peer = 0
            connections.erase(id)
            continue
        while peer.get_ready_state() == WebSocketPeer.STATE_OPEN and peer.get_available_packet_count() > 0:
            var message = JSON.parse_string(peer.get_packet().get_string_from_utf8())
            if message is Dictionary:
                receive(id, message)
    accumulator += dt
    while accumulator >= 0.05:
        accumulator -= 0.05
        # Probe authority keeps time at fixed rate; build configs affect presentation only.
        authority.advance(0.05, 1.0)
        if authority.tick % 2 == 0:
            broadcast(authority.snapshot())

func receive(id: int, message: Dictionary) -> void:
    var connection = connections[id]
    if message.get("type", "") == "join":
        var requested: String = str(message.get("role", ""))
        if requested not in slots:
            send_to(id, {"type": "error", "reason": "invalid_role"})
            return
        var slot = slots[requested]
        if slot.peer != 0:
            send_to(id, {"type": "error", "reason": "seat_in_use"})
            return
        if slot.token != "" and slot.token != message.get("token", ""):
            send_to(id, {"type": "error", "reason": "seat_token_required"})
            return
        if slot.token == "":
            slot.token = Crypto.new().generate_random_bytes(24).hex_encode()
        slot.peer = id
        connection.role = requested
        authority.connected[requested] = true
        print("PROBE welcome connection=%d role=%s tick=%d actions=%d resume_seq=%d" % [id, requested, authority.tick, authority.actions, authority.sequence[requested]])
        send_to(id, {"type": "welcome", "token": slot.token, "sequence": authority.sequence[requested], "connection_id": id})
        broadcast(authority.snapshot())
    elif message.get("type", "") == "command":
        var seq = int(message.get("seq", 0))
        var result = authority.command(connection.role, seq, str(message.get("action", "")))
        print("PROBE command connection=%d role=%s tick=%d seq=%d result=%s actions=%d" % [id, connection.role, authority.tick, seq, result, authority.actions])
        send_to(id, {"type": "result", "seq": seq, "result": result})
        broadcast(authority.snapshot())

func send_to(id: int, message: Dictionary) -> void:
    connections[id].ws.send_text(JSON.stringify(message))

func broadcast(message: Dictionary) -> void:
    for id in connections.keys():
        if connections[id].role != "" and connections[id].ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
            send_to(id, message)

func self_test() -> void:
    var test = Authority.new()
    assert(test.paused())
    assert(test.command("Builder", 1, "right") == "paused")
    test.connected = {"Builder": true, "General": true}
    assert(test.command("Builder", 1, "left") == "permission_denied")
    assert(test.command("Builder", 1, "right") == "applied")
    var expected = test.x
    assert(test.command("Builder", 1, "right") == "replayed_applied")
    assert(test.x == expected and test.actions == 1)
    assert(test.command("Builder", 1, "select") == "command_id_conflict")
    assert(test.x == expected and test.actions == 1 and not test.selected)
    assert(test.command("General", 1, "left") == "applied")
    assert(is_zero_approx(test.x) and test.actions == 2)
    test.advance(0.1, 1.0)
    var phase = test.phase
    test.connected.General = false
    test.advance(0.1, 1.0)
    assert(test.phase == phase)
    test.connected.General = true
    assert(test.command("General", 2, "left") == "applied")
    assert(test.actions == 3)
    print("AUTOMATED DISPOSABLE CHECKS PASS: pause, resume, seat permission, accepted-command replay, conflicting command ID rejection, sequence continuity. This is not interactive Gate 0 evidence.")
    get_tree().quit()
'''


def project_settings(text):
    """Recognize only Godot's harmless formatting/default-feature normalization."""
    section = ''
    settings = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith(';'):
            continue
        if line.startswith('[') and line.endswith(']'):
            section = line[1:-1]
            continue
        if '=' not in line:
            raise ValueError('unrecognized project configuration')
        key, value = line.split('=', 1)
        identifier = (section, key.strip())
        if identifier in settings:
            raise ValueError('duplicate project setting')
        settings[identifier] = value.strip()
    features = ('application', 'config/features')
    if settings.get(features) == 'PackedStringArray("4.6")':
        settings.pop(features)
    texture_default = ('rendering', 'textures/default_filters/use_nearest_mipmap_filter')
    if settings.get(texture_default) == 'false':
        settings.pop(texture_default)
    return settings


def same_generated_project(text):
    try:
        return project_settings(text) == project_settings(PROJECT)
    except ValueError:
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=Path('/tmp/ironwood-capability-probe'))
    parser.add_argument('--build-id', default='v1')
    parser.add_argument('--spin-rate', type=float, default=1.0)
    args = parser.parse_args()
    if not args.build_id.replace('-', '').replace('_', '').isalnum():
        parser.error('build ID must be letters, numbers, underscore or dash')
    if not 0.1 <= args.spin_rate <= 10.0:
        parser.error('spin rate must be 0.1 to 10.0')
    args.output = args.output.resolve()
    if (args.output.parent != Path('/tmp')
            or not (args.output.name == 'ironwood-capability-probe'
                    or args.output.name.startswith('ironwood-capability-probe-'))):
        parser.error('output must be an isolated /tmp/ironwood-capability-probe[-suffix] folder')
    if (args.output / '.git').exists() or (args.output / '.git').is_symlink():
        parser.error('preserving repository checkout; output must be disposable')
    args.output.mkdir(parents=True, exist_ok=True)
    files = {'project.godot': PROJECT, 'export_presets.cfg': PRESETS,
             'main.gd': MAIN, 'authority.gd': AUTHORITY,
             'main.tscn': '[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://main.gd" id="1"]\n[node name="CapabilityProbe" type="Node3D"]\nscript = ExtResource("1")\n',
             'probe_config.gd': 'extends RefCounted\nconst BUILD_ID = "' + args.build_id + '"\nconst SPIN_RATE = ' + repr(args.spin_rate) + '\n'}
    marker = args.output / '.ironwood-disposable-probe.json'
    for name in list(files) + [marker.name, '.godot']:
        if (args.output / name).is_symlink():
            parser.error('preserving unexpected symbolic link in disposable output: ' + name)
    if marker.exists():
        ownership = json.loads(marker.read_text())
        if (ownership.get('owner') != 'ironwood-cloud-harness'
                or ownership.get('path') != str(args.output)
                or set(ownership.get('source_sha256', {})) != set(files)):
            parser.error('preserving unexpected disposable-project marker')
        for name, expected_hash in ownership['source_sha256'].items():
            target = args.output / name
            if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest() != expected_hash:
                if name != 'project.godot' or not target.is_file() or not same_generated_project(target.read_text()):
                    parser.error('preserving modified fixture source: ' + name)
    elif any(args.output.iterdir()):
        # Adopt only the exact fixture emitted by the earlier version of this
        # helper. This is an ownership check, not permission to overwrite user code.
        for name, content in files.items():
            target = args.output / name
            if not target.is_file():
                parser.error('preserving unrecognized nonempty output directory')
            existing = target.read_text(encoding='utf-8')
            if name == 'probe_config.gd':
                recognized = re.fullmatch(r'extends RefCounted\nconst BUILD_ID = "[A-Za-z0-9_-]+"\nconst SPIN_RATE = [0-9]+(?:\.[0-9]+)?\n', existing)
                if not recognized:
                    parser.error('preserving unexpected existing probe configuration')
            elif existing != content and not (name == 'project.godot' and same_generated_project(existing)):
                parser.error('preserving unrecognized existing fixture source: ' + name)
    for name, content in files.items():
        target = args.output / name
        if not target.exists() or target.read_text(encoding='utf-8') != content:
            target.write_text(content, encoding='utf-8')
    ownership = {'owner': 'ironwood-cloud-harness', 'schema': 1, 'path': str(args.output),
                 'build_id': args.build_id, 'spin_rate': args.spin_rate,
                 'source_sha256': {name: hashlib.sha256(content.encode('utf-8')).hexdigest()
                                   for name, content in files.items()}}
    marker_text = json.dumps(ownership, indent=2) + '\n'
    if not marker.exists() or marker.read_text() != marker_text:
        marker.write_text(marker_text, encoding='utf-8')
    print(f'Generated disposable probe {args.build_id} rate={args.spin_rate} at {args.output}')


if __name__ == '__main__':
    main()
