@tool
class_name FleetBattleSimulator
extends RefCounted

const DEFAULT_SHIP_PART_CATALOG: ShipPartCatalog = preload("res://resources/config/ship_part_catalog_default.tres")
const DEFAULT_BATTLE_CONFIG: BattleConfig = preload("res://resources/config/battle_config_default.tres")

const SPAWN_X_A := -180.0
const SPAWN_X_B := 180.0

## Deterministic, animated, module-based fleet combat.
##
## Every ship is composed of individual modules (hull, drives, weapons,
## shields, scanner, utilities) that each carry their own HP share of the
## ship's pool, derived from the ModuleInfluence model (1 drive = 20 % of the
## pool, 2 drives ≈ 15 % each). Damage is applied to modules weighted by their
## influence; a destroyed module immediately degrades the stat it governs:
##   drive destroyed   → ship becomes immobile (speed 0, both in the
##                       simulation and in the replay visuals)
##   weapon destroyed  → DPS drops
##   scanner destroyed → range drops
##   shield destroyed  → HP pool shrinks
##   hull destroyed    → ship destroyed
## Ships with working drives advance toward the enemy until their weapon range
## reaches the firing line; ships that lose all drives mid-approach become
## sitting ducks and can never close the distance.

static func simulate_battle(fleet_a: FleetSnapshot, fleet_b: FleetSnapshot, battle_seed: int = 1337, catalog: ShipPartCatalog = null, config: BattleConfig = null) -> CombatReplay:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	var cfg: BattleConfig = config if config != null else DEFAULT_BATTLE_CONFIG
	var events: Array[BattleEvent] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = battle_seed

	if fleet_a == null or fleet_a.ships.is_empty():
		var empty_attacker_replay := CombatReplay.new_battle(battle_seed)
		empty_attacker_replay.winner = fleet_b.faction if fleet_b != null else &"neutral"
		if fleet_b != null:
			empty_attacker_replay.survivors_b = _copy_assemblies(fleet_b.ships)
		return empty_attacker_replay

	if fleet_b == null or fleet_b.ships.is_empty():
		var empty_defender_replay := CombatReplay.new_battle(battle_seed)
		empty_defender_replay.winner = fleet_a.faction
		empty_defender_replay.survivors_a = _copy_assemblies(fleet_a.ships)
		return empty_defender_replay

	var units_a: Array[Dictionary] = _spawn_fleet(fleet_a, cat, events, &"a", SPAWN_X_A)
	var units_b: Array[Dictionary] = _spawn_fleet(fleet_b, cat, events, &"b", SPAWN_X_B)

	var time := 0.0
	var tick := cfg.tick
	var max_time := cfg.max_time

	while time < max_time:
		time += tick
		var living_a := _get_living(units_a)
		var living_b := _get_living(units_b)

		if living_a.is_empty() or living_b.is_empty():
			break

		# Ships with functioning drives advance toward the enemy firing line.
		_advance_fleet(units_a, SPAWN_X_B, tick, time, events)
		_advance_fleet(units_b, SPAWN_X_A, tick, time, events)

		# Flotte A feuert auf Flotte B
		for attacker in living_a:
			if not _can_fire(attacker, SPAWN_X_B):
				continue
			var target: Dictionary = living_b[rng.randi_range(0, living_b.size() - 1)]
			var damage: float = float(attacker["dps"]) * tick * rng.randf_range(cfg.damage_variance_min, cfg.damage_variance_max)
			events.append(BattleEvent.create(time, BattleEvent.TYPE_FIRE, attacker["id"], target["id"], damage, attacker["pos"], target["pos"]))
			apply_damage_to_unit(target, damage, rng, events, time + 0.1, attacker["id"], target["id"])

		# Flotte B feuert auf Flotte A
		for attacker in living_b:
			if not attacker.get("alive", false):
				continue
			if not _can_fire(attacker, SPAWN_X_A):
				continue
			var target_candidates := _get_living(units_a)
			if target_candidates.is_empty():
				break
			var target: Dictionary = target_candidates[rng.randi_range(0, target_candidates.size() - 1)]
			var damage: float = float(attacker["dps"]) * tick * rng.randf_range(cfg.damage_variance_min, cfg.damage_variance_max)
			events.append(BattleEvent.create(time, BattleEvent.TYPE_FIRE, attacker["id"], target["id"], damage, attacker["pos"], target["pos"]))
			apply_damage_to_unit(target, damage, rng, events, time + 0.1, attacker["id"], target["id"])

	var surviving_a := _get_living(units_a)
	var surviving_b := _get_living(units_b)

	var winner: StringName = &"neutral"
	if surviving_a.size() > 0 and surviving_b.is_empty():
		winner = fleet_a.faction
	elif surviving_b.size() > 0 and surviving_a.is_empty():
		winner = fleet_b.faction
	elif surviving_a.size() > surviving_b.size():
		winner = fleet_a.faction
	elif surviving_b.size() > surviving_a.size():
		winner = fleet_b.faction

	var survivors_a_data: Array[ShipAssembly] = []
	for unit in surviving_a:
		var surviving_ship: ShipAssembly = unit["ship_data"] as ShipAssembly
		if surviving_ship != null:
			survivors_a_data.append(surviving_ship.copy())

	var survivors_b_data: Array[ShipAssembly] = []
	for unit in surviving_b:
		var surviving_ship: ShipAssembly = unit["ship_data"] as ShipAssembly
		if surviving_ship != null:
			survivors_b_data.append(surviving_ship.copy())

	var replay := CombatReplay.new_battle(battle_seed)
	replay.winner = winner
	replay.survivors_a = survivors_a_data
	replay.survivors_b = survivors_b_data
	replay.events = events
	replay.duration = time
	return replay


