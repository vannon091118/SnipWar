@tool
class_name FleetBattleSimulator
extends RefCounted

const DEFAULT_SHIP_PART_CATALOG: ShipPartCatalog = preload("res://resources/config/ship_part_catalog_default.tres")

static func simulate_battle(fleet_a: FleetSnapshot, fleet_b: FleetSnapshot, battle_seed: int = 1337, catalog: ShipPartCatalog = null) -> CombatReplay:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
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

	# Initialisiere Kampf-Einheiten. The runtime combat state remains a
	# Dictionary because it contains mutable hp/position fields; its immutable
	# loadout payload is always a ShipAssembly resource.
	var units_a: Array[Dictionary] = []
	for i in range(fleet_a.ships.size()):
		var ship: ShipAssembly = fleet_a.ships[i]
		var stats := _calculate_ship_combat_stats(ship, cat)
		var unit := {
			"id": StringName("a_%d" % i),
			"ship_data": ship,
			"faction": fleet_a.faction,
			"hp": stats["hp"],
			"max_hp": stats["hp"],
			"dps": stats["dps"],
			"pos": Vector2(-180.0, float(i * 40 - (fleet_a.ships.size() - 1) * 20)),
			"alive": true
		}
		units_a.append(unit)
		events.append(BattleEvent.create(
			0.0,
			BattleEvent.TYPE_SPAWN,
			unit["id"],
			&"",
			unit["hp"],
			unit["pos"],
			Vector2.ZERO,
			unit["ship_data"] as ShipAssembly
		))

	var units_b: Array[Dictionary] = []
	for i in range(fleet_b.ships.size()):
		var ship: ShipAssembly = fleet_b.ships[i]
		var stats := _calculate_ship_combat_stats(ship, cat)
		var unit := {
			"id": StringName("b_%d" % i),
			"ship_data": ship,
			"faction": fleet_b.faction,
			"hp": stats["hp"],
			"max_hp": stats["hp"],
			"dps": stats["dps"],
			"pos": Vector2(180.0, float(i * 40 - (fleet_b.ships.size() - 1) * 20)),
			"alive": true
		}
		units_b.append(unit)
		events.append(BattleEvent.create(
			0.0,
			BattleEvent.TYPE_SPAWN,
			unit["id"],
			&"",
			unit["hp"],
			unit["pos"],
			Vector2.ZERO,
			unit["ship_data"] as ShipAssembly
		))

	var time := 0.0
	var tick := 0.5
	var max_time := 30.0

	while time < max_time:
		time += tick
		var living_a := _get_living(units_a)
		var living_b := _get_living(units_b)

		if living_a.is_empty() or living_b.is_empty():
			break

		# Flotte A feuert auf Flotte B
		for attacker in living_a:
			var target: Dictionary = living_b[rng.randi_range(0, living_b.size() - 1)]
			var damage: float = attacker["dps"] * tick * rng.randf_range(0.85, 1.15)
			target["hp"] = maxf(0.0, target["hp"] - damage)
			events.append(BattleEvent.create(time, BattleEvent.TYPE_FIRE, attacker["id"], target["id"], damage, attacker["pos"], target["pos"]))
			events.append(BattleEvent.create(time + 0.1, BattleEvent.TYPE_HIT, attacker["id"], target["id"], damage, attacker["pos"], target["pos"]))
			if target["hp"] <= 0.0 and target["alive"]:
				target["alive"] = false
				events.append(BattleEvent.create(time + 0.15, BattleEvent.TYPE_DESTROYED, target["id"], &"", 0.0, target["pos"]))

		# Flotte B feuert auf Flotte A
		for attacker in living_b:
			if not attacker["alive"]:
				continue
			var target_candidates := _get_living(units_a)
			if target_candidates.is_empty():
				break
			var target: Dictionary = target_candidates[rng.randi_range(0, target_candidates.size() - 1)]
			var damage: float = attacker["dps"] * tick * rng.randf_range(0.85, 1.15)
			target["hp"] = maxf(0.0, target["hp"] - damage)
			events.append(BattleEvent.create(time, BattleEvent.TYPE_FIRE, attacker["id"], target["id"], damage, attacker["pos"], target["pos"]))
			events.append(BattleEvent.create(time + 0.1, BattleEvent.TYPE_HIT, attacker["id"], target["id"], damage, attacker["pos"], target["pos"]))
			if target["hp"] <= 0.0 and target["alive"]:
				target["alive"] = false
				events.append(BattleEvent.create(time + 0.15, BattleEvent.TYPE_DESTROYED, target["id"], &"", 0.0, target["pos"]))

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
	catalog: ShipPartCatalog = null
) -> CombatReplay:
	var replay := simulate_battle(fleet_a, fleet_b, battle_seed, catalog)
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

static func _calculate_ship_combat_stats(ship: ShipAssembly, cat: ShipPartCatalog) -> Dictionary:
	return FleetSnapshot.calculate_ship_stats(ship, cat)

static func _copy_assemblies(source: Array[ShipAssembly]) -> Array[ShipAssembly]:
	var result: Array[ShipAssembly] = []
	for assembly in source:
		if assembly != null:
			result.append(assembly.copy())
	return result

static func _get_living(units: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for unit in units:
		if unit.get("alive", false) and float(unit.get("hp", 0.0)) > 0.0:
			result.append(unit)
	return result
