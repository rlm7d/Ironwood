extends SceneTree

# Run from the game project:
# godot --headless --path game --script ../tests/simulation_tests.gd
# Each scenario gets a fresh simulation. Direct state setup only isolates the
# condition under test; commands and fixed steps exercise the actual rules.
const Battle = preload("res://scripts/simulation/battle.gd")
const Rules = preload("res://scripts/shared/rules.gd")
const Art = preload("res://scripts/client/art.gd")

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_test_initial_readiness_and_pause()
	_test_deterministic_replay()
	_test_role_authority()
	_test_json_numeric_commands()
	_test_shared_reservations()
	_test_fixed_sockets_and_construction()
	_test_barracks_recruitment()
	_test_visual_navigation_clearance()
	_test_building_navigation()
	_test_distinct_group_destinations()
	_test_finite_worker_economy()
	_test_general_ability_tradeoffs()
	_test_builder_abilities()
	_test_far_building_attack_approach()
	_test_combat_and_terminal_states()
	if failures.is_empty():
		print("SIMULATION TESTS PASS: %d checks" % checks)
		quit(0)
	else:
		for failure: String in failures:
			printerr("FAIL: " + failure)
		printerr("SIMULATION TESTS FAIL: %d/%d checks failed" % [failures.size(), checks])
		quit(1)


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _battle(is_ready: bool = true, seed_value: int = 7) -> Variant:
	var sim: Variant = Battle.new()
	sim.initialize(seed_value)
	sim.connected["Builder"] = true
	sim.connected["General"] = true
	sim.readiness["Builder"] = is_ready
	sim.readiness["General"] = is_ready
	return sim


func _steps(sim: Variant, count: int, isolate: bool = false) -> void:
	for _index in range(count):
		if isolate:
			# Keep this scenario independent of the timed encounter.
			for unit_id: String in sim.units.keys():
				if unit_id != "unit_001":
					sim.units.erase(unit_id)
		sim.step()


func _command(sim: Variant, role: String, payload: Dictionary) -> bool:
	var reply: Dictionary = sim.command(role, payload)
	return bool(reply.get("ok", false))


func _reserve_build(sim: Variant, kind: String = "tower", socket: int = 0) -> bool:
	return _command(sim, "Builder", {"action": "reserve", "kind": kind, "socket": socket})


func _reserve_recruit(sim: Variant, kind: String = "footmen", building: String = "ally_barracks") -> bool:
	return _command(sim, "General", {"action": "reserve", "kind": kind, "building": building})


func _price(role: String, payload: Dictionary) -> int:
	var sim: Variant = _battle()
	sim.gold = 100000
	if not _command(sim, role, payload):
		_check(false, "valid purchase can be reserved to discover its configured price")
		return 0
	return int(sim.reservations[role]["cost"])


func _built_id(sim: Variant, previous_ids: Array) -> String:
	for building_id: String in sim.buildings.keys():
		if not previous_ids.has(building_id):
			return building_id
	return ""


func _build_tower(sim: Variant, socket: int = 0) -> String:
	var previous_ids: Array = sim.buildings.keys()
	if not _reserve_build(sim, "tower", socket):
		_check(false, "tower fixture reservation succeeds")
		return ""
	if not _command(sim, "Builder", {"action": "confirm"}):
		_check(false, "tower fixture confirmation succeeds")
		return ""
	var tower_id: String = _built_id(sim, previous_ids)
	if tower_id.is_empty():
		_check(false, "confirm creates a tower construction site")
		return ""
	for _index in range(1000):
		if bool(sim.buildings[tower_id]["ready"]):
			return tower_id
		_steps(sim, 1, true)
	_check(false, "tower construction completes within its bounded trial duration")
	return tower_id


