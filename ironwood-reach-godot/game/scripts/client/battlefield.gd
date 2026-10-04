extends Node3D

const Art = preload("res://scripts/client/art.gd")
const Net = preload("res://scripts/client/net_client.gd")
const Rules = preload("res://scripts/shared/rules.gd")
const MiniMap = preload("res://scripts/client/minimap.gd")
const BattleHud = preload("res://scripts/client/battle_hud.gd")
var network: Net
var camera: Camera3D
var target: Vector3 = Vector3.ZERO
var zoom: float = 1.0
var state: Dictionary = {}
var visuals: Dictionary = {}
var selection: Array[String] = []
var selected_building: String = ""
var selected_socket: int = -1
var groups: Dictionary = {}
var attack_mode: bool = false
var drag_start: Vector2
var dragging: bool = false
var pan_drag: bool = false
var keys: Dictionary = {}
var phase: float = 0.0
var hover_marker: Node3D
var command_marker: Node3D
var marker_time: float = 0.0
var overlay: Control
var top: PanelContainer
var bottom: PanelContainer
var drag_box: Panel
var title: Label
var connection_label: Label
var treasury_label: Label
var objective_label: Label
var selection_label: Label
var reservation_label: Label
var message_label: Label
var ready_button: Button
var builder_button: Button
var general_button: Button
var actions: HBoxContainer
var ability_buttons: Array[Button] = []
var minimap: MiniMap
var help_window: AcceptDialog
var last_role: String = ""
var battle_hud: BattleHud

func _ready() -> void:
    add_child(Art.terrain())
    var environment: WorldEnvironment = WorldEnvironment.new()
    environment.environment = Environment.new()
    environment.environment.background_mode = Environment.BG_COLOR
    environment.environment.background_color = Color("#172e36")
    environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.environment.ambient_light_color = Color("#b7d6e0")
    environment.environment.ambient_light_energy = 0.3
    environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    add_child(environment)
    var sun: DirectionalLight3D = DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-55, -28, 0)
    sun.light_color = Color("#ffedd1")
    sun.light_energy = 0.9
    sun.shadow_enabled = true
    sun.directional_shadow_max_distance = 85.0
    add_child(sun)
    camera = Camera3D.new()
    camera.projection = Camera3D.PROJECTION_ORTHOGONAL
    camera.current = true
    camera.near = 0.1
    camera.far = 160.0
    add_child(camera)
    hover_marker = Art.selection(1.8, Color(0.95, 0.75, 0.3, 0.7))
    hover_marker.visible = false
    add_child(hover_marker)
    command_marker = Art.selection(0.8, Color(0.5, 1.0, 0.85, 0.9))
    command_marker.visible = false
    add_child(command_marker)
    network = Net.new()
    network.snapshot_received.connect(update_snapshot)
    network.notice.connect(show_notice)
    network.result_received.connect(handle_result)
    network.connection_changed.connect(func(_online: bool): refresh_ui())
    add_child(network)
    build_ui()
    update_camera()
    get_viewport().size_changed.connect(resize_ui)
    resize_ui()
    set_process_input(true)
    get_window().focus_exited.connect(clear_input)

func panel_style() -> StyleBoxFlat:
    var style: StyleBoxFlat = StyleBoxFlat.new()
    style.bg_color = Color(0.05, 0.09, 0.12, 0.94)
    style.border_color = Color("#59756d")
    style.set_border_width_all(1)
    style.set_corner_radius_all(7)
    style.content_margin_left = 12
    style.content_margin_right = 12
    style.content_margin_top = 8
    style.content_margin_bottom = 8
    return style

func add_label(parent: Node, text: String, font_size: int = 14) -> Label:
    var label: Label = Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", maxi(font_size, 14))
    label.add_theme_color_override("font_color", Color("#e9eadc"))
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    parent.add_child(label)
    return label