## Runs the existing deterministic fleet combat while attaching real
## NavigationField routes and route-derived event positions for the visible L2
## cutscene. The combat result remains the same seed-stable simulator output.
static func simulate_route_battle(
	fleet_a: FleetSnapshot,
	fleet_b: FleetSnapshot,
	route_a: Array[Vector2],
	route_b: Array[Vector2],
	engagement: Dictionary,
	battle_seed: int = 1337,
	catalog: ShipPartCatalog = null,
	config: BattleConfig = null
) -> CombatReplay:
	var replay := simulate_battle(fleet_a, fleet_b, battle_seed, catalog, config)
	replay.route_a = route_a.duplicate()
	replay.route_b = route_b.duplicate()
	if engagement != null:
		replay.engagement_point = engagement.get("point", Vector2.ZERO)
		replay.engagement_type = engagement.get("type", &"")
		replay.engagement_time_a = float(engagement.get("time_a", 0.0))
		replay.engagement_time_b = float(engagement.get("time_b", 0.0))
	for event in replay.events:
		if event == null:
			continue
		if String(event.source_id).begins_with("a_"):
			event.source_pos = _route_position(route_a, event.timestamp, replay.duration)
		else:
			event.source_pos = _route_position(route_b, event.timestamp, replay.duration)
		if not String(event.target_id).is_empty():
			if String(event.target_id).begins_with("a_"):
				event.target_pos = _route_position(route_a, event.timestamp, replay.duration)
			else:
				event.target_pos = _route_position(route_b, event.timestamp, replay.duration)
	return replay


static func _route_position(route: Array[Vector2], time: float, duration: float) -> Vector2:
	if route.is_empty():
		return Vector2.ZERO
	if route.size() == 1 or duration <= 0.0:
		return route[0]
	var total_length := PathUtils.distance(route)
	if total_length <= 0.0:
		return route[0]
	var target_distance := clampf(time / duration, 0.0, 1.0) * total_length
	var travelled := 0.0
	for index in range(route.size() - 1):
		var segment_length := route[index].distance_to(route[index + 1])
		if travelled + segment_length >= target_distance:
			var factor := (target_distance - travelled) / maxf(segment_length, 0.001)
			return route[index].lerp(route[index + 1], factor)
		travelled += segment_length
	return route.back()