func _test_initial_readiness_and_pause() -> void:
	var sim: Variant = _battle(false)
	var initial_tick: int = int(sim.tick)
	_steps(sim, 15)
	_check(int(sim.tick) == initial_tick, "battle waits for both roles to become ready")
	_check(_command(sim, "Builder", {"action": "ready", "value": true}), "Builder can ready their seat")
	_steps(sim, 5)
	_check(int(sim.tick) == initial_tick, "one ready player cannot start the battle")
	_check(_command(sim, "General", {"action": "ready", "value": true}), "General can ready their seat")
	_steps(sim, 5)
	_check(int(sim.tick) == initial_tick + 5, "both ready players advance one fixed tick per step")
	_check(_reserve_build(sim), "a reservation can exist before a disconnect")
	_check(_command(sim, "General", {"action": "order", "units": ["unit_001"], "mode": "move", "x": 8.0, "z": 2.0}) and _command(sim, "General", {"action": "ability", "slot": 0, "units": ["unit_001"]}), "movement and an active ability are underway before the disconnect")
	sim.set_connected("General", false)
	var paused_state: String = JSON.stringify(sim.snapshot())
	_steps(sim, 100)
	_check(JSON.stringify(sim.snapshot()) == paused_state, "disconnect freezes units, workers, cooldowns and tick together")
	_check(sim.reservations.has("Builder"), "disconnect preserves the player's reservation")
	sim.set_connected("General", true)
	_steps(sim, 1)
	_check(int(sim.tick) == initial_tick + 6, "reconnecting the same seat resumes without elapsed catch-up")
	sim.readiness["Builder"] = false
	var unready_tick: int = int(sim.tick)
	_steps(sim, 20)
	_check(int(sim.tick) == unready_tick, "withdrawing readiness pauses the active battle")


func _test_deterministic_replay() -> void:
	var first: Variant = _battle(true, 41)
	var second: Variant = _battle(true, 41)
	var commands: Array[Dictionary] = [
		{"action": "reserve", "kind": "tower", "socket": 0},
		{"action": "confirm"},
	]
	for payload: Dictionary in commands:
		_command(first, "Builder", payload)
		_command(second, "Builder", payload)
	var order: Dictionary = {"action": "order", "units": ["unit_001"], "mode": "move", "x": 7.0, "z": 10.0}
	_command(first, "General", order)
	_command(second, "General", order)
	_steps(first, 360)
	_steps(second, 360)
	_check(JSON.stringify(first.snapshot()) == JSON.stringify(second.snapshot()), "same seed, commands and fixed ticks reproduce the full battlefield snapshot")


func _test_role_authority() -> void:
	var sim: Variant = _battle()
	var original_gold: int = int(sim.gold)
	var original_goal: Array = sim.units["unit_001"]["goal"].duplicate()
	_check(not _command(sim, "General", {"action": "reserve", "kind": "tower", "socket": 0}), "General cannot reserve Builder construction")
	_check(not _command(sim, "Builder", {"action": "reserve", "kind": "footmen", "building": "ally_barracks"}), "Builder cannot reserve General recruitment")
	_check(not _command(sim, "Builder", {"action": "order", "units": ["unit_001"], "mode": "move", "x": 10.0, "z": 10.0}), "Builder cannot command the General's army")
	_check(not _command(sim, "Spectator", {"action": "ready", "value": true}), "unassigned roles cannot send authoritative commands")
	_check(not _command(sim, "General", {"action": "order", "units": ["missing_unit"], "mode": "move", "x": 1.0, "z": 1.0}), "orders require an existing controllable unit")
	_check(int(sim.gold) == original_gold and sim.reservations.is_empty(), "rejected role commands do not alter treasury or reservations")
	_check(sim.units["unit_001"]["goal"] == original_goal, "rejected role commands do not alter army orders")