func button(parent: Node, text: String, callback: Callable, tip: String = "") -> Button:
    var result: Button = Button.new()
    result.text = text
    result.tooltip_text = tip
    result.add_theme_font_size_override("font_size", 14)
    result.custom_minimum_size.y = 30
    result.focus_mode = Control.FOCUS_NONE
    result.pressed.connect(callback)
    parent.add_child(result)
    return result

func build_ui() -> void:
    var layer: CanvasLayer = CanvasLayer.new()
    add_child(layer)
    overlay = Control.new()
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    layer.add_child(overlay)
    battle_hud = BattleHud.new()
    battle_hud.camera = camera
    overlay.add_child(battle_hud)
    top = PanelContainer.new()
    top.add_theme_stylebox_override("panel", panel_style())
    overlay.add_child(top)
    var stack: VBoxContainer = VBoxContainer.new()
    top.add_child(stack)
    var headline: HBoxContainer = HBoxContainer.new()
    stack.add_child(headline)
    title = add_label(headline, "IRONWOOD REACH", 23)
    title.add_theme_color_override("font_color", Color("#edce89"))
    title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    button(headline, "Controls", func(): help_window.popup_centered(Vector2i(570, 430)))
    var seats: HFlowContainer = HFlowContainer.new()
    seats.add_theme_constant_override("h_separation", 6)
    seats.add_theme_constant_override("v_separation", 4)
    stack.add_child(seats)
    builder_button = button(seats, "Join Builder", func(): network.join("Builder"), "Structures, defenses and expansion")
    general_button = button(seats, "Join General", func(): network.join("General"), "Recruit and command battalions")
    ready_button = button(seats, "Ready", toggle_ready)
    button(seats, "Reconnect", func(): network.reconnect())
    button(seats, "Disconnect", func(): network.drop_link(), "The battle pauses and retains both seats and purchases.")
    connection_label = add_label(stack, "REACH-01 · Join different roles in two browsers.")
    treasury_label = add_label(stack, "Trial shared treasury · Waiting for server")
    objective_label = add_label(stack, "Protect your keep · Destroy the enemy keep")
    bottom = PanelContainer.new()
    bottom.add_theme_stylebox_override("panel", panel_style())
    overlay.add_child(bottom)
    var horizontal: HBoxContainer = HBoxContainer.new()
    bottom.add_child(horizontal)
    var information: VBoxContainer = VBoxContainer.new()
    information.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    horizontal.add_child(information)
    selection_label = add_label(information, "Select a battalion, building or construction socket.")
    selection_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    actions = HBoxContainer.new()
    information.add_child(actions)
    var ability_row: HFlowContainer = HFlowContainer.new()
    ability_row.add_theme_constant_override("h_separation", 6)
    information.add_child(ability_row)
    ability_buttons.append(button(ability_row, "Q · Ability", func(): use_ability(0)))
    ability_buttons.append(button(ability_row, "E · Ability", func(): use_ability(1)))
    reservation_label = add_label(information, "No purchase held.")
    reservation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    var purchases: HFlowContainer = HFlowContainer.new()
    purchases.add_theme_constant_override("h_separation", 6)
    information.add_child(purchases)
    button(purchases, "Confirm purchase", func(): network.command({"action": "confirm"}))
    button(purchases, "Cancel hold", func(): network.command({"action": "cancel"}))
    button(purchases, "Retry last", func(): network.retry_last(), "Repeat the same order identity; an accepted purchase is not charged again.")
    message_label = add_label(information, "Map, controls, art and tuning await your approval.")
    message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    minimap = MiniMap.new()
    minimap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    horizontal.add_child(minimap)
    minimap.focus_requested.connect(func(point: Vector3): target = point; update_camera())
    drag_box = Panel.new()
    var box_style: StyleBoxFlat = StyleBoxFlat.new()
    box_style.bg_color = Color(0.4, 0.9, 0.75, 0.12)
    box_style.border_color = Color("#8cddbf")
    box_style.set_border_width_all(1)
    drag_box.add_theme_stylebox_override("panel", box_style)
    drag_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    drag_box.visible = false
    overlay.add_child(drag_box)
    help_window = AcceptDialog.new()
    help_window.title = "Battlefield trial controls"
    help_window.dialog_text = "Two players share one faction in room REACH-01.\nJoin different roles, then both press Ready.\n\nBuilder: select a fixed socket; hold a building purchase,\nthen Confirm. Select a building for its abilities.\nGeneral: select the barracks to recruit; click or drag-select\nbattalions. Right-click moves. A, then left-click attack-moves.\nShift adds selection. S stops. Q / E use role abilities.\nCtrl + 1–9 assigns a group; 1–9 recalls it.\n\nArrow keys pan · Middle-drag pans · Wheel zooms\nF centers selection · H returns to overview · Esc cancels\nMinimap click-to-pan appears in wider windows.\n\nDisconnect pauses the whole battle, retaining seats and holds.\nReconnect restores the original seat. Trial results do not\nrepresent a campaign run. Final content and tuning await approval."
    overlay.add_child(help_window)
    refresh_actions()

