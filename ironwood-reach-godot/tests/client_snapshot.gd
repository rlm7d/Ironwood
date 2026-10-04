extends SceneTree

## Automated presentation-boundary supplement, not browser interaction evidence.
## godot --headless --path game --script ../tests/client_snapshot.gd
## A real simulation snapshot passes through Godot's wire-format JSON conversion
## before the production client consumes it. No server or credentials are needed.
const Battle = preload("res://scripts/simulation/battle.gd")
const Field = preload("res://scripts/client/battlefield.gd")
const Rules = preload("res://scripts/shared/rules.gd")

class CommandCapture:
	extends "res://scripts/client/net_client.gd"
	var sent: Array[Dictionary] = []
	func command(payload: Dictionary) -> void:
		sent.append(payload.duplicate(true))

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(640, 820)
	var simulation: Variant = Battle.new()
	simulation.initialize(7)
	simulation.set_connected("Builder", true)
	simulation.set_connected("General", true)
	_check(simulation.command("Builder", {"action": "ready", "value": true}).get("ok", false), "simulation readies Builder through its normal command")
	_check(simulation.command("General", {"action": "ready", "value": true}).get("ok", false), "simulation readies General through its normal command")
	var source: Dictionary = simulation.snapshot()
	# The production session adapter adds these safe transport identifiers to the
	# simulation snapshot. This local fixture isolates their string-valued boundary.
	source["connections"] = {"Builder": "connection-test-Builder", "General": "connection-test-General"}
	var parsed: Variant = JSON.parse_string(JSON.stringify(source))
	_check(parsed is Dictionary, "simulation snapshot survives real JSON serialization and parsing")
	if not parsed is Dictionary:
		_finish()
		return
	var wire_snapshot: Dictionary = parsed
	_check(typeof(wire_snapshot.sockets[0].id) == TYPE_FLOAT, "wire-format socket IDs arrive as JSON floats")
	_check(wire_snapshot.connections.Builder is String and wire_snapshot.connections.General is String, "wire-format connection identifiers remain strings")

	var field: Node3D = Field.new()
	root.add_child(field)
	# These two fields select the presentation branch only. Net has no peer and
	# never connects; this is not a multiplayer or reconnect claim.
	field.network.role = "Builder"
	field.network.joined = true
	field.update_snapshot(wire_snapshot)
	for _frame: int in range(4):
		await process_frame

	var expected_visuals: int = wire_snapshot.buildings.size() + wire_snapshot.units.size() + wire_snapshot.workers.size()
	var expected_sockets: int = wire_snapshot.sockets.size()
	var original_rings: Dictionary = {}
	for socket_value: Variant in wire_snapshot.sockets:
		var socket: Dictionary = socket_value
		var name: String = "Socket_%d" % int(socket.id)
		var ring: Node = field.get_node_or_null(name)
		_check(ring != null, "float socket %d resolves to its stable sanitized ring name" % int(socket.id))
		if ring != null:
			original_rings[name] = ring
	_check(expected_sockets == 8 and _socket_count(field) == expected_sockets, "initial JSON snapshot creates exactly eight socket rings")
	_check(field.visuals.size() == expected_visuals, "initial snapshot creates one production visual per live entity")
	var original_visuals: Dictionary = {}
	for key: Variant in field.visuals.keys():
		original_visuals[str(key)] = field.visuals[key].node
	var original_children: int = field.get_child_count()
	var original_descendants: int = _descendant_count(field)

	for repetition: int in range(10):
		field.update_snapshot(wire_snapshot)
		await process_frame
		_check(_socket_count(field) == expected_sockets and field.get_child_count() == original_children, "repeated JSON snapshot %d does not accumulate root nodes or socket rings" % (repetition + 1))
	var rings_unchanged: bool = true
	for name: Variant in original_rings.keys():
		if field.get_node_or_null(str(name)) != original_rings[name]:
			rings_unchanged = false
	_check(rings_unchanged and original_rings.size() == 8, "all eight socket ring instances survive repeated snapshots")
	var visuals_unchanged: bool = field.visuals.size() == expected_visuals
	for id: Variant in original_visuals.keys():
		if not field.visuals.has(id) or field.visuals[id].node != original_visuals[id]:
			visuals_unchanged = false
	_check(visuals_unchanged, "normal building, battalion, and worker visual identities persist")
	_check(_descendant_count(field) == original_descendants, "repeated snapshots keep the full scene descendant count stable")

	var top: Control = field.top
	var bottom: Control = field.bottom
	_check(root.get_visible_rect().size == Vector2(640, 820), "layout inspection uses an actual 640 by 820 viewport")
	_check(is_equal_approx(top.size.x, 616) and is_equal_approx(bottom.size.x, 616), "HUD panels fit the narrow viewport with twelve-pixel margins")
	_check(is_equal_approx(top.size.y, top.get_combined_minimum_size().y) and top.size.y <= 220, "top panel shrinks to its settled wrapped-label minimum")
	_check(is_equal_approx(bottom.size.y, bottom.get_combined_minimum_size().y) and bottom.size.y <= 260, "bottom panel shrinks to its settled wrapped-label minimum")
	_check(top.position.y + top.size.y < bottom.position.y and is_equal_approx(bottom.position.y + bottom.size.y, 808), "settled panels leave the battlefield clear and keep the bottom margin")
	_check(not field.minimap.visible, "narrow HUD hides the minimap instead of reserving a column")
	_check(field.connection_label.text.contains("2/2 online"), "string connection IDs render the correct two-seat status")
	var original_top_size: Vector2 = top.size
	var original_bottom_size: Vector2 = bottom.size
	var layouts: Array[Dictionary] = [_layout_snapshot(field, "initial_narrow")]

	root.size = Vector2i(1280, 820)
	field.update_snapshot(wire_snapshot)
	for _frame: int in range(4):
		await process_frame
	_check_resized_layout(field, Vector2i(1280, 820), true, "wide")
	_check_scene_identity(field, original_rings, original_visuals, original_children, original_descendants, "wide resize")
	layouts.append(_layout_snapshot(field, "wide"))

	root.size = Vector2i(640, 820)
	field.update_snapshot(wire_snapshot)
	for _frame: int in range(4):
		await process_frame
	_check_resized_layout(field, Vector2i(640, 820), false, "restored narrow")
	_check(top.size.is_equal_approx(original_top_size) and bottom.size.is_equal_approx(original_bottom_size), "restoring the narrow viewport restores its original settled panel sizes")
	_check_scene_identity(field, original_rings, original_visuals, original_children, original_descendants, "narrow restore")
	layouts.append(_layout_snapshot(field, "restored_narrow"))
	_check_tactical_feedback(field, wire_snapshot)
	await _check_selection_boundary(field)
	for _frame: int in range(4):
		await process_frame
	print(JSON.stringify({"layout_stages": layouts,
		"socket_rings": _socket_count(field), "entity_visuals": field.visuals.size(), "scene_descendants": _descendant_count(field)}))
	field.queue_free()
	_finish()