func _test_shared_reservations() -> void:
	var build_cost: int = _price("Builder", {"action": "reserve", "kind": "tower", "socket": 0})
	var recruit_cost: int = _price("General", {"action": "reserve", "kind": "footmen", "building": "ally_barracks"})
	_check(build_cost > 0 and recruit_cost > 0, "both roles make positive-cost purchases from shared gold")
	var sim: Variant = _battle()
	sim.gold = build_cost + recruit_cost - 1
	var initial_gold: int = int(sim.gold)
	_check(_reserve_build(sim), "Builder can hold affordable funds")
	_check(int(sim.gold) == initial_gold and int(sim.available_gold()) == initial_gold - build_cost, "reservation holds funds without charging gold")
	_check(not _reserve_build(sim, "tower", 1), "each player has only one visible reservation")
	_check(not _reserve_recruit(sim), "second role cannot reserve funds already held by the first role")
	_check(sim.reservations.size() == 1 and int(sim.gold) == initial_gold, "failed competing reservation is atomic")
	_check(_command(sim, "Builder", {"action": "cancel"}), "owner can cancel their held reservation")
	_check(sim.reservations.is_empty() and int(sim.available_gold()) == initial_gold, "cancel restores all spendable funds without creating gold")
	sim.gold = build_cost + recruit_cost
	_check(_reserve_build(sim) and _reserve_recruit(sim), "both roles can reserve exactly affordable combined purchases")
	_check(int(sim.available_gold()) == 0, "all held funds are excluded from spendable gold")
	var before_buildings: int = sim.buildings.size()
	_check(_command(sim, "Builder", {"action": "confirm"}), "confirm commits the Builder purchase")
	_check(int(sim.gold) == recruit_cost and int(sim.spent) == build_cost, "confirm charges exactly one reservation and records spending")
	_check(not _command(sim, "Builder", {"action": "confirm"}), "repeated confirmation cannot start a duplicate purchase")
	_check(sim.buildings.size() == before_buildings + 1 and int(sim.gold) == recruit_cost, "repeated confirmation cannot duplicate a site or charge twice")
	_check(not _command(sim, "Builder", {"action": "cancel"}), "a confirmed purchase has no cancellable reservation")
	_check(_command(sim, "General", {"action": "confirm"}), "General can commit independently held recruitment funds")
	_check(int(sim.gold) == 0 and int(sim.spent) == build_cost + recruit_cost, "combined confirmations conserve initial gold exactly")
	_check(sim.reservations.is_empty(), "confirmation removes each owner's completed reservation")
	var held: Variant = _battle()
	_check(_reserve_build(held), "an unconfirmed purchase can remain held during play")
	var held_reservation: String = JSON.stringify(held.reservations["Builder"])
	var held_buildings: int = held.buildings.size()
	_steps(held, 1000, true)
	_check(JSON.stringify(held.reservations.get("Builder", {})) == held_reservation, "an active reservation has no automatic expiry")
	_check(int(held.spent) == 0 and held.buildings.size() == held_buildings, "holding funds never automatically charges or starts the purchase")


func _test_json_numeric_commands() -> void:
	var sim: Variant = _battle()
	var socket_payload: Dictionary = JSON.parse_string('{"action":"reserve","kind":"tower","socket":0.0}')
	_check(_command(sim, "Builder", socket_payload), "whole-number socket IDs survive JSON float decoding")
	_check(_command(sim, "Builder", {"action": "cancel"}), "JSON-decoded reservation remains cancellable")
	var before_fractional_socket: String = JSON.stringify(sim.snapshot())
	var fractional_socket: Dictionary = JSON.parse_string('{"action":"reserve","kind":"tower","socket":0.5}')
	_check(not _command(sim, "Builder", fractional_socket), "fractional socket IDs are rejected instead of truncated")
	_check(JSON.stringify(sim.snapshot()) == before_fractional_socket, "fractional socket rejection leaves battlefield and treasury unchanged")
	var slot_payload: Dictionary = JSON.parse_string('{"action":"ability","slot":0.0,"units":["unit_001"]}')
	_check(_command(sim, "General", slot_payload), "whole-number ability slots survive JSON float decoding")
	var before_fractional_slot: String = JSON.stringify(sim.snapshot())
	var fractional_slot: Dictionary = JSON.parse_string('{"action":"ability","slot":0.5,"units":["unit_001"]}')
	_check(not _command(sim, "General", fractional_slot), "fractional ability slots are rejected instead of truncated")
	_check(JSON.stringify(sim.snapshot()) == before_fractional_slot, "fractional slot rejection leaves effects and cooldowns unchanged")