func resize_ui() -> void:
    var viewport_size: Vector2 = get_viewport().get_visible_rect().size
    # Apply visibility before measuring containers so a hidden minimap keeps no column.
    minimap.visible = viewport_size.x >= 860.0
    top.position = Vector2(12,12)
    var panel_width: float = maxf(1.0, viewport_size.x - 24.0)
    top.size.x = panel_width
    bottom.size.x = panel_width
    bottom.position = Vector2(12, viewport_size.y - bottom.size.y - 12.0)
    update_camera()

func update_camera() -> void:
    if camera == null:
        return
    var dimensions: Vector2 = get_viewport().get_visible_rect().size
    var aspect: float = dimensions.x / maxf(dimensions.y, 1.0)
    camera.size = 55.0 / maxf(aspect, 0.4) * zoom
    target.x = clampf(target.x, -23.0, 23.0)
    target.z = clampf(target.z, -16.0, 16.0)
    camera.position = target + Vector3(0, 44, 36)
    camera.look_at(target)

func update_snapshot(next: Dictionary) -> void:
    state = next
    selection.assign(commandable_selection(selection))
    phase = float(state.get("tick",0)) / 20.0
    minimap.state = state
    minimap.queue_redraw()
    var retained: Dictionary = {}
    for building in state.get("buildings", []):
        if float(building.hp) <= 0:
            retain_death(building,retained)
            continue
        sync_visual(building, "building")
        retained[str(building.id)] = true
    for unit in state.get("units", []):
        if float(unit.hp) <= 0:
            retain_death(unit,retained)
            continue
        sync_visual(unit, "unit")
        retained[str(unit.id)] = true
    for worker in state.get("workers", []):
        sync_visual(worker, "worker")
        retained[str(worker.id)] = true
    for id in visuals.keys():
        if not retained.has(id):
            visuals[id].node.queue_free()
            visuals.erase(id)
            selection.erase(str(id))
    refresh_ui()
    battle_hud.state = state
    battle_hud.selected = selection
    battle_hud.selected_building = selected_building
    battle_hud.queue_redraw()
    if not has_node("GoldDeposit") and state.has("deposit"):
        var ore: Node3D = Node3D.new()
        ore.name = "GoldDeposit"
        ore.position = Vector3(float(state.deposit.x),0,float(state.deposit.z))
        var material: StandardMaterial3D = StandardMaterial3D.new()
        material.albedo_color = Color("#b9a253")
        material.roughness = 0.6
        material.metallic = 0.2
        for index in range(6):
            var crystal: MeshInstance3D = MeshInstance3D.new()
            var mesh: CylinderMesh = CylinderMesh.new()
            mesh.top_radius = 0.0
            mesh.bottom_radius = 0.35
            mesh.height = 0.8 + (index % 3) * 0.35
            mesh.radial_segments = 5
            crystal.mesh = mesh
            crystal.material_override = material
            crystal.position = Vector3(sin(index * 2.4) * 1.1,mesh.height * 0.5,cos(index * 2.4) * 1.1)
            crystal.rotation.z = sin(index) * 0.15
            ore.add_child(crystal)
        add_child(ore)

