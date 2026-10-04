extends RefCounted

## The server alone advances this deterministic state at 20 Hz. No physics engine
## affects rules, resource accounting, combat, or navigation.
const Rules = preload("res://scripts/shared/rules.gd")
const CELL := 2.0
# Four animated miniatures at the client's +/-0.575 formation offsets reach
# 1.401 world units from the root. This conservative disk encloses the complete
# battalion, rather than allowing the outer soldiers through building meshes.
const BODY_RADIUS := 1.45
const WORKER_BODY_RADIUS := 0.65
const GROUP_GOAL_SPACING := 2.0
const NEIGHBORS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1), Vector2i(1, -1)]

var connected: Dictionary = {"Builder": false, "General": false}
var readiness: Dictionary = {"Builder": false, "General": false}
var seed: int = 7
var tick: int = 0
var revision: int = 0
var status: String = "waiting"
var result: String = ""
var gold: int = 0
var spent: int = 0
var gathered: int = 0
var reservations: Dictionary = {}
var buildings: Dictionary = {}
var units: Dictionary = {}
var workers: Dictionary = {}
var territories: Dictionary = {}
var abilities: Dictionary = {"Builder": [0, 0], "General": [0, 0]}
var deposit: Dictionary = {"x": -21.0, "z": 9.0, "remaining": 450}
var _next_building: int = 1
var _next_unit: int = 1
var _started: bool = false
var _navigation_revision: int = 0
var _tuning: Dictionary = {}

func initialize(new_seed: int = 7) -> void:
	seed = new_seed
	tick = 0
	revision = 0
	status = "waiting"
	result = ""
	connected = {"Builder": false, "General": false}
	readiness = {"Builder": false, "General": false}
	_tuning = Rules.data()
	gold = int(_tuning.starting_gold)
	spent = 0
	gathered = 0
	reservations = {}
	buildings = {}
	units = {}
	workers = {}
	territories = {}
	abilities = {"Builder": [0, 0], "General": [0, 0]}
	_next_building = 1
	_next_unit = 1
	_started = false
	_navigation_revision = 0
	for territory in Rules.TERRITORIES:
		territories[territory.id] = territory.duplicate(true)
	deposit = {"x": -21.0, "z": 9.0, "remaining": int(_tuning.deposit_remaining)}
	territories[0].remaining = deposit.remaining
	_add_building("ally_keep", "keep", "ally", Vector2(-19, 0), -1, true)
	_add_building("ally_barracks", "barracks", "ally", Vector2(-16, -7), -1, true)
	_add_building("enemy_keep", "enemy_keep", "enemy", Vector2(19, 0), -1, true)
	_add_unit("footmen", "ally", Vector2(-13, 3))
	for i in range(2):
		var id := "worker_%03d" % (i + 1)
		workers[id] = {"id": id, "x": -21.0 - i * 2.0, "z": 4.0, "carry": 0, "state": "to_deposit", "gather_cd": 0, "body_radius": WORKER_BODY_RADIUS, "path": [], "nav_revision": -1, "path_goal": []}

func reserved_gold() -> int:
	var total := 0
	for role in Rules.ROLES:
		if reservations.has(role):
			total += int(reservations[role].cost)
	return total

func available_gold() -> int:
	return gold - reserved_gold()

func set_connected(role: String, value: bool) -> void:
	if not Rules.ROLES.has(role) or connected[role] == value:
		return
	connected[role] = value
	_refresh_status()
	revision += 1

func command(role: String, payload: Dictionary) -> Dictionary:
	if not Rules.ROLES.has(role):
		return _reject("unknown_role")
	if status == "victory" or status == "defeat":
		return _reject("battle_finished")
	var action := str(payload.get("action", ""))
	if action == "ready":
		if not payload.get("value") is bool:
			return _reject("invalid_readiness")
		readiness[role] = payload.value
		_refresh_status()
		return _accept("readiness_updated")
	_refresh_status()
	if status != "playing":
		return _reject("battle_not_playing")
	match action:
		"reserve":
			return _reserve(role, payload)
		"confirm":
			return _confirm(role)
		"cancel":
			if not reservations.has(role):
				return _reject("no_reservation")
			reservations.erase(role)
			return _accept("reservation_cancelled")
		"order":
			return _order(role, payload)
		"ability":
			return _ability(role, payload)
	return _reject("unknown_action")

