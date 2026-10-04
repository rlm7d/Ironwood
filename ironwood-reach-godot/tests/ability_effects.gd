extends SceneTree

## Deterministic paired-combat supplement, not browser or human playtest proof.
## godot --headless --path game --script ../tests/ability_effects.gd
## Ordinary commands ready both roles, build a tower and activate abilities.
## Ordinary fixed steps spawn the raid and resolve every measured combat hit.
## Explicit identical position/stop/high-health fixtures isolate those hits and
## keep units alive through effect expiry. No damage helper is called directly.
const Battle = preload("res://scripts/simulation/battle.gd")
const Rules = preload("res://scripts/shared/rules.gd")
const FIXTURE_HP: int = 100000

var checks: int = 0
var failures: Array[String] = []
var measurements: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_shield_damage()
	_test_tower_damage()
	print(JSON.stringify({"kind": "automated_paired_ability_combat_effects", "build_id": Rules.BUILD_ID,
		"checks": checks, "failures": failures.size(), "measurements": measurements,
		"ordinary_command_and_step_paths": true, "direct_damage_calls": false,
		"fixture": "Identically seeded paired battles; first enemy comes from normal timed raid. Explicit positions, stopped enemy order and high unit health isolate combat and survive effect expiry. Tuning and damage statistics remain unchanged.",
		"browser_interaction": false, "human_feedback": false, "balance_tested": false,
		"performance_tested": false, "multiplayer_tested": false}))
	quit(0 if failures.is_empty() else 1)

func _battle(with_tower: bool = false) -> Dictionary:
	var battle: Variant = Battle.new()
	battle.initialize(7)
	battle.set_connected("Builder", true)
	battle.set_connected("General", true)
	var builder: Dictionary = battle.command("Builder", {"action": "ready", "value": true})
	var general: Dictionary = battle.command("General", {"action": "ready", "value": true})
	var tower_id: String = ""
	var purchase_ok: bool = not with_tower
	if with_tower:
		var reservation: Dictionary = battle.command("Builder", {"action": "reserve", "kind": "tower", "socket": 1})
		var purchase: Dictionary = battle.command("Builder", {"action": "confirm"})
		purchase_ok = reservation.get("ok", false) and purchase.get("ok", false)
		for id: String in battle.buildings:
			if battle.buildings[id].kind == "tower": tower_id = id
	var first_raid_tick: int = int(Rules.data().first_raid_tick)
	for _step: int in range(first_raid_tick):
		battle.step()
	var enemy_id: String = ""
	for id: String in battle.units:
		if battle.units[id].team == "enemy": enemy_id = id
	return {"battle": battle, "enemy_id": enemy_id, "tower_id": tower_id,
		"ordinary_setup_ok": builder.get("ok", false) and general.get("ok", false) and purchase_ok,
		"raid_origin_tick": first_raid_tick}

func _position_unit(unit: Dictionary, position: Vector2) -> void:
	unit.x = position.x
	unit.z = position.y
	unit.goal = [position.x, position.y]
	unit.order = "stop"
	unit.path = []
	unit.hp = FIXTURE_HP
	unit.max_hp = FIXTURE_HP

func _hits(battle: Variant, target: Dictionary, ticks: int, tower_id: String = "") -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var start_tick: int = int(battle.tick)
	for _step: int in range(ticks):
		var previous_hp: int = int(target.hp)
		battle.step()
		var damage: int = previous_hp - int(target.hp)
		if damage > 0:
			var hit: Dictionary = {"tick": int(battle.tick), "relative_tick": int(battle.tick) - start_tick,
				"damage": damage, "shield_ticks": int(target.get("shield_ticks", 0))}
			if not tower_id.is_empty():
				hit.overcharge_ticks = int(battle.buildings[tower_id].overcharge_ticks)
				hit.shutdown_ticks = int(battle.buildings[tower_id].shutdown_ticks)
			hits.append(hit)
	return hits