## Builds the runtime combat unit (mutable module dictionary) for one ship.
## Exposed for preflight assertions on the module-damage model.
static func build_combat_unit(ship: ShipAssembly, faction: StringName, unit_id: StringName, catalog: ShipPartCatalog = null, pos: Vector2 = Vector2.ZERO) -> Dictionary:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	var stats := FleetSnapshot.calculate_ship_stats(ship, cat)
	var modules: Array[Dictionary] = []
	for entry in stats.get("modules", []):
		var mod: Dictionary = (entry as Dictionary).duplicate(true)
		mod["hp"] = float(mod.get("max_hp", 0.0))
		mod["alive"] = true
		modules.append(mod)
	var unit := {
		"id": unit_id,
		"ship_data": ship,
		"faction": faction,
		"modules": modules,
		"pos": pos,
		"hp": float(stats.get("hp", FleetSnapshot.BASE_HULL_HP)),
		"max_hp": float(stats.get("hp", FleetSnapshot.BASE_HULL_HP)),
		"dps": float(stats.get("dps", FleetSnapshot.BASE_DPS)),
		"range": float(stats.get("range", FleetSnapshot.BASE_RANGE)),
		"speed": float(stats.get("speed", FleetSnapshot.BASE_SPEED)),
		"alive": true,
	}
	recompute_unit_stats(unit)
	return unit


## Recomputed ship aggregates from alive modules only. A ship without any
## living drive module becomes immobile (speed 0); without its hull it dies.
static func recompute_unit_stats(unit: Dictionary) -> void:
	if unit == null:
		return
	var dps := FleetSnapshot.BASE_DPS
	var range := FleetSnapshot.BASE_RANGE
	var speed_mult := 1.0
	var drives_alive := 0
	var hull_alive := false
	var total_hp := 0.0
	for mod in unit.get("modules", []):
		if mod == null or not mod.get("alive", false):
			continue
		var stat: Dictionary = mod.get("stat", {}) as Dictionary
		dps += float(stat.get("dps", 0.0))
		range += float(stat.get("range", 0.0))
		speed_mult *= float(stat.get("speed_mult", 1.0))
		total_hp += float(mod.get("hp", 0.0))
		var slot_type: StringName = mod.get("slot_type", &"") as StringName
		if slot_type == ShipPartDefinition.SLOT_DRIVE:
			drives_alive += 1
		if slot_type == ShipPartDefinition.SLOT_HULL:
			hull_alive = true
	unit["dps"] = dps
	unit["range"] = range
	unit["speed"] = FleetSnapshot.BASE_SPEED * speed_mult if drives_alive > 0 else 0.0
	unit["hp"] = total_hp
	unit["alive"] = hull_alive and total_hp > 0.0


## Applies one attack's damage to the target's modules, weighted by module
## influence. Damage bleeds from one module into the next (no wasted overkill)
## and module destruction immediately recomputes the target's stats. Appends
## TYPE_MODULE_HIT / TYPE_MODULE_DESTROYED / TYPE_DESTROYED events.
## Exposed for preflight assertions on the module-damage model.
static func apply_damage_to_unit(unit: Dictionary, damage: float, rng: RandomNumberGenerator, events: Array = [], time: float = 0.0, attacker_id: StringName = &"", target_id: StringName = &"") -> void:
	if unit == null or not unit.get("alive", false) or damage <= 0.0:
		return
	var remaining := damage
	var guard := 0
	while remaining > 0.01 and guard < 32:
		guard += 1
		var alive_modules := _alive_modules(unit)
		if alive_modules.is_empty():
			break
		var picked: Dictionary = _pick_module(rng, alive_modules)
		var applied := minf(remaining, float(picked.get("hp", 0.0)))
		picked["hp"] = maxf(0.0, float(picked.get("hp", 0.0)) - applied)
		remaining -= applied
		if events != null:
			events.append(BattleEvent.create_module(
				time,
				BattleEvent.TYPE_MODULE_HIT,
				attacker_id,
				target_id,
				applied,
				picked.get("part_id", &"") as StringName,
				picked.get("slot_type", &"") as StringName,
				picked.get("trait", &"") as StringName,
				unit["pos"],
				unit["pos"]
			))
		if float(picked.get("hp", 0.0)) <= 0.0 and picked.get("alive", false):
			picked["alive"] = false
			if events != null:
				events.append(BattleEvent.create_module(
					time + 0.05,
					BattleEvent.TYPE_MODULE_DESTROYED,
					target_id,
					&"",
					0.0,
					picked.get("part_id", &"") as StringName,
					picked.get("slot_type", &"") as StringName,
					picked.get("trait", &"") as StringName,
					unit["pos"],
					unit["pos"]
				))
			recompute_unit_stats(unit)
			if not unit.get("alive", false):
				if events != null:
					events.append(BattleEvent.create(time + 0.1, BattleEvent.TYPE_DESTROYED, target_id, &"", 0.0, unit["pos"]))
				return
	recompute_unit_stats(unit)