func _reserve(role: String, payload: Dictionary) -> Dictionary:
	if reservations.has(role):
		return _reject("reservation_exists")
	var kind := str(payload.get("kind", ""))
	var reservation: Dictionary = {"kind": kind}
	if role == "Builder":
		if not ["barracks", "tower", "sawmill", "outpost"].has(kind):
			return _reject("role_cannot_purchase")
		if not _integer_number(payload.get("socket")):
			return _reject("invalid_socket")
		var socket := Rules.socket_by_id(int(payload.socket))
		var failure := _socket_failure(socket)
		if not failure.is_empty():
			return _reject(failure)
		reservation.socket = socket.id
		reservation.cost = int(_tuning.buildings[kind].cost)
	else:
		if not ["footmen", "archers"].has(kind):
			return _reject("role_cannot_purchase")
		var building_id := str(payload.get("building", ""))
		if not _valid_barracks(building_id):
			return _reject("ready_barracks_required")
		reservation.building = building_id
		reservation.cost = int(_tuning.units[kind].cost)
	if int(reservation.cost) > available_gold():
		return _reject("insufficient_available_gold")
	reservations[role] = reservation
	return _accept("purchase_reserved")

func _confirm(role: String) -> Dictionary:
	if not reservations.has(role):
		return _reject("no_reservation")
	var purchase: Dictionary = reservations[role]
	if gold < int(purchase.cost) or gold < reserved_gold():
		return _reject("insufficient_gold")
	if role == "Builder":
		var socket := Rules.socket_by_id(int(purchase.socket))
		var failure := _socket_failure(socket, role)
		if not failure.is_empty():
			return _reject(failure)
		var id := "building_%03d" % _next_building
		_next_building += 1
		_add_building(id, purchase.kind, "ally", Vector2(socket.x, socket.z), socket.id, false)
	else:
		if not _valid_barracks(purchase.building):
			return _reject("ready_barracks_required")
		var barracks: Dictionary = buildings[purchase.building]
		var position := _nearest_walkable(Vector2(barracks.x + 4.0, barracks.z))
		var unit := _add_unit(purchase.kind, "ally", position)
		unit.train_ticks = int(_tuning.units[purchase.kind].train_ticks)
		unit.state = "training"
	gold -= int(purchase.cost)
	spent += int(purchase.cost)
	reservations.erase(role)
	return _accept("purchase_confirmed")

func _socket_failure(socket: Dictionary, own_role: String = "") -> String:
	if socket.is_empty():
		return "unknown_socket"
	if not territories[socket.territory].secured:
		# Capture policy is intentionally not invented: Brass Tactics research and
		# owner approval must define how these territories become secured.
		return "territory_capture_pending"
	for id in _sorted_keys(buildings):
		var building: Dictionary = buildings[id]
		if building.hp > 0 and int(building.socket) == int(socket.id):
			return "socket_occupied"
	for role in Rules.ROLES:
		if role != own_role and reservations.has(role) and reservations[role].get("socket", -1) == socket.id:
			return "socket_reserved"
	return ""

func _valid_barracks(id: String) -> bool:
	return buildings.has(id) and buildings[id].team == "ally" and buildings[id].kind == "barracks" and buildings[id].ready and buildings[id].hp > 0