func retain_death(entity: Dictionary,retained: Dictionary) -> void:
    var id: String = str(entity.id)
    if not visuals.has(id):
        return
    if not visuals[id].has("death_at"):
        visuals[id].death_at = Time.get_ticks_msec()
        visuals[id].entity = entity
        selection.erase(id)
        if selected_building == id: selected_building = ""
    if Time.get_ticks_msec() - int(visuals[id].death_at) < 1400:
        retained[id] = true

func sync_visual(entity: Dictionary, category: String) -> void:
    var id: String = str(entity.id)
    if not visuals.has(id):
        var root: Node3D
        if category == "building":
            root = Art.building(str(entity.kind), str(entity.team))
        elif category == "worker":
            root = Art.worker()
        else:
            root = Node3D.new()
            for index in range(int(entity.get("count",4))):
                var soldier: Node3D = Art.unit(str(entity.kind), str(entity.team))
                soldier.position = Vector3((index % 2 - 0.5) * 1.15,0,(index / 2 - 0.5) * 1.15)
                root.add_child(soldier)
        root.position = Vector3(float(entity.x),0,float(entity.z))
        add_child(root)
        var ring: Node3D = Art.selection(float(entity.get("radius",1.65)),Color(0.6,0.95,0.8,0.9))
        ring.visible = false
        root.add_child(ring)
        visuals[id] = {"node": root, "ring": ring, "category": category, "entity": entity}
    if float(entity.get("hp",1)) < float(visuals[id].entity.get("hp",1)):
        visuals[id].hit_until = Time.get_ticks_msec() + 150
    visuals[id].entity = entity

func _process(delta: float) -> void:
    if network.joined and state.get("status","waiting") == "playing":
        phase += delta
    if marker_time > 0:
        marker_time -= delta
        command_marker.visible = marker_time > 0
    var direction: Vector3 = Vector3.ZERO
    if keys.get(KEY_LEFT,false): direction.x -= 1
    if keys.get(KEY_RIGHT,false): direction.x += 1
    if keys.get(KEY_UP,false): direction.z -= 1
    if keys.get(KEY_DOWN,false): direction.z += 1
    if direction != Vector3.ZERO:
        target += direction.normalized() * delta * 15.0 * zoom
        update_camera()
    for id in visuals:
        var entry: Dictionary = visuals[id]
        var root: Node3D = entry.node
        var entity: Dictionary = entry.entity
        var destination: Vector3 = Vector3(float(entity.x),0,float(entity.z))
        var difference: Vector3 = destination - root.position
        root.position = root.position.lerp(destination, minf(delta * 12.0,1.0))
        var selected: bool = id in selection or id == selected_building
        entry.ring.visible = selected
        if entry.has("death_at"):
            var elapsed: float = float(Time.get_ticks_msec() - int(entry.death_at)) / 1400.0
            root.scale.y = maxf(0.04,1.0 - elapsed)
            root.rotation.z = elapsed * 0.5
            entry.ring.visible = false
            if entry.category == "unit":
                for soldier in root.get_children():
                    if soldier != entry.ring: Art.animate_unit(soldier,"dead",elapsed,false)
            continue
        if entry.category == "unit":
            if difference.length() > 0.01:
                root.rotation.y = atan2(difference.x,difference.z)
            for soldier in root.get_children():
                if soldier != entry.ring:
                    var animation: String = "hit" if int(entry.get("hit_until",0)) > Time.get_ticks_msec() else str(entity.get("state","idle"))
                    Art.animate_unit(soldier,animation,phase + float(id.hash() % 10) * 0.2,selected)
        elif entry.category == "worker":
            Art.animate_unit(root,"attack" if entity.get("state","") == "gather" else "walk" if entity.get("state","") in ["to_deposit","to_keep","return","moving"] else "idle",phase,false)
        elif entry.category == "building":
            var progress: float = float(entity.get("progress",1.0))
            root.scale.y = clampf(progress,0.08,1.0)
    # Wrapped labels first measure at a narrow provisional width during _ready.
    # Containers grow to that initial minimum but do not shrink automatically
    # after their real width is assigned. Fit the settled minimum each frame.
    top.size.y = top.get_combined_minimum_size().y
    bottom.size.y = bottom.get_combined_minimum_size().y
    var height: float = bottom.size.y
    bottom.position.y = get_viewport().get_visible_rect().size.y - height - 12.0
    battle_hud.selected = selection
    battle_hud.selected_building = selected_building
    battle_hud.queue_redraw()