func _check_selection_boundary(field: Node3D) -> void:
	# Ordinary production simulation commands create a real training battalion.
	# Later zero-health/removal snapshots are explicitly local fixtures; they
	# exercise production selection against known state, not browser input.
	var battle: Variant = Battle.new()
	battle.initialize(7)
	battle.set_connected("Builder", true)
	battle.set_connected("General", true)
	battle.command("Builder", {"action": "ready", "value": true})
	battle.command("General", {"action": "ready", "value": true})
	battle.command("General", {"action": "reserve", "kind": "footmen", "building": "ally_barracks"})
	var purchase: Dictionary = battle.command("General", {"action": "confirm"})
	var wire: Dictionary = JSON.parse_string(JSON.stringify(battle.snapshot()))
	var training_id: String = ""
	var live_id: String = ""
	for unit: Dictionary in wire.units:
		if unit.team == "ally":
			if unit.train_ticks > 0: training_id = str(unit.id)
			else: live_id = str(unit.id)
	_check(purchase.get("ok", false) and not training_id.is_empty() and not live_id.is_empty(),
		"ordinary reserve and confirm commands produce distinct ready and training battalions for selection tests")
	if training_id.is_empty() or live_id.is_empty(): return
	field.network.role = "General"
	field.selection.clear()
	field.selected_building = ""
	field.update_snapshot(wire)
	await process_frame
	var training_point: Vector2 = field.camera.unproject_position(field.visuals[training_id].node.position + Vector3(0, 0.9, 0))
	var live_point: Vector2 = field.camera.unproject_position(field.visuals[live_id].node.position + Vector3(0, 0.9, 0))
	field.select_at(training_point, false)
	_check(field.selection.is_empty(), "clicking a known training battalion does not select an uncommandable unit")
	field.select_at(live_point, false)
	field.select_at(training_point, true)
	_check(field.selection == [live_id], "additive click on a training battalion retains the ready battalion alone")
	field.drag_start = Vector2.ZERO
	field.end_drag(root.get_visible_rect().size, false)
	_check(field.selection == [live_id], "drag selection covering both battalions excludes the known training unit")
	field.groups[0] = [training_id, live_id, "missing_battalion", live_id]
	var recall: InputEventKey = InputEventKey.new()
	recall.keycode = KEY_1
	recall.pressed = true
	field._unhandled_input(recall)
	_check(field.selection == [live_id], "control group recall keeps ready members and filters training, missing and duplicate IDs")
	field.selection.assign([training_id, live_id, "missing_battalion"])
	field.update_snapshot(wire)
	_check(field.selection == [live_id], "a received snapshot prunes current selection to commandable members")
	# Capture only the production client's outgoing payload boundary. The spy
	# has no peer, does not connect, and is never used in interactive evidence.
	var original_network: Node = field.network
	var capture: CommandCapture = CommandCapture.new()
	field.add_child(capture)
	capture.role = "General"
	capture.joined = true
	field.network = capture
	field.selection.assign([training_id, live_id, "missing_battalion"])
	field.issue_order(Vector3(-5, 0, 5), "move")
	_check(capture.sent.size() == 1 and capture.sent[0].units == [live_id],
		"production order boundary sends only ready members when local selection contains stale IDs")
	_check(capture.sent.size() == 1 and battle.command("General", capture.sent[0]).get("ok", false),
		"a training member no longer poisons an otherwise valid ready-battalion order at the authority")
	field.selection.assign([training_id, live_id, "missing_battalion"])
	field.use_ability(1)
	_check(capture.sent.size() == 2 and capture.sent[1].units == [live_id],
		"production General ability boundary sends only ready members")
	field.selection.assign([training_id, "missing_battalion"])
	field.issue_order(Vector3.ZERO, "stop")
	field.selection.assign([training_id, "missing_battalion"])
	field.use_ability(1)
	_check(capture.sent.size() == 2 and field.selection.is_empty(),
		"orders and General abilities send no command when every selected member is known invalid")
	field.network = original_network
	capture.queue_free()
	for _tick: int in range(int(battle.units[training_id].train_ticks)):
		battle.step()
	wire = JSON.parse_string(JSON.stringify(battle.snapshot()))
	field.update_snapshot(wire)
	training_point = field.camera.unproject_position(field.visuals[training_id].node.position + Vector3(0, 0.9, 0))
	field.select_at(training_point, false)
	_check(field.selection == [training_id], "a battalion becomes selectable after real simulation training completes")
	# The dead entity is intentionally still present for the production 1.4s
	# death animation; it must not be reintroduced into selection during it.
	for unit: Dictionary in wire.units:
		if str(unit.id) == live_id: unit.hp = 0
	field.selection.assign([live_id])
	field.update_snapshot(wire)
	_check(field.selection.is_empty() and field.visuals[live_id].has("death_at"),
		"a zero-health snapshot clears selection while retaining its death-animation visual")
	var dead_point: Vector2 = field.camera.unproject_position(field.visuals[live_id].node.position + Vector3(0, 0.9, 0))
	field.select_at(dead_point, false)
	_check(not live_id in field.selection, "clicking a retained death-animation visual cannot reselect the dead battalion")
	field.drag_start = dead_point - Vector2(8, 8)
	field.end_drag(dead_point + Vector2(8, 8), false)
	_check(not live_id in field.selection, "dragging over a retained death-animation visual cannot reselect the dead battalion")
	field.groups[0] = [live_id, training_id, "missing_battalion"]
	field._unhandled_input(recall)
	_check(field.selection == [training_id], "recalling a group after a death retains its surviving ready member")
	wire.units = wire.units.filter(func(unit: Dictionary) -> bool: return str(unit.id) != live_id)
	field.update_snapshot(wire)
	field._unhandled_input(recall)
	_check(field.selection == [training_id], "recalling a group after entity removal cannot restore the missing member")
	# A unit can still die after the client received a valid snapshot. Preserve
	# authoritative whole-command rejection for this unavoidable timing race.
	battle.units[training_id].hp = 0
	var race_result: Dictionary = battle.command("General", {"action": "order", "units": field.selection.duplicate(), "mode": "stop", "x": 0, "z": 0})
	_check(field.selection == [training_id] and not race_result.get("ok", false) and race_result.get("result", "") == "invalid_units",
		"the authority still rejects a battalion that dies after the client's valid received snapshot")
	print(JSON.stringify({"selection_fixture_scope": "Local production client with ordinary training commands, explicit received death/removal fixtures, and captured payloads; no browser interaction or multiplayer claim."}))