func _test_fixed_sockets_and_construction() -> void:
	var sim: Variant = _battle()
	sim.gold = 10000
	_check(not _reserve_build(sim, "tower", -1), "construction rejects a nonexistent socket")
	_check(not _reserve_build(sim, "tower", 4), "construction rejects an unsecured territory socket")
	var initial_buildings: Array = sim.buildings.keys()
	_check(_reserve_build(sim, "tower", 0), "construction can reserve a secured fixed socket")
	_check(sim.buildings.size() == initial_buildings.size(), "reservation alone does not start construction")
	_check(_command(sim, "Builder", {"action": "confirm"}), "confirmation starts a fixed-socket construction site")
	var tower_id: String = _built_id(sim, initial_buildings)
	_check(not tower_id.is_empty(), "one new construction site exists after confirm")
	if tower_id.is_empty():
		return
	var tower: Dictionary = sim.buildings[tower_id]
	_check(is_equal_approx(float(tower["x"]), -13.0) and is_equal_approx(float(tower["z"]), 7.0), "the building occupies its fixed socket coordinates")
	_check(not bool(tower["ready"]), "confirmed construction is not instantly ready")
	_check(not _reserve_build(sim, "tower", 0), "an occupied construction socket cannot be purchased again")
	_steps(sim, 1000, true)
	_check(bool(sim.buildings[tower_id]["ready"]), "construction becomes ready through fixed-step simulation")
	_check(is_equal_approx(float(sim.buildings[tower_id]["x"]), -13.0) and is_equal_approx(float(sim.buildings[tower_id]["z"]), 7.0), "construction never moves away from its socket")


func _test_barracks_recruitment() -> void:
	var sim: Variant = _battle()
	sim.gold = 10000
	_check(not _reserve_recruit(sim, "footmen", "enemy_keep"), "recruitment rejects enemy infrastructure")
	_check(not _reserve_recruit(sim, "footmen", "ally_keep"), "recruitment requires the appropriate production building")
	sim.buildings["ally_barracks"]["ready"] = false
	_check(not _reserve_recruit(sim), "unfinished barracks cannot recruit")
	sim.buildings["ally_barracks"]["ready"] = true
	var initial_units: int = sim.units.size()
	_check(_reserve_recruit(sim), "ready allied barracks can reserve a battalion")
	_check(_command(sim, "General", {"action": "confirm"}), "General confirmation starts recruitment")
	_check(sim.units.size() == initial_units + 1, "recruitment creates exactly one battalion in training")
	var new_unit: Dictionary = {}
	var new_id: String = ""
	for unit_id: String in sim.units.keys():
		if unit_id != "unit_001":
			new_unit = sim.units[unit_id]
			new_id = unit_id
	if not new_unit.is_empty():
		_check(int(new_unit["train_ticks"]) > 0, "new recruitment requires time before it can join the army")
		_check(not _command(sim, "General", {"action": "order", "units": [new_id], "mode": "move", "x": 0.0, "z": 0.0}), "General cannot command a battalion while it is training")
		var spawn_point: Vector2 = Vector2(float(new_unit["x"]), float(new_unit["z"]))
		var barracks: Dictionary = sim.buildings["ally_barracks"]
		var barracks_point: Vector2 = Vector2(float(barracks["x"]), float(barracks["z"]))
		_check(spawn_point.distance_to(barracks_point) >= float(barracks["radius"]) + Battle.BODY_RADIUS, "the entire recruited battalion emerges outside the barracks footprint")
		for _index in range(800):
			if int(new_unit["train_ticks"]) == 0:
				break
			sim.step()
		_check(int(new_unit["train_ticks"]) == 0 and sim.units.size() == initial_units + 1, "fixed-step recruitment completes without duplicating the battalion")
		_check(_command(sim, "General", {"action": "order", "units": [new_id], "mode": "move", "x": 0.0, "z": 0.0}), "completed recruitment becomes controllable")


func _test_building_navigation() -> void:
	var sim: Variant = _battle()
	sim.gold = 10000
	var tower_id: String = _build_tower(sim)
	if tower_id.is_empty():
		return
	var unit: Dictionary = sim.units["unit_001"]
	unit["x"] = -23.0
	unit["z"] = 7.0
	var destination: Vector2 = Vector2(8.0, 7.0)
	_check(_command(sim, "General", {"action": "order", "units": ["unit_001"], "mode": "move", "x": destination.x, "z": destination.y}), "General can order open-terrain movement through a building-obstructed route")
	var clear: bool = true
	var travelled: bool = false
	for _index in range(1000):
		_steps(sim, 1, true)
		var point: Vector2 = Vector2(float(unit["x"]), float(unit["z"]))
		for building: Dictionary in sim.buildings.values():
			if float(building["hp"]) > 0.0:
				var building_point: Vector2 = Vector2(float(building["x"]), float(building["z"]))
				if point.distance_to(building_point) < float(building["radius"]) + Battle.BODY_RADIUS - 0.025:
					clear = false
		if point.distance_to(destination) < 0.6:
			travelled = true
			break
	_check(clear, "every sampled movement position keeps the complete four-soldier battalion outside live building footprints")
	_check(travelled, "building-aware navigation actually reaches the destination beyond the obstruction")