func refresh_actions() -> void:
    for child in actions.get_children():
        child.queue_free()
    if network.role == "Builder":
        for kind in ["barracks","tower","sawmill"]:
            var chosen: String = kind
            button(actions, kind.capitalize(), func(): reserve_building(chosen))
    elif network.role == "General":
        button(actions,"Footmen",func(): reserve_unit("footmen"))
        button(actions,"Archers",func(): reserve_unit("archers"))
        button(actions,"Stop [S]",func(): issue_order(Vector3.ZERO,"stop"))
        button(actions,"Attack-move [A]",func(): attack_mode = true; show_notice("Click terrain for attack-move."))
    else:
        add_label(actions,"Choose a role to begin.",13)

func refresh_ui() -> void:
    if not is_instance_valid(connection_label):
        return
    if last_role != network.role:
        last_role = network.role
        refresh_actions()
    var connected: Dictionary = state.get("connections",{})
    var count: int = int(not str(connected.get("Builder","")).is_empty()) + int(not str(connected.get("General","")).is_empty())
    var status: String = str(state.get("status","waiting"))
    var seat_name: String = network.role if network.joined else "Choose a role" if network.role.is_empty() else network.role + " offline"
    connection_label.text = "REACH-01 · " + seat_name + " · " + str(count) + "/2 online · " + status.capitalize()
    if not network.joined and not network.role.is_empty():
        connection_label.text = "REACH-01 · " + seat_name + " · Showing last received state"
    if status == "paused":
        connection_label.text += "\nWaiting for the original player to reconnect."
    treasury_label.text = "Gold %d · Available %d · Held %d" % [int(state.get("gold",0)),int(state.get("available_gold",state.get("gold",0))),int(state.get("reserved_gold",0))]
    var remaining: int = maxi(0,int(state.get("trial_limit_ticks",6000)) - int(state.get("tick",0))) / 20
    objective_label.text = "Trial %d:%02d · Protect your keep; defeat the enemy keep" % [remaining / 60, remaining % 60]
    if status in ["victory","defeat"]:
        objective_label.text = status.to_upper() + " — practice battlefield complete"
    if not network.joined and not network.role.is_empty():
        objective_label.text = "Reconnect to restore the current battlefield."
    ready_button.disabled = not network.joined
    builder_button.disabled = network.joined
    general_button.disabled = network.joined
    var readiness: Dictionary = state.get("readiness",state.get("ready",{}))
    ready_button.text = "Unready" if readiness.get(network.role,false) else "Ready"
    if not selection.is_empty():
        selection_label.text = "%d battalion(s) · Right-click move · A + click attack-move" % selection.size()
        var health: int = 0
        var maximum: int = 0
        var march: int = 0
        var shield: int = 0
        for id: String in selection:
            var unit: Dictionary = find_entity(id)
            health += int(unit.get("hp",0))
            maximum += int(unit.get("max_hp",0))
            march = maxi(march,int(unit.get("march_ticks",0)))
            shield = maxi(shield,int(unit.get("shield_ticks",0)))
        selection_label.text += "\nHealth %d / %d" % [health,maximum]
        if march > 0:
            selection_label.text += " · March %ds: cannot attack" % ceili(float(march) / 20.0)
        if shield > 0:
            selection_label.text += " · Shield %ds: protected, slower" % ceili(float(shield) / 20.0)
    elif not selected_building.is_empty():
        var building: Dictionary = find_entity(selected_building)
        selection_label.text = str(building.get("kind","Building")).capitalize() + " · %d / %d health" % [int(building.get("hp",0)),int(building.get("max_hp",0))]
        if not building.get("ready",false):
            selection_label.text += " · Building %d%%" % int(float(building.get("progress",0.0)) * 100.0)
        elif int(building.get("overcharge_ticks",0)) > 0:
            selection_label.text += " · Overcharged %ds; shutdown follows" % ceili(float(building.overcharge_ticks) / 20.0)
        elif int(building.get("shutdown_ticks",0)) > 0:
            selection_label.text += " · Shut down %ds" % ceili(float(building.shutdown_ticks) / 20.0)
    elif selected_socket >= 0:
        selection_label.text = "Construction socket %d selected" % selected_socket
    else:
        selection_label.text = "Builder: sockets · General: battalions and barracks"
    var held: Dictionary = state.get("reservations",{})
    var hold_lines: Array[String] = []
    for seat in Rules.ROLES:
        var reservation: Dictionary = held.get(seat,{})
        if reservation.is_empty():
            hold_lines.append(seat + ": no hold")
        else:
            var location: String = " · socket %d" % int(reservation.socket) if reservation.has("socket") else " · barracks"
            hold_lines.append(seat + ": " + str(reservation.kind).capitalize() + " · %d gold" % int(reservation.cost) + location)
    reservation_label.text = "\n".join(hold_lines)
    var cooldowns: Array = state.get("abilities",{}).get(network.role,[0,0])
    var names: Array = ["Mend","Overcharge"] if network.role == "Builder" else ["Forced march","Shield wall"]
    for index in range(2):
        var seconds: int = ceili(float(cooldowns[index]) / 20.0) if cooldowns.size() > index else 0
        ability_buttons[index].text = ("Q" if index == 0 else "E") + " · " + names[index] + (" (%ds)" % seconds if seconds > 0 else "")
        ability_buttons[index].disabled = not network.joined or seconds > 0
        var tips: Array = ["Heal a selected building near your keep and allied battalions close to it. Retreat into its range for healing.","Boost a selected tower temporarily, followed by a shutdown."] if network.role == "Builder" else ["Move faster temporarily while giving up attacks.","Reduce incoming damage temporarily while moving slowly."]
        ability_buttons[index].tooltip_text = tips[index]
    hover_marker.visible = selected_socket >= 0
    if hover_marker.visible:
        for socket in state.get("sockets",[]):
            if int(socket.id) == selected_socket:
                hover_marker.position = Vector3(float(socket.x),0.04,float(socket.z))
    draw_sockets()

