class_name PreflightConstraintModuleDamageModel
extends RefCounted

## Mathematical foundation of the module-based damage model: influence scaling,
## HP distribution, module destruction consequences (immobility), repair drone
## caps and the drone tech-tree merge prerequisites. Pure — no scene boot.

const SHIP_PART_CATALOG: ShipPartCatalog = preload("res://resources/config/ship_part_catalog_default.tres")
const TECH_CATALOG: TechnologyCatalog = preload("res://resources/config/technology_catalog_default.tres")
const CONQUEST_CONFIG: ConquestConfig = preload("res://resources/config/conquest_config_default.tres")

func constraint_name() -> String:
	return "module_damage_model"


func run(ctx: PreflightContext) -> bool:
	# 1. Influence scaling curve: 1 drive = 20 %, 2 drives ≈ 15 % each, with
	#    diminishing total returns (the "fair" model from the design).
	var one := ModuleInfluence.type_influence(ModuleInfluence.INFLUENCE_DRIVE, 1)
	var two_total := ModuleInfluence.type_influence(ModuleInfluence.INFLUENCE_DRIVE, 2)
	var two_each := ModuleInfluence.instance_influence(ModuleInfluence.INFLUENCE_DRIVE, 2)
	var three_each := ModuleInfluence.instance_influence(ModuleInfluence.INFLUENCE_DRIVE, 3)
	if not ctx.check(is_equal_approx(one, 0.2), "one drive should carry 20 %% influence (got %.4f)" % one):
		return false
	if not ctx.check(absf(two_total - 0.2 * pow(2.0, 0.6)) < 0.001, "two drives should scale sub-linearly (total %.4f)" % two_total):
		return false
	if not ctx.check(absf(two_each - 0.1516) < 0.001, "two drives should split ≈15 %% each (got %.4f)" % two_each):
		return false
	if not ctx.check(absf(three_each - 0.1289) < 0.001, "three drives should split ≈12.9 %% each (got %.4f)" % three_each):
		return false
	if not ctx.check(two_each < one and three_each < two_each, "per-instance influence must fall with redundancy"):
		return false

	# 2. HP distribution: module HP sums to the pool and weights stay normalized.
	var probe_entries: Array[Dictionary] = [
		{"part_id": &"hull_t1", "slot_type": ShipPartDefinition.SLOT_HULL},
		{"part_id": &"drive_t1", "slot_type": ShipPartDefinition.SLOT_DRIVE},
		{"part_id": &"drive_t1", "slot_type": ShipPartDefinition.SLOT_DRIVE},
		{"part_id": &"weapon_t1", "slot_type": ShipPartDefinition.SLOT_WEAPON},
		{"part_id": &"shield_t1", "slot_type": ShipPartDefinition.SLOT_SHIELD},
		{"part_id": &"scanner_t1", "slot_type": ShipPartDefinition.SLOT_SCANNER},
	]
	ModuleInfluence.distribute_hp(probe_entries, 200.0)
	var sum_hp := 0.0
	var sum_weights := 0.0
	for entry in probe_entries:
		sum_hp += float(entry.get("hp", 0.0))
		sum_weights += float(entry.get("weight", 0.0))
	if not ctx.check(absf(sum_hp - 200.0) < 0.001, "module HP must sum to the ship pool (got %.2f)" % sum_hp):
		return false
	if not ctx.check(absf(sum_weights - (ModuleInfluence.type_influence(ModuleInfluence.INFLUENCE_HULL, 1) + ModuleInfluence.type_influence(ModuleInfluence.INFLUENCE_DRIVE, 2) + ModuleInfluence.INFLUENCE_WEAPON + ModuleInfluence.INFLUENCE_SHIELD + ModuleInfluence.INFLUENCE_SCANNER)) < 0.001, "module weights must sum to the normalized influence pool"):
		return false

	# 3. Ship stats expose module states whose HP sums to total_hull_hp.
	var ship: ShipAssembly = ctx.make_ship_assembly(&"hull_t1", &"scanner_t1", [], &"", &"drive_t1", &"shield_t1")
	var stats := FleetSnapshot.calculate_ship_stats(ship, SHIP_PART_CATALOG)
	var module_sum := 0.0
	var drive_module: Dictionary = {}
	for mod in stats.get("modules", []):
		module_sum += float(mod.get("max_hp", 0.0))
		if (mod.get("slot_type", &"") as StringName) == ShipPartDefinition.SLOT_DRIVE:
			drive_module = mod
	if not ctx.check(absf(module_sum - float(stats.get("hp", 0.0))) < 0.001, "module HP must sum to the ship pool"):
		return false
	if not ctx.check(absf(float(stats.get("hp", 0.0)) - float(ship_hull_hp(ship))) < 0.001, "calculate_ship_stats pool must equal FleetSnapshot total_hull_hp"):
		return false
	if not ctx.check(not drive_module.is_empty() and (drive_module.get("trait", &"") as StringName) == ModuleInfluence.TRAIT_SPEED, "drive module must carry the speed influence trait"):
		return false

	# 4. Destroyed drive → immobile (speed 0) while the ship stays alive.
	var unit := FleetBattleSimulator.build_combat_unit(ship, GameState.FACTION_PLAYER, &"probe_a", SHIP_PART_CATALOG, Vector2(-100.0, 0.0))
	if not ctx.check(float(unit.get("speed", 0.0)) > 0.0 and unit.get("alive", false), "fresh combat unit must be mobile and alive"):
		return false
	var drive_index := -1
	for index in range((unit.get("modules", []) as Array).size()):
		var mod: Dictionary = (unit["modules"] as Array)[index] as Dictionary
		if (mod.get("slot_type", &"") as StringName) == ShipPartDefinition.SLOT_DRIVE:
			drive_index = index
			break
	if not ctx.check(drive_index >= 0, "combat unit must contain a drive module"):
		return false
	var drive_stat: Dictionary = (unit["modules"] as Array)[drive_index] as Dictionary
	drive_stat["hp"] = 0.0
	drive_stat["alive"] = false
	FleetBattleSimulator.recompute_unit_stats(unit)
	if not ctx.check(is_equal_approx(float(unit.get("speed", 1.0)), 0.0), "destroyed drive must immobilize the ship"):
		return false
	if not ctx.check(unit.get("alive", false), "ship must survive losing only its drive"):
		return false

	# 5. Destroyed weapon → DPS drops by exactly its payload.
	var armed: ShipAssembly = ctx.make_ship_assembly(&"hull_t1", &"scanner_t1", [], &"weapon_t1", &"drive_t1", &"shield_t1")
	var armed_stats := FleetSnapshot.calculate_ship_stats(armed, SHIP_PART_CATALOG)
	var armed_unit := FleetBattleSimulator.build_combat_unit(armed, GameState.FACTION_PLAYER, &"probe_b", SHIP_PART_CATALOG)
	var dps_before := float(armed_unit.get("dps", 0.0))
	var weapon_payload := 0.0
	for mod in armed_unit.get("modules", []):
		if (mod.get("slot_type", &"") as StringName) == ShipPartDefinition.SLOT_WEAPON:
			weapon_payload += float((mod.get("stat", {}) as Dictionary).get("dps", 0.0))
			mod["hp"] = 0.0
			mod["alive"] = false
	FleetBattleSimulator.recompute_unit_stats(armed_unit)
	if not ctx.check(absf(float(armed_unit.get("dps", 0.0)) - (dps_before - weapon_payload)) < 0.001, "destroyed weapon must drop DPS by its payload"):
		return false

	# 6. Deterministic weighted damage application reduces exactly the module HP.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var damage_target := FleetBattleSimulator.build_combat_unit(ship, GameState.FACTION_PLAYER, &"probe_c", SHIP_PART_CATALOG)
	var hp_before := float(damage_target.get("hp", 0.0))
	var events: Array[BattleEvent] = []
	FleetBattleSimulator.apply_damage_to_unit(damage_target, 30.0, rng, events, 1.0, &"probe_a", &"probe_c")
	if not ctx.check(absf(float(damage_target.get("hp", 0.0)) - (hp_before - 30.0)) < 0.001, "applied damage must reduce the module pool exactly"):
		return false
	if not ctx.check(events.size() >= 1, "damage application must emit module hit events"):
		return false
	var module_event: BattleEvent = events[0]
	if not ctx.check(module_event.event_type == BattleEvent.TYPE_MODULE_HIT and not String(module_event.module_slot_type).is_empty(), "module hit event must carry the module slot type"):
		return false

	# 7. Repair drones: caps grow with tier, healing never exceeds the cap.
	var default_cfg: ConquestConfig = CONQUEST_CONFIG
	if not ctx.check(default_cfg.repair_cap_t1 < default_cfg.repair_cap_t2 and default_cfg.repair_cap_t2 < default_cfg.repair_cap_t3, "repair caps must grow with drone tier"):
		return false
	var repaired_ship: ShipAssembly = ctx.make_ship_assembly(&"hull_t1", &"scanner_t1", [&"repair_drone_t2"], &"", &"drive_t1", &"shield_t1")
	var minion := AssaultMinionDefinition.from_ship(repaired_ship, SHIP_PART_CATALOG, 10.0, 2.0, 60.0, default_cfg)
	if not ctx.check(absf(minion.repair_cap - 0.5) < 0.001, "T2 repair drone should cap at 50 %"):
		return false
	if not ctx.check(minion.repair_rate > 0.0, "T2 repair drone should have a positive regeneration rate"):
		return false
	# Deterministically damage every module to 30 % (below the 50 % cap,
	# nothing destroyed) so the minion stays alive and repairable.
	for mod in minion.modules:
		mod["hp"] = float(mod.get("max_hp", 0.0)) * 0.3
	if not ctx.check(minion.current_hp() < minion.max_hp * 0.5, "damaged minion should drop below the repair cap"):
		return false
	var healed: float = minion.repair(120.0, RandomNumberGenerator.new())
	if not ctx.check(healed > 0.0, "repair drone should regenerate module HP"):
		return false
	if not ctx.check(absf(minion.current_hp() - minion.max_hp * 0.5) < 0.01, "repair must never exceed the tier cap"):
		return false
	if not ctx.check(minion.current_hp() <= minion.max_hp * 0.5 + 0.01, "repair must never heal beyond the tier cap"):
		return false
	if not ctx.check(minion.repair(120.0, RandomNumberGenerator.new()) == 0.0, "repair should stop once the cap is reached"):
		return false
	# T1 stays below T2 below T3 when mounted.
	var t1_minion := AssaultMinionDefinition.from_ship(ctx.make_ship_assembly(&"hull_t1", &"scanner_t1", [&"repair_drone_t1"], &"", &"drive_t1", &"shield_t1"), SHIP_PART_CATALOG, 10.0, 2.0, 60.0, default_cfg)
	var t3_minion := AssaultMinionDefinition.from_ship(ctx.make_ship_assembly(&"hull_t1", &"scanner_t1", [&"repair_drone_t3"], &"", &"drive_t1", &"shield_t1"), SHIP_PART_CATALOG, 10.0, 2.0, 60.0, default_cfg)
	if not ctx.check(t1_minion.repair_cap < minion.repair_cap and minion.repair_cap < t3_minion.repair_cap, "repair caps must scale T1 < T2 < T3"):
		return false
	if not ctx.check(t1_minion.repair_rate > t3_minion.repair_rate or t3_minion.repair_rate > minion.repair_rate, "recharge pacing must differ across tiers"):
		return false

	# 8. Booster modules amplify mounted drone modules.
	var boosted: ShipAssembly = ctx.make_ship_assembly(&"hull_t1", &"scanner_t1", [&"combat_drone_t1", &"drone_booster_t1"], &"", &"drive_t1", &"shield_t1")
	var boosted_stats := FleetSnapshot.calculate_ship_stats(boosted, SHIP_PART_CATALOG)
	var plain: ShipAssembly = ctx.make_ship_assembly(&"hull_t1", &"scanner_t1", [&"combat_drone_t1"], &"", &"drive_t1", &"shield_t1")
	var plain_stats := FleetSnapshot.calculate_ship_stats(plain, SHIP_PART_CATALOG)
	if not ctx.check(absf(float(boosted_stats.get("booster_multiplier", 1.0)) - 1.25) < 0.001, "T1 booster should amplify drone modules by 25 %"):
		return false
	if not ctx.check(float(boosted_stats.get("dps", 0.0)) > float(plain_stats.get("dps", 0.0)), "booster must raise the ship's drone DPS"):
		return false

	# 9. Dynamic slot system: hull schemas scale with ship size.
	if not ctx.check(SHIP_PART_CATALOG.validate().is_empty(), "ship part catalog validation failed"):
		return false
	var hull_t2: ShipPartDefinition = SHIP_PART_CATALOG.resolve(&"hull_t2")
	var layout := SHIP_PART_CATALOG.slot_layout_for(hull_t2)
	if not ctx.check(int(layout.get(ShipPartDefinition.SLOT_DRIVE, 0)) == 2, "hull_t2 should offer two drive slots"):
		return false
	var hull_t1: ShipPartDefinition = SHIP_PART_CATALOG.resolve(&"hull_t1")
	if not ctx.check(int(SHIP_PART_CATALOG.slot_layout_for(hull_t1).get(ShipPartDefinition.SLOT_UTILITY, 0)) == 1, "hull_t1 should offer one utility slot"):
		return false
	for drone_id in [&"repair_drone_t1", &"repair_drone_t2", &"repair_drone_t3", &"combat_drone_t1", &"combat_drone_t2", &"scan_drone_t1", &"scan_drone_t2", &"drone_vision", &"drone_booster_t1", &"drone_booster_t2"]:
		if not ctx.check(SHIP_PART_CATALOG.resolve(drone_id) != null, "drone module part %s is missing" % drone_id):
			return false

	# 10. Drone tech tree: root merges mech + ship research, then branches.
	if not ctx.check(TECH_CATALOG.validate().is_empty(), "technology catalog validation failed"):
		return false
	var swarm: TechnologyDefinition = TECH_CATALOG.resolve(&"drone_swarm")
	if not ctx.check(swarm != null and swarm.category == TechnologyDefinition.CATEGORY_DRONES, "drone_swarm root technology is missing or miscategorized"):
		return false
	if not ctx.check(swarm.prerequisite_tech_ids.has(&"mech_frame") and swarm.prerequisite_tech_ids.has(&"scanner_drone"), "drone_swarm must merge mech_frame and scanner_drone"):
		return false
	if not ctx.check(TECH_CATALOG.can_research([&"mech_frame", &"scanner_drone"], &"drone_swarm"), "drone_swarm must be researchable with both prerequisites"):
		return false
	if not ctx.check(not TECH_CATALOG.can_research([&"mech_frame"], &"drone_swarm"), "drone_swarm must require the ship prerequisite"):
		return false
	if not ctx.check(not TECH_CATALOG.can_research([&"scanner_drone"], &"drone_swarm"), "drone_swarm must require the mech prerequisite"):
		return false
	for branch in [&"repair_drone_t1", &"repair_drone_t2", &"repair_drone_t3", &"combat_drone_t1", &"combat_drone_t2", &"scan_drone_t1", &"scan_drone_t2", &"drone_vision", &"drone_booster_t1", &"drone_booster_t2"]:
		if not ctx.check(TECH_CATALOG.resolve(branch) != null, "drone tech branch %s is missing" % branch):
			return false
	if not ctx.check(TECH_CATALOG.resolve(&"repair_drone_t2").prerequisite_tech_id == &"repair_drone_t1" and TECH_CATALOG.resolve(&"repair_drone_t3").prerequisite_tech_id == &"repair_drone_t2", "repair branch must chain T1 → T2 → T3"):
		return false

	# 11. CPU loadout builder: the opponent uses the module meta, not presets.
	var cpu_rng := RandomNumberGenerator.new()
	cpu_rng.seed = 42
	var no_techs := CpuLoadoutBuilder.build_loadout(SHIP_PART_CATALOG, [], cpu_rng, GameState.MISSION_MILITARY)
	if not ctx.check(no_techs.is_empty(), "CPU loadout builder must stay empty without research"):
		return false
	var cpu_techs: Array = [&"shipyard_construction", &"scanner_drone", &"weapon_systems", &"repair_drone_t1", &"combat_drone_t1", &"drone_booster_t1"]
	var military_loadout: Dictionary = CpuLoadoutBuilder.build_loadout(SHIP_PART_CATALOG, cpu_techs, cpu_rng, GameState.MISSION_MILITARY)
	if not ctx.check(military_loadout.has("hull_id") and military_loadout.has("drive_id"), "CPU military loadout must contain hull and drive"):
		return false
	var military_hull: ShipPartDefinition = SHIP_PART_CATALOG.resolve(military_loadout.get("hull_id", &""))
	var military_layout: Dictionary = SHIP_PART_CATALOG.slot_layout_for(military_hull)
	if not ctx.check(not String(military_loadout.get("weapon_id", &"")).is_empty(), "CPU military loadout must mount a weapon"):
		return false
	var military_modules: Array = military_loadout.get("module_ids", [])
	var drive_tally := 1 + int(military_modules.count(military_loadout.get("drive_id", &"")))
	if not ctx.check(drive_tally <= int(military_layout.get(ShipPartDefinition.SLOT_DRIVE, 1)), "CPU military loadout must respect the hull's drive capacity"):
		return false
	if not ctx.check(military_modules.has(&"combat_drone_t1"), "CPU military loadout must use combat drones"):
		return false
	var booster_techs: Array = [&"shipyard_construction", &"scanner_drone", &"weapon_systems", &"drone_booster_t1"]
	var boosted_loadout: Dictionary = CpuLoadoutBuilder.build_loadout(SHIP_PART_CATALOG, booster_techs, cpu_rng, GameState.MISSION_MILITARY)
	if not ctx.check(boosted_loadout.get("module_ids", []).has(&"drone_booster_t1"), "CPU military loadout must mount a booster when researched"):
		return false
	var colony_loadout: Dictionary = CpuLoadoutBuilder.build_loadout(SHIP_PART_CATALOG, cpu_techs, cpu_rng, GameState.MISSION_COLONY)
	if not ctx.check(String(colony_loadout.get("weapon_id", &"")).is_empty(), "CPU colony loadout must stay unarmed"):
		return false
	if not ctx.check(colony_loadout.get("module_ids", []).has(&"repair_drone_t1"), "CPU colony loadout must carry a repair drone"):
		return false
	var colony_hull: ShipPartDefinition = SHIP_PART_CATALOG.resolve(colony_loadout.get("hull_id", &""))
	var colony_layout: Dictionary = SHIP_PART_CATALOG.slot_layout_for(colony_hull)
	var colony_drive_tally := 1 + int(colony_loadout.get("module_ids", []).count(colony_loadout.get("drive_id", &"")))
	if not ctx.check(colony_drive_tally <= int(colony_layout.get(ShipPartDefinition.SLOT_DRIVE, 1)), "CPU colony loadout must respect the hull's drive capacity"):
		return false

	return true


func ship_hull_hp(ship: ShipAssembly) -> float:
	var fleet := FleetSnapshot.new()
	fleet.faction = GameState.FACTION_PLAYER
	fleet.ships = [ship.copy()]
	fleet.calculate_stats(SHIP_PART_CATALOG)
	return fleet.total_hull_hp