func _check_tactical_feedback(field: Node3D, wire_snapshot: Dictionary) -> void:
	# Explicit presentation fixtures exercise received-state labels only. These
	# active flags/health values are not produced by commands, gameplay input, a
	# server, or an application hook; no ability-rule outcome is claimed here.
	var feedback: Dictionary = wire_snapshot.duplicate(true)
	var unit: Dictionary = feedback.units[0]
	unit.hp = 75
	unit.march_ticks = 41
	unit.shield_ticks = 21
	field.network.role = "General"
	field.selection.assign([str(unit.id)])
	field.selected_building = ""
	field.update_snapshot(feedback)
	_check(field.selection_label.text.contains("Health 75 / %d" % int(unit.max_hp)), "selected battalion feedback displays received health and maximum health")
	_check(field.selection_label.text.contains("March 3s: cannot attack"), "received march ticks show rounded-up active duration and attack sacrifice")
	_check(field.selection_label.text.contains("Shield 2s: protected, slower"), "received shield ticks show rounded-up active duration and movement tradeoff")
	_check(field.ability_buttons[0].tooltip_text.contains("giving up attacks")
		and field.ability_buttons[1].tooltip_text.contains("incoming damage")
		and field.ability_buttons[1].tooltip_text.contains("slowly"),
		"General role tooltips describe march and shield tradeoffs")
	var active_unit_label: String = field.selection_label.text
	unit.march_ticks = 0
	unit.shield_ticks = 0
	field.update_snapshot(feedback)
	_check(not field.selection_label.text.contains("March ") and not field.selection_label.text.contains("Shield "),
		"expired received flags remove active-unit feedback instead of leaving stale durations")

	var tower: Dictionary = feedback.buildings[0].duplicate(true)
	tower.id = "presentation_tower"
	tower.kind = "tower"
	tower.team = "ally"
	tower.x = -10.0
	tower.z = 0.0
	tower.hp = 320
	tower.max_hp = 370
	tower.radius = 1.4
	tower.ready = false
	tower.progress = 0.5
	tower.build_ticks = 70
	tower.total_build_ticks = 140
	tower.overcharge_ticks = 0
	tower.shutdown_ticks = 0
	feedback.buildings.append(tower)
	field.network.role = "Builder"
	field.selection.clear()
	field.selected_building = str(tower.id)
	field.update_snapshot(feedback)
	_check(field.selection_label.text.contains("320 / 370 health") and field.selection_label.text.contains("Building 50%"),
		"selected construction feedback displays received building health and progress")
	var construction_label: String = field.selection_label.text
	tower.ready = true
	tower.progress = 1.0
	tower.build_ticks = 0
	tower.overcharge_ticks = 41
	field.update_snapshot(feedback)
	_check(field.selection_label.text.contains("Overcharged 3s; shutdown follows") and not field.selection_label.text.contains("Building "),
		"received overcharge state replaces construction progress with duration and shutdown consequence")
	var overcharge_label: String = field.selection_label.text
	tower.overcharge_ticks = 0
	tower.shutdown_ticks = 21
	field.update_snapshot(feedback)
	_check(field.selection_label.text.contains("Shut down 2s") and not field.selection_label.text.contains("Overcharged "),
		"received shutdown state replaces the completed overcharge feedback")
	_check(field.ability_buttons[0].tooltip_text.contains("Retreat") and field.ability_buttons[0].tooltip_text.contains("range")
		and field.ability_buttons[1].tooltip_text.contains("shutdown"),
		"Builder role tooltips describe local healing positioning and overcharge shutdown")
	print(JSON.stringify({"presentation_feedback_fixture": {"unit_label": active_unit_label,
		"construction_label": construction_label, "overcharge_label": overcharge_label,
		"shutdown_label": field.selection_label.text,
		"scope": "Explicit received-state flags and a synthetic tower test presentation text only; no gameplay or ability outcome is asserted."}}))