func draw_sockets() -> void:
    for socket in state.get("sockets",[]):
        var name: String = "Socket_%d" % int(socket.id)
        if not has_node(name):
            var secured: bool = false
            for territory in state.get("territories",[]):
                if int(territory.id) == int(socket.territory): secured = bool(territory.secured)
            var tint: Color = Color(0.95,0.78,0.48,0.7) if secured else Color(0.5,0.6,0.58,0.45)
            var ring: Node3D = Art.selection(1.9,tint)
            ring.name = name
            ring.position = Vector3(float(socket.x),0.03,float(socket.z))
            add_child(ring)
        var occupied: bool = false
        for building in state.get("buildings",[]):
            if int(building.get("socket",-1)) == int(socket.id) and float(building.hp) > 0: occupied = true
        get_node(name).visible = not occupied

func show_notice(message: String) -> void:
    if is_instance_valid(message_label):
        message_label.text = message

func handle_result(message: Dictionary) -> void:
    var outcome: Dictionary = message.get("result",{})
    if message.get("ok",false):
        show_notice("Order already applied; no duplicate charge." if message.get("replayed",false) else str(outcome.get("result","Order accepted.")).replace("_"," ").capitalize())
    else:
        show_notice(str(outcome.get("error",outcome.get("result","Order rejected"))).replace("_"," ").capitalize())