func _order(role: String, payload: Dictionary) -> Dictionary:
	if role != "General":
		return _reject("general_required")
	var selected := _selected_units(payload)
	if selected.is_empty():
		return _reject("invalid_units")
	var mode := str(payload.get("mode", ""))
	if not ["move", "attack_move", "stop"].has(mode):
		return _reject("invalid_order")
	var goal := Vector2.ZERO
	if mode != "stop":
		if not _valid_point(payload):
			return _reject("invalid_position")
		goal = Vector2(float(payload.x), float(payload.z))
	var destinations: Array[Vector2] = []
	if mode != "stop":
		for i in range(selected.size()):
			var offset := Vector2((i % 3 - 1) * GROUP_GOAL_SPACING, int(i / 3) * GROUP_GOAL_SPACING) if selected.size() > 1 else Vector2.ZERO
			if selected.size() == 1:
				destinations.append(_nearest_walkable(goal))
			else:
				var unit: Dictionary = units[selected[i]]
				var planned := _group_destination(goal + offset, Vector2(unit.x, unit.z), destinations)
				if planned.is_empty():
					return _reject("group_destination_unreachable")
				destinations.append(planned.point)
	for i in range(selected.size()):
		var unit: Dictionary = units[selected[i]]
		unit.order = mode
		unit.path = []
		unit.nav_revision = -1
		if mode == "stop":
			unit.goal = [unit.x, unit.z]
			unit.state = "idle"
		else:
			# One authoritative root per four-soldier battalion. Multiple selected
			# roots retain separate reachable endpoints even when a footprint or
			# map edge projects their requested offsets onto the same grid cell.
			var destination: Vector2 = destinations[i]
			unit.goal = [destination.x, destination.y]
			unit.state = "walk"
	return _accept("order_accepted")

func _group_destination(requested: Vector2, start: Vector2, assigned: Array[Vector2]) -> Dictionary:
	var preferred := _nearest_walkable(requested)
	if _goal_separated(preferred, assigned) and not _find_path(start, preferred).is_empty():
		return {"point": preferred}
	# This allocates order endpoints only; it does not add inter-unit collision.
	# Consider nearby existing navigation cells in an explicit deterministic
	# distance/x/z order, accepting only a clear and reachable alternative.
	var candidates: Array[Vector2] = []
	for x in range(-13, 14):
		for z in range(-9, 10):
			var cell := Vector2i(x, z)
			var point := _cell_world(cell)
			if _cell_walkable(cell) and _goal_separated(point, assigned):
				candidates.append(point)
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var distance_a := a.distance_squared_to(requested)
		var distance_b := b.distance_squared_to(requested)
		if distance_a != distance_b:
			return distance_a < distance_b
		return a.y < b.y if a.x == b.x else a.x < b.x
	)
	for candidate in candidates:
		if not _find_path(start, candidate).is_empty():
			return {"point": candidate}
	return {}

func _goal_separated(point: Vector2, assigned: Array[Vector2]) -> bool:
	for other in assigned:
		if point.distance_squared_to(other) < GROUP_GOAL_SPACING * GROUP_GOAL_SPACING - 0.00001:
			return false
	return true

func _selected_units(payload: Dictionary) -> Array:
	if not payload.get("units") is Array or payload.units.is_empty():
		return []
	var selected: Array = []
	for value in payload.units:
		var id := str(value)
		if not units.has(id) or units[id].team != "ally" or units[id].hp <= 0 or units[id].train_ticks > 0 or selected.has(id):
			return []
		selected.append(id)
	selected.sort()
	return selected

func _ability(role: String, payload: Dictionary) -> Dictionary:
	if not _integer_number(payload.get("slot")) or int(payload.slot) < 0 or int(payload.slot) > 1:
		return _reject("invalid_ability")
	var slot := int(payload.slot)
	if abilities[role][slot] > 0:
		return _reject("ability_on_cooldown")
	if role == "General":
		var selected := _selected_units(payload)
		if selected.is_empty():
			return _reject("invalid_units")
		var config: Dictionary = _tuning.abilities.forced_march if slot == 0 else _tuning.abilities.shield_wall
		for id in selected:
			units[id]["march_ticks" if slot == 0 else "shield_ticks"] = int(config.duration_ticks)
		abilities[role][slot] = int(config.cooldown_ticks)
	else:
		var id := str(payload.get("building", ""))
		if not buildings.has(id) or buildings[id].team != "ally" or buildings[id].hp <= 0 or not buildings[id].ready:
			return _reject("ready_allied_building_required")
		var building: Dictionary = buildings[id]
		if slot == 0:
			var config: Dictionary = _tuning.abilities.mending
			if Vector2(building.x + 19.0, building.z).length() > float(config.building_radius):
				return _reject("outside_mending_radius")
			building.hp = mini(int(building.max_hp), int(building.hp) + int(config.heal))
			for unit_id in _sorted_keys(units):
				var unit: Dictionary = units[unit_id]
				if unit.team == "ally" and unit.hp > 0 and _distance(unit, building) <= float(config.unit_radius):
					unit.hp = mini(int(unit.max_hp), int(unit.hp) + int(config.heal))
			abilities[role][slot] = int(config.cooldown_ticks)
		else:
			if building.kind != "tower":
				return _reject("tower_required")
			var config: Dictionary = _tuning.abilities.tower_overcharge
			building.overcharge_ticks = int(config.duration_ticks)
			abilities[role][slot] = int(config.cooldown_ticks)
	return _accept("ability_activated")