func _test_distinct_group_destinations() -> void:
	var sim: Variant = _battle()
	sim.gold = 10000
	_build_tower(sim, 1)
	_check(_reserve_recruit(sim) and _command(sim, "General", {"action": "confirm"}), "a second battalion is recruited for the group navigation scenario")
	_steps(sim, int(Rules.data().units.footmen.train_ticks))
	var selected: Array = ["unit_001", "unit_002"]
	_check(_command(sim, "General", {"action": "order", "units": selected, "mode": "move", "x": 19.0, "z": 0.0}), "a group can move toward an occupied keep footprint across an obstructed route")
	var first_goal: Vector2 = Vector2(sim.units.unit_001.goal[0], sim.units.unit_001.goal[1])
	var second_goal: Vector2 = Vector2(sim.units.unit_002.goal[0], sim.units.unit_002.goal[1])
	_check(first_goal.distance_to(second_goal) >= 1.75, "group formation destinations remain separated when desired offsets project onto the same blocked keep cell")
	var clear: bool = true
	var arrived: bool = false
	for _index in range(500):
		sim.step()
		arrived = true
		for id: String in selected:
			var unit: Dictionary = sim.units[id]
			var point: Vector2 = Vector2(unit.x, unit.z)
			var goal: Vector2 = Vector2(unit.goal[0], unit.goal[1])
			arrived = arrived and point.distance_to(goal) < 0.2
			for building: Dictionary in sim.buildings.values():
				if building.hp > 0 and point.distance_to(Vector2(building.x, building.z)) < float(building.radius) + Battle.BODY_RADIUS - 0.01:
					clear = false
		if arrived:
			break
	_check(clear, "both group routes retain full battalion clearance around the intervening tower and all other buildings")
	_check(arrived, "both battalions actually reach their separated endpoints beyond the intervening obstruction")
	var first_position: Vector2 = Vector2(sim.units.unit_001.x, sim.units.unit_001.z)
	var second_position: Vector2 = Vector2(sim.units.unit_002.x, sim.units.unit_002.z)
	_check(first_position.distance_to(second_position) >= 1.5, "group arrival preserves different root positions instead of stacking both battalions")
	_check(_command(sim, "General", {"action": "order", "units": ["unit_002", "unit_001"], "mode": "attack_move", "x": 19.0, "z": 0.0}), "attack-move group orders use the same reachable endpoint allocation")
	first_goal = Vector2(sim.units.unit_001.goal[0], sim.units.unit_001.goal[1])
	second_goal = Vector2(sim.units.unit_002.goal[0], sim.units.unit_002.goal[1])
	_check(first_goal.distance_to(second_goal) >= 1.75, "attack-move destinations stay distinct regardless of selected ID input order")
	var edge: Variant = _battle()
	edge.gold = 10000
	for _index in range(2):
		_reserve_recruit(edge)
		_command(edge, "General", {"action": "confirm"})
		_steps(edge, int(Rules.data().units.footmen.train_ticks))
	_check(_command(edge, "General", {"action": "order", "units": ["unit_003", "unit_001", "unit_002"], "mode": "move", "x": 26.0, "z": 19.0}), "a group order at the map corner accepts bounded alternatives for clipped formation offsets")
	var edge_goals: Array[Vector2] = []
	var separated: bool = true
	var valid: bool = true
	for id: String in ["unit_001", "unit_002", "unit_003"]:
		var unit: Dictionary = edge.units[id]
		var point: Vector2 = Vector2(unit.goal[0], unit.goal[1])
		valid = valid and point.x <= 26.0 and point.y <= 19.0 and point.x >= -26.0 and point.y >= -19.0
		for other: Vector2 in edge_goals:
			separated = separated and point.distance_to(other) >= 1.75
		edge_goals.append(point)
	_check(separated, "map-edge clamping does not collapse different battalion destinations")
	_check(valid, "group alternatives remain within existing map bounds")