func _test_shield_damage() -> void:
	var normal: Dictionary = _battle()
	var shielded: Dictionary = _battle()
	var fixture_ok: bool = normal.ordinary_setup_ok and shielded.ordinary_setup_ok and not normal.enemy_id.is_empty() and not shielded.enemy_id.is_empty()
	_check(fixture_ok, "paired shield battles use ordinary readiness and the real first timed raid")
	if not fixture_ok: return
	for scenario: Dictionary in [normal, shielded]:
		_position_unit(scenario.battle.units.unit_001, Vector2(-8, 8))
		_position_unit(scenario.battle.units[scenario.enemy_id], Vector2(-7, 8))
	var activation: Dictionary = shielded.battle.command("General", {"action": "ability", "slot": 1, "units": ["unit_001"]})
	_check(activation.get("ok", false) and int(normal.battle.units.unit_001.shield_ticks) == 0,
		"ordinary General ability command activates shielding in exactly one paired battle")
	var duration: int = int(shielded.battle.units.unit_001.shield_ticks)
	var horizon: int = duration + 80
	var normal_hits: Array[Dictionary] = _hits(normal.battle, normal.battle.units.unit_001, horizon)
	var shield_hits: Array[Dictionary] = _hits(shielded.battle, shielded.battle.units.unit_001, horizon)
	_check(not normal_hits.is_empty() and not shield_hits.is_empty(), "normal step combat produces incoming hits in both shield comparison battles")
	if normal_hits.is_empty() or shield_hits.is_empty(): return
	_check(int(shield_hits[0].shield_ticks) > 0 and int(shield_hits[0].damage) > 0 and int(shield_hits[0].damage) < int(normal_hits[0].damage),
		"the first real incoming hit deals less damage while Shield wall is active")
	var expired_hit: Dictionary = {}
	for hit: Dictionary in shield_hits:
		if int(hit.shield_ticks) == 0:
			expired_hit = hit
			break
	_check(not expired_hit.is_empty(), "continued normal step combat produces a hit after Shield wall expires")
	if expired_hit.is_empty(): return
	var paired_expired_hit: Dictionary = {}
	for hit: Dictionary in normal_hits:
		if hit.relative_tick == expired_hit.relative_tick:
			paired_expired_hit = hit
			break
	_check(not paired_expired_hit.is_empty() and expired_hit.damage == paired_expired_hit.damage and expired_hit.damage == normal_hits[0].damage,
		"after shielding expires, an incoming hit returns to the paired unshielded damage")
	_check(normal.battle.status == "playing" and shielded.battle.status == "playing" and normal.battle.units.unit_001.hp > 0 and shielded.battle.units.unit_001.hp > 0,
		"paired shield measurements finish with both targets alive and both battles still playing")
	measurements.shield = {"raid_origin_tick": normal.raid_origin_tick, "observed_duration_ticks": duration,
		"horizon_ticks": horizon, "normal_first_hit": normal_hits[0], "shielded_first_hit": shield_hits[0],
		"expired_shield_hit": expired_hit, "paired_normal_expiry_hit": paired_expired_hit,
		"normal_hits": normal_hits, "shielded_hits": shield_hits}

