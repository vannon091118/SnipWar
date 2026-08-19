@tool
class_name FleetBattleSimulator
extends RefCounted

const DEFAULT_SHIP_PART_CATALOG: ShipPartCatalog = preload("res://resources/config/ship_part_catalog_default.tres")

static func simulate_battle(fleet_a: FleetSnapshot, fleet_b: FleetSnapshot, battle_seed: int = 1337, catalog: ShipPartCatalog = null) -> Dictionary:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	var events: Array[BattleEvent] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = battle_seed

	if fleet_a == null or fleet_a.ships.is_empty():
		return {
			"winner": fleet_b.faction if fleet_b != null else &"neutral",
			"survivors_a": [],
			"survivors_b": fleet_b.ships.duplicate() if fleet_b != null else [],
			"events": events,
			"duration": 0.0
		}

	if fleet_b == null or fleet_b.ships.is_empty():
		return {
			"winner": fleet_a.faction,
			"survivors_a": fleet_a.ships.duplicate(),
			"survivors_b": [],
			"events": events,
			"duration": 0.0
		}

	# Initialisiere Kampf-Einheiten
	var units_a: Array[Dictionary] = []
	for i in range(fleet_a.ships.size()):
		var ship: Dictionary = fleet_a.ships[i]
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
		events.append(BattleEvent.create(0.0, BattleEvent.TYPE_SPAWN, unit["id"], &"", unit["hp"], unit["pos"]))

	var units_b: Array[Dictionary] = []
	for i in range(fleet_b.ships.size()):
		var ship: Dictionary = fleet_b.ships[i]
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
		events.append(BattleEvent.create(0.0, BattleEvent.TYPE_SPAWN, unit["id"], &"", unit["hp"], unit["pos"]))

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

	var survivors_a_data: Array[Dictionary] = []
	for u in surviving_a:
		survivors_a_data.append(u["ship_data"])

	var survivors_b_data: Array[Dictionary] = []
	for u in surviving_b:
		survivors_b_data.append(u["ship_data"])

	return {
		"winner": winner,
		"survivors_a": survivors_a_data,
		"survivors_b": survivors_b_data,
		"events": events,
		"duration": time
	}

static func _calculate_ship_combat_stats(ship: Dictionary, cat: ShipPartCatalog) -> Dictionary:
	var hp := 50.0
	var dps := 10.0
	if cat != null:
		var hull := cat.resolve(ship.get("hull", &"") as StringName)
		if hull != null:
			hp += float(hull.tier * 30)
			if hull.trait_definition != null:
				hp += float(hull.trait_definition.hull_hp_bonus)
				dps += hull.trait_definition.dps_bonus
		for mod_val in ship.get("modules", []):
			var mod := cat.resolve(mod_val as StringName)
			if mod != null:
				dps += float(mod.tier * 5)
				if mod.trait_definition != null:
					dps += mod.trait_definition.dps_bonus
					hp += float(mod.trait_definition.hull_hp_bonus)
	return {"hp": hp, "dps": dps}

static func _get_living(units: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for u in units:
		if u.get("alive", false) and float(u.get("hp", 0.0)) > 0.0:
			result.append(u)
	return result