func _test_finite_worker_economy() -> void:
	var sim: Variant = _battle()
	sim.deposit["remaining"] = 12
	sim.territories[0]["remaining"] = 12
	var starting_gold: int = int(sim.gold)
	var starting_gathered: int = int(sim.gathered)
	var conserved: bool = true
	for _index in range(700):
		_steps(sim, 1, true)
		var in_transit: int = 0
		for worker: Dictionary in sim.workers.values():
			in_transit += int(worker["carry"])
		if int(sim.deposit["remaining"]) + in_transit + int(sim.gathered) - starting_gathered != 12:
			conserved = false
	_check(int(sim.gathered) > starting_gathered, "automatic workers complete a physical collection-and-delivery cycle")
	_check(int(sim.gold) - starting_gold == int(sim.gathered) - starting_gathered, "delivered worker resources increase shared gold exactly once")
	_check(conserved, "deposit, carried resources and completed deliveries conserve resources every tick")
	_check(int(sim.deposit["remaining"]) == 0 and int(sim.gathered) - starting_gathered == 12, "workers finish the finite deposit without losing or inventing resources")
	var depleted_gold: int = int(sim.gold)
	var depleted_gathered: int = int(sim.gathered)
	_steps(sim, 600, true)
	_check(int(sim.gold) == depleted_gold and int(sim.gathered) == depleted_gathered, "exhausted deposits never mint more gold after final delivery")


func _test_general_ability_tradeoffs() -> void:
	var marching: Variant = _battle()
	var enemy_keep: Dictionary = marching.buildings["enemy_keep"]
	var unit: Dictionary = marching.units["unit_001"]
	unit["x"] = 15.0
	unit["z"] = 0.0
	var initial_enemy_hp: float = float(enemy_keep["hp"])
	_check(_command(marching, "General", {"action": "order", "units": ["unit_001"], "mode": "attack_move", "x": 19.0, "z": 0.0}), "General can issue an attack-move order")
	_check(_command(marching, "General", {"action": "ability", "slot": 0, "units": ["unit_001"]}), "forced march activates for a selected battalion")
	_check(not _command(marching, "General", {"action": "ability", "slot": 0, "units": ["unit_001"]}), "forced march cannot be reused during its cooldown")
	_steps(marching, 80, true)
	_check(float(enemy_keep["hp"]) == initial_enemy_hp and int(unit["march_ticks"]) > 0, "forced march temporarily gives up attacking")
	var normal: Variant = _battle()
	var shielded: Variant = _battle()
	for candidate: Variant in [normal, shielded]:
		candidate.units["unit_001"]["x"] = -6.0
		candidate.units["unit_001"]["z"] = 15.0
		_command(candidate, "General", {"action": "order", "units": ["unit_001"], "mode": "move", "x": 8.0, "z": 15.0})
	_check(_command(shielded, "General", {"action": "ability", "slot": 1, "units": ["unit_001"]}), "shield wall activates for a selected battalion")
	_check(not _command(shielded, "General", {"action": "ability", "slot": 1, "units": ["unit_001"]}), "shield wall cannot be reused during its cooldown")
	_steps(normal, 40, true)
	_steps(shielded, 40, true)
	var normal_distance: float = Vector2(float(normal.units["unit_001"]["x"]) + 6.0, float(normal.units["unit_001"]["z"]) - 15.0).length()
	var shield_distance: float = Vector2(float(shielded.units["unit_001"]["x"]) + 6.0, float(shielded.units["unit_001"]["z"]) - 15.0).length()
	_check(normal_distance > 0.1 and shield_distance < normal_distance * 0.8, "shield wall trades movement speed for protection")