func _test_tower_damage() -> void:
	var normal: Dictionary = _battle(true)
	var charged: Dictionary = _battle(true)
	var fixture_ok: bool = normal.ordinary_setup_ok and charged.ordinary_setup_ok and not normal.enemy_id.is_empty() and not charged.enemy_id.is_empty() and not normal.tower_id.is_empty() and not charged.tower_id.is_empty()
	_check(fixture_ok, "paired towers are purchased normally and measured against the real first timed raid")
	if not fixture_ok: return
	_check(normal.battle.buildings[normal.tower_id].ready and charged.battle.buildings[charged.tower_id].ready,
		"both purchased towers finish construction through ordinary fixed steps before combat")
	for scenario: Dictionary in [normal, charged]:
		# Four world units from the fixed tower socket is inside tower range but
		# outside the stopped raider's melee reach; no allied unit can hit it.
		_position_unit(scenario.battle.units[scenario.enemy_id], Vector2(-6, 0))
	var activation: Dictionary = charged.battle.command("Builder", {"action": "ability", "slot": 1, "building": charged.tower_id})
	_check(activation.get("ok", false) and int(normal.battle.buildings[normal.tower_id].overcharge_ticks) == 0,
		"ordinary Builder command overcharges exactly one ready paired tower")
	var duration: int = int(charged.battle.buildings[charged.tower_id].overcharge_ticks)
	var horizon: int = duration + int(Rules.data().abilities.tower_overcharge.shutdown_ticks) + 50
	var normal_hits: Array[Dictionary] = _hits(normal.battle, normal.battle.units[normal.enemy_id], horizon, normal.tower_id)
	var charged_hits: Array[Dictionary] = []
	var start_tick: int = int(charged.battle.tick)
	var shutdown_frames: int = 0
	var shutdown_damage: int = 0
	var observed_shutdown_start: int = -1
	var observed_shutdown_end: int = -1
	for _step: int in range(horizon):
		var target: Dictionary = charged.battle.units[charged.enemy_id]
		var previous_hp: int = int(target.hp)
		charged.battle.step()
		var tower: Dictionary = charged.battle.buildings[charged.tower_id]
		var damage: int = previous_hp - int(target.hp)
		var relative_tick: int = int(charged.battle.tick) - start_tick
		if tower.shutdown_ticks > 0:
			shutdown_frames += 1
			shutdown_damage += damage
			if observed_shutdown_start < 0: observed_shutdown_start = relative_tick
		elif observed_shutdown_start >= 0 and observed_shutdown_end < 0:
			observed_shutdown_end = relative_tick
		if damage > 0:
			charged_hits.append({"tick": int(charged.battle.tick), "relative_tick": relative_tick,
				"damage": damage, "overcharge_ticks": int(tower.overcharge_ticks), "shutdown_ticks": int(tower.shutdown_ticks)})
	_check(normal_hits.size() >= 2 and charged_hits.size() >= 2, "normal step combat produces repeated tower shots in both paired battles")
	if normal_hits.size() < 2 or charged_hits.size() < 2: return
	_check(charged_hits[0].overcharge_ticks > 0 and charged_hits[0].damage > normal_hits[0].damage,
		"the overcharged tower's first real shot deals more damage than the paired normal tower")
	var normal_interval: int = int(normal_hits[1].relative_tick) - int(normal_hits[0].relative_tick)
	var charged_interval: int = int(charged_hits[1].relative_tick) - int(charged_hits[0].relative_tick)
	_check(charged_interval > 0 and charged_interval < normal_interval,
		"the overcharged tower fires its second real shot sooner than the paired normal tower")
	_check(shutdown_frames > 0 and shutdown_damage == 0 and observed_shutdown_end > observed_shutdown_start,
		"after overcharge expires the entire observed shutdown interval contains no tower damage")
	var resumed_hit: Dictionary = {}
	for hit: Dictionary in charged_hits:
		if int(hit.relative_tick) >= observed_shutdown_end and hit.overcharge_ticks == 0 and hit.shutdown_ticks == 0:
			resumed_hit = hit
			break
	_check(not resumed_hit.is_empty() and resumed_hit.damage == normal_hits[0].damage,
		"after shutdown ends the tower resumes normal-damage shots through ordinary combat steps")
	_check(normal.battle.status == "playing" and charged.battle.status == "playing" and normal.battle.units[normal.enemy_id].hp > 0 and charged.battle.units[charged.enemy_id].hp > 0,
		"paired tower measurements finish with both targets alive and both battles still playing")
	measurements.tower = {"raid_origin_tick": normal.raid_origin_tick, "observed_overcharge_duration_ticks": duration,
		"horizon_ticks": horizon, "normal_first_hit": normal_hits[0], "charged_first_hit": charged_hits[0],
		"normal_first_interval_ticks": normal_interval, "charged_first_interval_ticks": charged_interval,
		"observed_shutdown_start": observed_shutdown_start, "observed_shutdown_end": observed_shutdown_end,
		"shutdown_frames": shutdown_frames, "shutdown_damage": shutdown_damage,
		"first_resumed_hit": resumed_hit, "normal_hits": normal_hits, "charged_hits": charged_hits}

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition: failures.append(description)
	print(JSON.stringify({"check": description, "status": "PASS" if condition else "FAIL"}))