static func _calculate_ship_combat_stats(ship: ShipAssembly, cat: ShipPartCatalog) -> Dictionary:
	return FleetSnapshot.calculate_ship_stats(ship, cat)


static func _copy_assemblies(source: Array[ShipAssembly]) -> Array[ShipAssembly]:
	var result: Array[ShipAssembly] = []
	for assembly in source:
		if assembly != null:
			result.append(assembly.copy())
	return result


static func _spawn_fleet(fleet: FleetSnapshot, cat: ShipPartCatalog, events: Array, prefix: StringName, start_x: float) -> Array[Dictionary]:
	var units: Array[Dictionary] = []
	for i in range(fleet.ships.size()):
		var ship: ShipAssembly = fleet.ships[i]
		var pos := Vector2(start_x, float(i * 40 - (fleet.ships.size() - 1) * 20))
		var unit := build_combat_unit(ship, fleet.faction, StringName("%s_%d" % [String(prefix), i]), cat, pos)
		units.append(unit)
		events.append(BattleEvent.create(0.0, BattleEvent.TYPE_SPAWN, unit["id"], &"", unit["hp"], pos, Vector2.ZERO, ship))
	return units


static func _advance_fleet(units: Array, target_center_x: float, tick: float, time: float, events: Array) -> void:
	for unit in units:
		if not unit.get("alive", false):
			continue
		var speed := float(unit.get("speed", 0.0))
		if speed <= 0.0:
			continue
		var range := float(unit.get("range", FleetSnapshot.BASE_RANGE))
		var firing_line := target_center_x - signf(target_center_x) * range
		if absf(firing_line - float(unit["pos"].x)) <= 1.0:
			continue
		var step := speed * tick
		unit["pos"].x = move_toward(float(unit["pos"].x), firing_line, step)
		events.append(BattleEvent.create(time, BattleEvent.TYPE_MOVE, unit["id"], &"", 0.0, unit["pos"]))


static func _can_fire(unit: Dictionary, target_center_x: float) -> bool:
	if not unit.get("alive", false):
		return false
	return absf(target_center_x - float(unit["pos"].x)) <= float(unit.get("range", FleetSnapshot.BASE_RANGE)) + 0.5


static func _alive_modules(unit: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mod in unit.get("modules", []):
		if mod != null and mod.get("alive", false) and float(mod.get("hp", 0.0)) > 0.0:
			result.append(mod as Dictionary)
	return result


static func _pick_module(rng: RandomNumberGenerator, alive_modules: Array[Dictionary]) -> Dictionary:
	var total := 0.0
	for mod in alive_modules:
		total += float(mod.get("weight", 1.0))
	if total <= 0.0:
		return alive_modules[rng.randi_range(0, alive_modules.size() - 1)] as Dictionary
	var roll := rng.randf() * total
	for mod in alive_modules:
		roll -= float(mod.get("weight", 1.0))
		if roll <= 0.0:
			return mod
	return alive_modules.back() as Dictionary


static func _get_living(units: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit in units:
		if unit.get("alive", false) and float(unit.get("hp", 0.0)) > 0.0:
			result.append(unit)
	return result