func toggle_ready() -> void:
    var readiness: Dictionary = state.get("readiness",state.get("ready",{}))
    network.command({"action":"ready","value":not bool(readiness.get(network.role,false))})

func reserve_building(kind: String) -> void:
    if selected_socket < 0:
        show_notice("Select a fixed construction socket first.")
        return
    network.command({"action":"reserve","kind":kind,"socket":selected_socket})

func reserve_unit(kind: String) -> void:
    var building: String = selected_building
    if building.is_empty() or find_entity(building).get("kind","") != "barracks":
        for entry in state.get("buildings",[]):
            if entry.kind == "barracks" and entry.team == "ally" and entry.get("ready",false):
                building = str(entry.id)
                break
    network.command({"action":"reserve","kind":kind,"building":building})

func find_entity(id: String) -> Dictionary:
    for entity in state.get("units",[]) + state.get("buildings",[]):
        if str(entity.id) == id:
            return entity
    return {}

func unit_is_commandable(entity: Dictionary) -> bool:
    return entity.get("team","") == "ally" and float(entity.get("hp",0)) > 0.0 and int(entity.get("train_ticks",0)) <= 0

func commandable_selection(values: Array) -> Array[String]:
    var eligible: Dictionary = {}
    for unit in state.get("units",[]):
        if unit_is_commandable(unit):
            eligible[str(unit.id)] = true
    var valid: Array[String] = []
    for value in values:
        var id: String = str(value)
        if eligible.has(id) and not id in valid:
            valid.append(id)
    return valid

func use_ability(slot: int) -> void:
    var payload: Dictionary = {"action":"ability","slot":slot}
    if network.role == "General":
        selection.assign(commandable_selection(selection))
        if selection.is_empty():
            show_notice("Select an allied battalion for this ability.")
            return
        payload.units = selection.duplicate()
    else:
        if selected_building.is_empty():
            show_notice("Select an allied building for this ability.")
            return
        payload.building = selected_building
    network.command(payload)

func issue_order(point: Vector3, mode: String) -> void:
    if network.role != "General":
        show_notice("The General commands the army.")
        return
    selection.assign(commandable_selection(selection))
    if selection.is_empty():
        show_notice("Select a battalion first.")
        return
    network.command({"action":"order","units":selection.duplicate(),"mode":mode,"x":point.x,"z":point.z})
    if mode != "stop":
        command_marker.position = point + Vector3(0,0.05,0)
        command_marker.visible = true
        marker_time = 1.6

func ground_point(screen: Vector2) -> Variant:
    return Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(screen),camera.project_ray_normal(screen))

func select_at(screen: Vector2, additive: bool) -> void:
    if attack_mode:
        var point = ground_point(screen)
        if point is Vector3:
            issue_order(point,"attack_move")
        attack_mode = false
        return
    if not additive:
        selection.clear()
        selected_building = ""
        selected_socket = -1
    var best_id: String = ""
    var distance: float = 28.0
    for id in visuals:
        var entry: Dictionary = visuals[id]
        var entity: Dictionary = entry.entity
        if entry.category == "worker" or entity.get("team","enemy") != "ally" or float(entity.get("hp",0)) <= 0.0:
            continue
        if entry.category == "unit" and not unit_is_commandable(entity):
            continue
        var screen_position: Vector2 = camera.unproject_position(entry.node.position + Vector3(0,0.9,0))
        var length: float = screen_position.distance_to(screen)
        if length < distance:
            distance = length
            best_id = str(id)
    if not best_id.is_empty():
        if visuals[best_id].category == "unit":
            if not best_id in selection: selection.append(best_id)
        else:
            selected_building = best_id
            selection.clear()
    elif network.role == "Builder":
        var nearest: float = 24.0
        for socket in state.get("sockets",[]):
            var screen_position: Vector2 = camera.unproject_position(Vector3(float(socket.x),0,float(socket.z)))
            var length: float = screen_position.distance_to(screen)
            if length < nearest:
                nearest = length
                selected_socket = int(socket.id)
    refresh_ui()