func step() -> void:
	if status == "victory" or status == "defeat":
		return
	_refresh_status()
	if status != "playing":
		return
	if _check_outcome():
		return
	tick += 1
	revision += 1
	for role in Rules.ROLES:
		for slot in range(2):
			abilities[role][slot] = maxi(0, int(abilities[role][slot]) - 1)
	_step_buildings()
	_step_workers()
	_spawn_raid()
	_step_units()
	if _check_outcome():
		return
	_step_towers()
	if _check_outcome():
		return
	if tick >= int(_tuning.trial_limit_ticks):
		status = "defeat"
		result = "trial_time_limit"

func _refresh_status() -> void:
	if status == "victory" or status == "defeat":
		return
	var both_ready: bool = connected.Builder and connected.General and readiness.Builder and readiness.General
	if both_ready:
		_started = true
		status = "playing"
	else:
		status = "paused" if _started else "waiting"

func _check_outcome() -> bool:
	if buildings.ally_keep.hp <= 0:
		status = "defeat"
		result = "main_keep_destroyed"
		return true
	if buildings.enemy_keep.hp <= 0:
		status = "victory"
		result = "enemy_keep_destroyed"
		return true
	return false

func _step_buildings() -> void:
	for id in _sorted_keys(buildings):
		var building: Dictionary = buildings[id]
		if building.hp <= 0:
			continue
		if not building.ready:
			building.build_ticks = maxi(0, int(building.build_ticks) - 1)
			building.progress = 1.0 - float(building.build_ticks) / maxf(1.0, float(building.total_build_ticks))
			building.ready = building.build_ticks == 0
		if building.attack_cd > 0:
			building.attack_cd -= 1
		if building.overcharge_ticks > 0:
			building.overcharge_ticks -= 1
			if building.overcharge_ticks == 0:
				building.shutdown_ticks = int(_tuning.abilities.tower_overcharge.shutdown_ticks)
		elif building.shutdown_ticks > 0:
			building.shutdown_ticks -= 1

func _step_workers() -> void:
	if not territories[0].secured:
		return
	for id in _sorted_keys(workers):
		var worker: Dictionary = workers[id]
		if worker.state == "idle":
			continue
		if worker.state == "to_deposit":
			if deposit.remaining <= 0:
				worker.state = "to_keep" if worker.carry > 0 else "idle"
			elif _move_entity(worker, Vector2(deposit.x, deposit.z), float(_tuning.worker_speed)):
				worker.state = "gather"
				worker.gather_cd = int(_tuning.worker_gather_ticks)
		elif worker.state == "gather":
			worker.gather_cd -= 1
			if worker.gather_cd <= 0:
				var amount := int(_tuning.worker_gather_amount)
				var gather_ticks := int(_tuning.worker_gather_ticks)
				for building_id in _sorted_keys(buildings):
					var building: Dictionary = buildings[building_id]
					if building.kind == "sawmill" and building.ready and building.hp > 0 and _distance(building, deposit) <= float(_tuning.buildings.sawmill.deposit_range):
						amount += int(_tuning.buildings.sawmill.gather_bonus)
						gather_ticks = int(round(gather_ticks * float(_tuning.buildings.sawmill.gather_interval_multiplier)))
						break
				amount = mini(amount, mini(int(deposit.remaining), int(_tuning.worker_capacity) - int(worker.carry)))
				worker.carry += amount
				deposit.remaining -= amount
				territories[0].remaining = deposit.remaining
				worker.gather_cd = gather_ticks
				if worker.carry >= int(_tuning.worker_capacity) or deposit.remaining <= 0:
					worker.state = "to_keep"
		elif worker.state == "to_keep":
			# Delivery is a physical trip to a walkable point outside the keep.
			if _move_entity(worker, Vector2(-19.0, 4.0), float(_tuning.worker_speed)):
				gold += int(worker.carry)
				gathered += int(worker.carry)
				worker.carry = 0
				worker.state = "to_deposit" if deposit.remaining > 0 else "idle"