func _test_builder_abilities() -> void:
	var sim: Variant = _battle()
	sim.buildings["ally_keep"]["hp"] = float(sim.buildings["ally_keep"]["max_hp"]) - 100.0
	var damaged_hp: float = float(sim.buildings["ally_keep"]["hp"])
	_check(_command(sim, "Builder", {"action": "ability", "slot": 0, "building": "ally_keep"}), "Builder can mend a nearby damaged allied building")
	_check(float(sim.buildings["ally_keep"]["hp"]) > damaged_hp, "mending restores building health")
	_check(not _command(sim, "Builder", {"action": "ability", "slot": 0, "building": "ally_keep"}), "mending has a cooldown")
	var foreign: Variant = _battle()
	_check(not _command(foreign, "Builder", {"action": "ability", "slot": 0, "building": "enemy_keep"}), "Builder cannot mend an enemy structure")
	foreign.buildings["ally_barracks"]["x"] = 5.0
	foreign.buildings["ally_barracks"]["z"] = 0.0
	foreign.buildings["ally_barracks"]["hp"] -= 100
	_check(not _command(foreign, "Builder", {"action": "ability", "slot": 0, "building": "ally_barracks"}), "mending respects its positional limit around the home keep")
	sim.gold = 10000
	var tower_id: String = _build_tower(sim)
	if tower_id.is_empty():
		return
	_check(_command(sim, "Builder", {"action": "ability", "slot": 1, "building": tower_id}), "Builder can overcharge a ready allied tower")
	_check(not _command(sim, "Builder", {"action": "ability", "slot": 1, "building": tower_id}), "tower overcharge has a cooldown")
	_steps(sim, int(Rules.data()["abilities"]["tower_overcharge"]["duration_ticks"]), true)
	_check(int(sim.buildings[tower_id].get("shutdown_ticks", 0)) > 0, "tower overcharge is followed by a shutdown tradeoff")


func _test_combat_and_terminal_states() -> void:
	var victory: Variant = _battle()
	victory.buildings["enemy_keep"]["hp"] = 1.0
	_command(victory, "General", {"action": "order", "units": ["unit_001"], "mode": "attack_move", "x": 19.0, "z": 0.0})
	_steps(victory, 700, true)
	_check(float(victory.buildings["enemy_keep"]["hp"]) <= 0.0, "an attacking battalion can destroy the enemy keep through combat")
	_check(str(victory.status) == "victory" and str(victory.result) == "enemy_keep_destroyed", "enemy keep destruction produces the victory result")
	_check(not _command(victory, "General", {"action": "order", "units": ["unit_001"], "mode": "move", "x": 0.0, "z": 0.0}), "terminal victory rejects new battlefield commands")
	var victory_snapshot: String = JSON.stringify(victory.snapshot())
	_steps(victory, 50)
	_check(JSON.stringify(victory.snapshot()) == victory_snapshot, "a completed battlefield stops simulation instead of continuing after victory")
	_test_terminal_connections(victory, "victory")
	var defeat: Variant = _battle()
	defeat.buildings["ally_keep"]["hp"] = 0.0
	_steps(defeat, 1)
	_check(str(defeat.status) == "defeat" and str(defeat.result) == "main_keep_destroyed", "home keep destruction gives the distinct loss result")
	var defeat_tick: int = int(defeat.tick)
	_steps(defeat, 50)
	_check(int(defeat.tick) == defeat_tick, "defeat is terminal and freezes fixed ticks")
	_test_terminal_connections(defeat, "defeat")


func _test_terminal_connections(sim: Variant, expected_status: String) -> void:
	var before: Dictionary = sim.snapshot()
	var before_revision: int = int(before.revision)
	sim.set_connected("General", false)
	var disconnected: Dictionary = sim.snapshot()
	_check(not bool(disconnected.connected.General), "terminal %s still reports a disconnected seat accurately" % expected_status)
	_check(int(disconnected.revision) == before_revision + 1, "terminal disconnect increments the observable revision once")
	_steps(sim, 20)
	sim.set_connected("General", true)
	var reconnected: Dictionary = sim.snapshot()
	_check(bool(reconnected.connected.General), "terminal %s still reports a restored seat accurately" % expected_status)
	_check(int(reconnected.revision) == before_revision + 2, "terminal reconnect increments the observable revision once")
	_check(str(reconnected.status) == expected_status and reconnected.result == before.result, "connection changes retain the terminal battle result")
	# Connection metadata may change after the result, but the authoritative
	# battlefield and economy must never resume through reconnect.
	before.erase("revision")
	before.erase("connected")
	reconnected.erase("revision")
	reconnected.erase("connected")
	_check(JSON.stringify(before) == JSON.stringify(reconnected), "terminal disconnect/reconnect cannot advance combat, economy, ticks, cooldowns, or reservations")