func end_drag(screen: Vector2, additive: bool) -> void:
    dragging = false
    drag_box.visible = false
    if drag_start.distance_to(screen) < 6.0:
        select_at(screen,additive)
        return
    if not additive:
        selection.clear()
        selected_building = ""
        selected_socket = -1
    var rect: Rect2 = Rect2(drag_start,screen-drag_start).abs()
    for id in visuals:
        var entry: Dictionary = visuals[id]
        if entry.category == "unit" and unit_is_commandable(entry.entity):
            if rect.has_point(camera.unproject_position(entry.node.position + Vector3(0,0.6,0))):
                if not str(id) in selection: selection.append(str(id))
    refresh_ui()

func clear_input() -> void:
    keys.clear()
    pan_drag = false
    dragging = false
    if is_instance_valid(drag_box):
        drag_box.visible = false

func _input(event: InputEvent) -> void:
    if event is InputEventKey and not event.pressed:
        keys.erase(event.keycode)
    if event is InputEventMouseButton and not event.pressed:
        if event.button_index == MOUSE_BUTTON_MIDDLE: pan_drag = false
        if event.button_index == MOUSE_BUTTON_LEFT and dragging:
            end_drag(event.position,event.shift_pressed)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
            zoom = maxf(0.32,zoom - 0.08)
            update_camera()
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            zoom = minf(1.1,zoom + 0.08)
            update_camera()
        elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            drag_start = event.position
            dragging = true
        elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
            var point = ground_point(event.position)
            if point is Vector3:
                issue_order(point,"move")
        elif event.button_index == MOUSE_BUTTON_MIDDLE:
            pan_drag = event.pressed
    elif event is InputEventMouseMotion:
        if pan_drag:
            target += Vector3(-event.relative.x,0,-event.relative.y) * 0.065 * zoom
            update_camera()
        if dragging and drag_start.distance_to(event.position) >= 6:
            var rectangle: Rect2 = Rect2(drag_start,event.position-drag_start).abs()
            drag_box.position = rectangle.position
            drag_box.size = rectangle.size
            drag_box.visible = true
    elif event is InputEventKey and event.pressed and not event.echo:
        keys[event.keycode] = true
        match event.keycode:
            KEY_ESCAPE:
                attack_mode = false
                selection.clear()
                selected_building = ""
                selected_socket = -1
                clear_input()
            KEY_A:
                attack_mode = true
                show_notice("Click terrain to attack-move.")
            KEY_S: issue_order(Vector3.ZERO,"stop")
            KEY_Q: use_ability(0)
            KEY_E: use_ability(1)
            KEY_H:
                target = Vector3.ZERO
                zoom = 1.0
                update_camera()
            KEY_F:
                if not selection.is_empty():
                    var entity: Dictionary = find_entity(selection[0])
                    target = Vector3(float(entity.get("x",0)),0,float(entity.get("z",0)))
                    zoom = 0.6
                    update_camera()
        if event.keycode >= KEY_1 and event.keycode <= KEY_9:
            var slot: int = event.keycode - KEY_1
            if event.ctrl_pressed:
                groups[slot] = commandable_selection(selection)
            else:
                selection.assign(commandable_selection(groups.get(slot,[])))
        refresh_ui()