func _spawn_raid() -> void:
	var first := int(_tuning.first_raid_tick)
	if tick < first or (tick - first) % int(_tuning.raid_interval_ticks) != 0:
		return
	var wave := int((tick - first) / int(_tuning.raid_interval_ticks))
	for i in range(mini(4, 1 + wave)):
		var side := -1.0 if (absi(seed) + wave) % 2 == 0 else 1.0
		var position := Vector2(15.0, side * (11.0 - i * 3.0))
		var unit := _add_unit("raider", "enemy", position)
		unit.order = "attack_move"
		unit.goal = [-19.0, 0.0]

func _step_units() -> void:
	for id in _sorted_keys(units):
		var unit: Dictionary = units[id]
		if unit.hp <= 0:
			unit.state = "dead"
			continue
		if unit.train_ticks > 0:
			unit.train_ticks -= 1
			unit.state = "training" if unit.train_ticks > 0 else "idle"
			continue
		unit.attack_cd = maxi(0, int(unit.attack_cd) - 1)
		unit.march_ticks = maxi(0, int(unit.march_ticks) - 1)
		unit.shield_ticks = maxi(0, int(unit.shield_ticks) - 1)
		unit.hit_ticks = maxi(0, int(unit.hit_ticks) - 1)
		var target: Dictionary = {}
		if unit.march_ticks == 0 and unit.order != "move":
			target = _find_target(unit, float(unit.range) + (7.0 if unit.order == "attack_move" else 0.0))
		if not target.is_empty():
			var reach: float = float(unit.range) + float(target.get("radius", 0.0))
			if _distance(unit, target) <= reach:
				unit.state = "attack"
				if unit.attack_cd == 0:
					_damage(target, int(unit.damage))
					unit.attack_cd = int(unit.attack_interval)
					if status == "victory" or status == "defeat":
						return
			else:
				_move_entity(unit, _attack_approach(unit, target), _unit_speed(unit))
				unit.state = "walk"
		elif unit.order == "move" or unit.order == "attack_move":
			var arrived := _move_entity(unit, Vector2(unit.goal[0], unit.goal[1]), _unit_speed(unit))
			unit.state = "idle" if arrived else "walk"
			if arrived and unit.order == "move":
				unit.order = "stop"
		else:
			unit.state = "idle"
		if unit.hit_ticks > 0 and unit.state == "idle":
			unit.state = "hit"

func _unit_speed(unit: Dictionary) -> float:
	var speed := float(unit.speed)
	if unit.march_ticks > 0:
		speed *= float(_tuning.abilities.forced_march.speed_multiplier)
	if unit.shield_ticks > 0:
		speed *= float(_tuning.abilities.shield_wall.speed_multiplier)
	return speed

func _attack_approach(unit: Dictionary, target: Dictionary) -> Vector2:
	var center := Vector2(target.x, target.z)
	if not target.has("radius"):
		return center
	# The grid routes around footprints, but a melee attack endpoint must be
	# continuous: the nearest 2-unit cell can sit outside the attacker's reach.
	# Approach the disk from the current side with a small clearance margin.
	var direction := Vector2(unit.x, unit.z) - center
	if direction.length_squared() < 0.00001:
		direction = Vector2.LEFT
	else:
		direction = direction.normalized()
	var clearance := float(target.radius) + BODY_RADIUS + 0.05
	var best := Vector2.ZERO
	var best_distance := INF
	for index in range(32):
		var angle := index * TAU / 32.0
		var candidate := center + direction.rotated(angle) * clearance
		if not _point_walkable(candidate):
			continue
		var distance := candidate.distance_squared_to(Vector2(unit.x, unit.z))
		if distance < best_distance:
			best_distance = distance
			best = candidate
	if best_distance < INF:
		return best
	return _nearest_walkable(center)