func _check_resized_layout(field: Node3D, dimensions: Vector2i, expected_minimap: bool, stage: String) -> void:
	var viewport_size: Vector2 = root.get_visible_rect().size
	var top: Control = field.top
	var bottom: Control = field.bottom
	_check(viewport_size == Vector2(dimensions), "%s layout uses the actual %d by %d viewport" % [stage, dimensions.x, dimensions.y])
	_check(top.position == Vector2(12, 12) and is_equal_approx(bottom.position.x, 12)
		and is_equal_approx(top.size.x, viewport_size.x - 24) and is_equal_approx(bottom.size.x, viewport_size.x - 24),
		"%s HUD preserves twelve-pixel top and horizontal margins" % stage)
	_check(is_equal_approx(top.size.y, top.get_combined_minimum_size().y) and top.size.y <= 220,
		"%s top panel settles to its wrapped minimum without covering the battlefield" % stage)
	_check(is_equal_approx(bottom.size.y, bottom.get_combined_minimum_size().y) and bottom.size.y <= 260,
		"%s bottom panel settles to its wrapped minimum without covering the battlefield" % stage)
	_check(bottom.position.y - (top.position.y + top.size.y) >= 300
		and is_equal_approx(bottom.position.y + bottom.size.y, viewport_size.y - 12),
		"%s panels leave at least three hundred central pixels and preserve the bottom margin" % stage)
	var minimap_valid: bool = not field.minimap.visible and not field.minimap.is_visible_in_tree()
	if expected_minimap:
		minimap_valid = field.minimap.visible and field.minimap.is_visible_in_tree()
		minimap_valid = minimap_valid and field.minimap.size.x >= 146 and field.minimap.size.y >= 104
		minimap_valid = minimap_valid and bottom.get_global_rect().encloses(field.minimap.get_global_rect())
	_check(minimap_valid, "%s minimap visibility and bounds match the actual viewport" % stage)