func _test_far_building_attack_approach() -> void:
	# Reproduce the actual browser failure: a footman walking from home toward
	# the keep center must cross the coarse grid and then enter melee reach.
	# No teleport, range inflation, or reduced footprint is used in this test.
	var assault: Variant = _battle()
	var initial_hp: int = int(assault.buildings.enemy_keep.hp)
	_check(_command(assault, "General", {"action": "order", "units": ["unit_001"], "mode": "attack_move", "x": 19.0, "z": 0.0}), "a home battalion accepts an attack move toward the enemy keep center")
	var clear: bool = true
	var damaged: bool = false
	for _index in range(700):
		_steps(assault, 1, true)
		var unit: Dictionary = assault.units.unit_001
		var point: Vector2 = Vector2(unit.x, unit.z)
		for building: Dictionary in assault.buildings.values():
			if building.hp > 0 and point.distance_to(Vector2(building.x, building.z)) < float(building.radius) + Battle.BODY_RADIUS - 0.01:
				clear = false
		if assault.buildings.enemy_keep.hp < initial_hp:
			damaged = true
	_check(clear, "the full formation stays outside building meshes while approaching melee range")
	_check(damaged, "a far-start battalion actually reaches and damages the keep instead of stopping at an out-of-range grid cell")
	_steps(assault, 1000, true)
	_check(str(assault.status) == "victory", "continuous melee approach permits sustained combat to destroy a full-health enemy keep")
	var defense: Variant = _battle()
	defense.units.clear()
	var home_hp: int = int(defense.buildings.ally_keep.hp)
	_steps(defense, 1500)
	_check(int(defense.buildings.ally_keep.hp) < home_hp, "a normally spawned enemy raid also reaches and damages the protected main keep")


func _test_visual_navigation_clearance() -> void:
	# Measure real exported geometry, including the sawmill's projecting logs and
	# barracks' weapon rack. Mesh decoration must fit inside authority footprints.
	for kind in ["keep", "enemy_keep", "barracks", "tower", "sawmill", "outpost"]:
		var building: Node3D = Art.building(kind, "ally")
		_check(_mesh_radius(building) <= float(Rules.data().buildings[kind].radius), "%s artwork fits inside its authoritative footprint" % kind)
		building.free()
	# The client currently renders four roots at +/-0.575 in both horizontal
	# axes. Enclose animated equipment as well as their formation offsets.
	var formation_corner: float = Vector2(0.575, 0.575).length()
	for kind in ["footmen", "archers", "raider"]:
		var soldier: Node3D = Art.unit(kind, "ally")
		var animated_radius: float = 0.0
		for state in ["idle", "walk", "attack", "hit"]:
			for phase in range(40):
				Art.animate_unit(soldier, state, phase * 0.17, false)
				animated_radius = maxf(animated_radius, _mesh_radius(soldier))
		_check(animated_radius + formation_corner <= Battle.BODY_RADIUS, "%s battalion clearance encloses its animated four-soldier formation" % kind)
		soldier.free()
	var worker: Node3D = Art.worker()
	var worker_radius: float = 0.0
	for state in ["idle", "walk", "attack"]:
		for phase in range(40):
			Art.animate_unit(worker, state, phase * 0.17, false)
			worker_radius = maxf(worker_radius, _mesh_radius(worker))
	_check(worker_radius <= Battle.WORKER_BODY_RADIUS, "individual worker clearance encloses its animated model without requiring battalion clearance")
	worker.free()


func _mesh_radius(node: Node3D, parent_transform: Transform3D = Transform3D.IDENTITY) -> float:
	var world: Transform3D = parent_transform * node.transform
	var maximum: float = 0.0
	if node is MeshInstance3D and node.mesh:
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			for vertex in arrays[Mesh.ARRAY_VERTEX]:
				var point: Vector3 = world * vertex
				maximum = maxf(maximum, Vector2(point.x, point.z).length())
	for child in node.get_children():
		if child is Node3D:
			maximum = maxf(maximum, _mesh_radius(child, world))
	return maximum