func _step_towers() -> void:
	for id in _sorted_keys(buildings):
		var tower: Dictionary = buildings[id]
		if tower.kind != "tower" or not tower.ready or tower.hp <= 0 or tower.shutdown_ticks > 0 or tower.attack_cd > 0:
			continue
		var config: Dictionary = _tuning.buildings.tower
		var target := _find_target(tower, float(config.range), false)
		if target.is_empty():
			continue
		var damage := int(config.damage)
		var interval := int(config.attack_interval)
		if tower.overcharge_ticks > 0:
			damage = int(round(damage * float(_tuning.abilities.tower_overcharge.damage_multiplier)))
			interval = int(round(interval * float(_tuning.abilities.tower_overcharge.interval_multiplier)))
		_damage(target, damage)
		tower.attack_cd = maxi(1, interval)

func _find_target(source: Dictionary, radius: float, include_buildings: bool = true) -> Dictionary:
	var target: Dictionary = {}
	var best := INF
	for id in _sorted_keys(units):
		var candidate: Dictionary = units[id]
		if candidate.team == source.team or candidate.hp <= 0 or candidate.train_ticks > 0:
			continue
		var distance := _distance(source, candidate)
		if distance <= radius and distance < best:
			best = distance
			target = candidate
	if include_buildings:
		for id in _sorted_keys(buildings):
			var candidate: Dictionary = buildings[id]
			if candidate.team == source.team or candidate.hp <= 0:
				continue
			var distance := maxf(0.0, _distance(source, candidate) - float(candidate.radius))
			if distance <= radius and distance < best:
				best = distance
				target = candidate
	return target

func _damage(target: Dictionary, amount: int) -> void:
	if int(target.get("shield_ticks", 0)) > 0:
		amount = maxi(1, int(round(amount * float(_tuning.abilities.shield_wall.damage_multiplier))))
	var was_alive: bool = target.hp > 0
	target.hp = maxi(0, int(target.hp) - amount)
	if target.has("hit_ticks"):
		target.hit_ticks = 4
	if was_alive and target.hp == 0 and target.has("radius"):
		_navigation_revision += 1
		if target.id == "ally_keep" or target.id == "enemy_keep":
			_check_outcome()

func _add_building(id: String, kind: String, team: String, position: Vector2, socket: int, ready: bool) -> Dictionary:
	var config: Dictionary = _tuning.buildings[kind]
	var duration := int(config.build_ticks)
	var building := {"id": id, "kind": kind, "team": team, "x": position.x, "z": position.y, "hp": int(config.hp), "max_hp": int(config.hp), "radius": float(config.radius), "socket": socket, "progress": 1.0 if ready else 0.0, "ready": ready, "build_ticks": 0 if ready else duration, "total_build_ticks": duration, "attack_cd": 0, "overcharge_ticks": 0, "shutdown_ticks": 0}
	buildings[id] = building
	_navigation_revision += 1
	# A new footprint displaces roots safely before any following simulation tick.
	for collection in [units, workers]:
		for entity_id in _sorted_keys(collection):
			var entity: Dictionary = collection[entity_id]
			var point := Vector2(entity.x, entity.z)
			var body_radius := float(entity.get("body_radius", BODY_RADIUS))
			if not _point_walkable(point, body_radius):
				point = _nearest_walkable(point, body_radius)
				entity.x = point.x
				entity.z = point.y
				entity.path = []
	return building

func _add_unit(kind: String, team: String, position: Vector2) -> Dictionary:
	var config: Dictionary = _tuning.units[kind]
	var id := "unit_%03d" % _next_unit
	_next_unit += 1
	position = _nearest_walkable(position)
	var unit := {"id": id, "kind": kind, "team": team, "x": position.x, "z": position.y, "hp": int(config.hp), "max_hp": int(config.hp), "count": 4, "state": "idle", "goal": [position.x, position.y], "order": "stop", "speed": float(config.speed), "range": float(config.range), "damage": int(config.damage), "attack_interval": int(config.attack_interval), "attack_cd": 0, "train_ticks": 0, "march_ticks": 0, "shield_ticks": 0, "hit_ticks": 0, "path": [], "nav_revision": -1, "path_goal": []}
	units[id] = unit
	return unit