func _check_scene_identity(field: Node3D, rings: Dictionary, visuals: Dictionary, children: int, descendants: int, stage: String) -> void:
	var rings_unchanged: bool = _socket_count(field) == rings.size()
	for name: Variant in rings.keys():
		if field.get_node_or_null(str(name)) != rings[name]:
			rings_unchanged = false
	_check(rings_unchanged, "%s retains every socket ring instance" % stage)
	var visuals_unchanged: bool = field.visuals.size() == visuals.size()
	for id: Variant in visuals.keys():
		if not field.visuals.has(id) or field.visuals[id].node != visuals[id]:
			visuals_unchanged = false
	_check(visuals_unchanged, "%s retains every building, battalion and worker visual instance" % stage)
	_check(field.get_child_count() == children and _descendant_count(field) == descendants,
		"%s retains the original root and descendant node counts" % stage)


func _layout_snapshot(field: Node3D, stage: String) -> Dictionary:
	var viewport_size: Vector2 = root.get_visible_rect().size
	return {"stage": stage, "viewport": [viewport_size.x, viewport_size.y],
		"top_height": field.top.size.y, "bottom_height": field.bottom.size.y, "bottom_y": field.bottom.position.y,
		"central_clearance": field.bottom.position.y - (field.top.position.y + field.top.size.y),
		"minimap_visible": field.minimap.is_visible_in_tree(), "socket_rings": _socket_count(field),
		"entity_visuals": field.visuals.size(), "scene_descendants": _descendant_count(field)}


func _socket_count(field: Node) -> int:
	var count: int = 0
	for child: Node in field.get_children():
		if str(child.name).begins_with("Socket_"):
			count += 1
	return count


func _descendant_count(parent: Node) -> int:
	var count: int = 0
	for child: Node in parent.get_children():
		count += 1 + _descendant_count(child)
	return count


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
	print(JSON.stringify({"check": description, "status": "PASS" if condition else "FAIL"}))


func _finish() -> void:
	print(JSON.stringify({"kind": "automated_production_client_snapshot_boundary", "build_id": Rules.BUILD_ID,
		"checks": checks, "failures": failures.size(), "json_float_boundary_tested": true,
		"viewport_sizes_tested": [[640, 820], [1280, 820], [640, 820]], "headless_layout_tested": true,
		"explicit_presentation_flags_tested": true, "gameplay_input_tested": false,
		"known_invalid_selection_tested": true, "authoritative_post_snapshot_death_rejection_tested": true,
		"browser_interaction": false, "multiplayer_tested": false, "human_feedback": false,
		"performance_tested": false, "tokens_logged": false}))
	quit(0 if failures.is_empty() else 1)