func _move_entity(entity: Dictionary, requested_goal: Vector2, speed: float) -> bool:
	var position := Vector2(entity.x, entity.z)
	var body_radius := float(entity.get("body_radius", BODY_RADIUS))
	var goal := requested_goal if _point_walkable(requested_goal, body_radius) else _nearest_walkable(requested_goal, body_radius)
	if position.distance_to(goal) <= 0.12:
		entity.x = goal.x
		entity.z = goal.y
		return true
	var goal_changed: bool = entity.path_goal.size() != 2 or Vector2(entity.path_goal[0], entity.path_goal[1]).distance_to(goal) > 1.0
	if entity.path.is_empty() or entity.nav_revision != _navigation_revision or goal_changed:
		entity.path = _find_path(position, goal, body_radius)
		entity.path_goal = [goal.x, goal.y]
		entity.nav_revision = _navigation_revision
	if entity.path.is_empty():
		return false
	var next: Vector2 = entity.path[0]
	var distance := speed / float(Rules.TICK_RATE)
	var moved := position.move_toward(next, distance)
	if not _segment_clear(position, moved, body_radius):
		entity.path = []
		return false
	entity.x = moved.x
	entity.z = moved.y
	if moved.distance_to(next) < 0.01:
		entity.path.pop_front()
	return moved.distance_to(goal) <= 0.12

func _find_path(start: Vector2, goal: Vector2, body_radius: float = BODY_RADIUS) -> Array:
	if _segment_clear(start, goal, body_radius):
		return [goal]
	var start_cell := _nearest_cell(start, body_radius)
	var goal_cell := _nearest_cell(goal, body_radius)
	var frontier: Array[Vector2i] = [start_cell]
	var came: Dictionary = {start_cell: start_cell}
	var head := 0
	while head < frontier.size():
		var cell: Vector2i = frontier[head]
		head += 1
		if cell == goal_cell:
			break
		for offset in NEIGHBORS:
			var candidate: Vector2i = cell + offset
			if came.has(candidate) or not _cell_walkable(candidate, body_radius) or not _segment_clear(_cell_world(cell), _cell_world(candidate), body_radius):
				continue
			came[candidate] = cell
			frontier.append(candidate)
	if not came.has(goal_cell):
		return []
	var reverse: Array = []
	var cursor := goal_cell
	while cursor != start_cell:
		reverse.append(_cell_world(cursor))
		cursor = came[cursor]
	reverse.reverse()
	var path: Array = []
	# Connect off-grid endpoints only through clear segments, including the
	# nearest start cell when its first successor cannot be reached directly.
	if reverse.is_empty() or not _segment_clear(start, reverse[0], body_radius):
		if not _segment_clear(start, _cell_world(start_cell), body_radius):
			return []
		path.append(_cell_world(start_cell))
	path.append_array(reverse)
	if path.is_empty() or _segment_clear(path[-1], goal, body_radius):
		path.append(goal)
	return path

func _nearest_cell(point: Vector2, body_radius: float = BODY_RADIUS) -> Vector2i:
	var origin := Vector2i(roundi(point.x / CELL), roundi(point.y / CELL))
	if _cell_walkable(origin, body_radius):
		return origin
	var best := Vector2i.ZERO
	var distance := INF
	for x in range(-13, 14):
		for z in range(-9, 10):
			var candidate := Vector2i(x, z)
			if not _cell_walkable(candidate, body_radius):
				continue
			var current := _cell_world(candidate).distance_squared_to(point)
			if current < distance:
				distance = current
				best = candidate
	return best

func _nearest_walkable(point: Vector2, body_radius: float = BODY_RADIUS) -> Vector2:
	point.x = clampf(point.x, Rules.MAP_BOUNDS.min_x, Rules.MAP_BOUNDS.max_x)
	point.y = clampf(point.y, Rules.MAP_BOUNDS.min_z, Rules.MAP_BOUNDS.max_z)
	if _point_walkable(point, body_radius):
		return point
	return _cell_world(_nearest_cell(point, body_radius))

func _cell_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * CELL, cell.y * CELL)

func _cell_walkable(cell: Vector2i, body_radius: float = BODY_RADIUS) -> bool:
	return cell.x >= -13 and cell.x <= 13 and cell.y >= -9 and cell.y <= 9 and _point_walkable(_cell_world(cell), body_radius)

func _point_walkable(point: Vector2, body_radius: float = BODY_RADIUS) -> bool:
	if point.x < Rules.MAP_BOUNDS.min_x or point.x > Rules.MAP_BOUNDS.max_x or point.y < Rules.MAP_BOUNDS.min_z or point.y > Rules.MAP_BOUNDS.max_z:
		return false
	for id in _sorted_keys(buildings):
		var building: Dictionary = buildings[id]
		if building.hp > 0 and point.distance_to(Vector2(building.x, building.z)) < float(building.radius) + body_radius:
			return false
	return true

func _segment_clear(start: Vector2, end: Vector2, body_radius: float = BODY_RADIUS) -> bool:
	if not _point_walkable(start, body_radius) or not _point_walkable(end, body_radius):
		return false
	var delta := end - start
	var length_squared := delta.length_squared()
	for id in _sorted_keys(buildings):
		var building: Dictionary = buildings[id]
		if building.hp <= 0:
			continue
		var center := Vector2(building.x, building.z)
		var t := clampf((center - start).dot(delta) / length_squared, 0.0, 1.0) if length_squared > 0.00001 else 0.0
		if center.distance_to(start + delta * t) < float(building.radius) + body_radius:
			return false
	return true

func _valid_point(payload: Dictionary) -> bool:
	for key in ["x", "z"]:
		if not payload.get(key) is float and not payload.get(key) is int:
			return false
		if not is_finite(float(payload[key])):
			return false
	return float(payload.x) >= Rules.MAP_BOUNDS.min_x and float(payload.x) <= Rules.MAP_BOUNDS.max_x and float(payload.z) >= Rules.MAP_BOUNDS.min_z and float(payload.z) <= Rules.MAP_BOUNDS.max_z

func _integer_number(value) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value))

func _distance(a: Dictionary, b: Dictionary) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _sorted_keys(collection: Dictionary) -> Array:
	var keys := collection.keys()
	keys.sort()
	return keys

func _accept(message: String) -> Dictionary:
	revision += 1
	return {"ok": true, "result": message, "revision": revision}

func _reject(message: String) -> Dictionary:
	return {"ok": false, "result": message, "revision": revision}

func snapshot() -> Dictionary:
	_refresh_status()
	var building_list: Array = []
	for id in _sorted_keys(buildings):
		building_list.append(buildings[id].duplicate(true))
	var unit_list: Array = []
	for id in _sorted_keys(units):
		var copy: Dictionary = units[id].duplicate(true)
		copy.erase("path")
		copy.erase("nav_revision")
		copy.erase("path_goal")
		unit_list.append(copy)
	var worker_list: Array = []
	for id in _sorted_keys(workers):
		var copy: Dictionary = workers[id].duplicate(true)
		copy.erase("path")
		copy.erase("nav_revision")
		copy.erase("path_goal")
		worker_list.append(copy)
	var territory_list: Array = []
	for id in _sorted_keys(territories):
		territory_list.append(territories[id].duplicate(true))
	return {"build_id": Rules.BUILD_ID, "protocol": Rules.PROTOCOL, "seed": seed, "tick": tick, "elapsed_ticks": tick, "revision": revision, "status": status, "gold": gold, "available_gold": available_gold(), "reserved_gold": reserved_gold(), "spent": spent, "gathered": gathered, "reservations": reservations.duplicate(true), "sockets": Rules.SOCKETS.duplicate(true), "territories": territory_list, "buildings": building_list, "units": unit_list, "workers": worker_list, "abilities": abilities.duplicate(true), "connected": connected.duplicate(true), "readiness": readiness.duplicate(true), "deposit": deposit.duplicate(true), "trial_limit_ticks": int(_tuning.trial_limit_ticks), "territory_capture": "pending_owner_research", "result": result}
