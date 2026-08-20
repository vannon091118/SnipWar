class_name PreflightConstraintLayers2And3
extends RefCounted

## Perimeter/defense slots, CompositeShipView and deterministic Layer 2/3 simulators.

func constraint_name() -> String:
	return "layers_2_and_3"


func run(ctx: PreflightContext) -> bool:
	# 1. Perimeter Slots & Defense Range
	var test_planet: Planet = ctx.find_planet_by_id(ctx.field, ctx.game_state.homeworld_for(GameState.FACTION_PLAYER))
	if not ctx.check(test_planet != null, "player homeworld missing for perimeter check"):
		return false
	if not ctx.check(test_planet.get_perimeter_slots() >= 1, "planet perimeter slots should be at least 1"):
		return false
	if not ctx.check(test_planet.get_defense_range() >= 150.0, "planet defense range should be at least 150.0"):
		return false

	# 2. CompositeShipView
	var view := CompositeShipView.new()
	var test_tex: Texture2D = preload("res://assets/objects/workers/cluster_k.svg")
	view.setup(test_tex, test_tex, [test_tex], &"a")
	if not ctx.check(view.get_node_or_null("HullSprite") != null, "CompositeShipView missing HullSprite"):
		return false
	if not ctx.check(view.get_node_or_null("ScannerSprite") != null, "CompositeShipView missing ScannerSprite"):
		return false
	if not ctx.check(view.get_node_or_null("ModulesContainer") != null, "CompositeShipView missing ModulesContainer"):
		return false
	view.queue_free()

	# 3. FleetSnapshot & Stats
	var conflict_manager: Node = ctx.field.get_node_or_null("ConflictManager")
	if not ctx.check(conflict_manager != null and conflict_manager.has_signal("replay_started"), "ConflictManager must expose the live replay handoff"):
		return false
	var replay_kinds: Array[StringName] = []
	var replay_payloads: Dictionary = {}
	var replay_capture: Callable = func(simulation_type, replay):
		replay_kinds.append(simulation_type as StringName)
		replay_payloads[simulation_type] = replay as CombatReplay
	conflict_manager.connect("replay_started", replay_capture)

	var fleet_a := FleetSnapshot.new()
	fleet_a.fleet_id = &"fleet_test_a"
	fleet_a.faction = GameState.FACTION_PLAYER
	fleet_a.ships = [
		{"hull": &"hull_fighter", "scanner": &"scanner_drone", "modules": [&"mod_laser"]}
	]
	fleet_a.calculate_stats()
	if not ctx.check(fleet_a.total_hull_hp > 0.0 and fleet_a.total_dps > 0.0, "FleetSnapshot stat calculation failed"):
		return false

	var fleet_b := FleetSnapshot.new()
	fleet_b.fleet_id = &"fleet_test_b"
	fleet_b.faction = GameState.FACTION_CPU
	fleet_b.ships = [
		{"hull": &"hull_fighter", "scanner": &"scanner_drone", "modules": []}
	]
	fleet_b.calculate_stats()

	# 3b. Ship-part traits feed the fleet stats used by the simulators.
	var trait_fleet := FleetSnapshot.new()
	trait_fleet.fleet_id = &"fleet_trait_readback"
	trait_fleet.faction = GameState.FACTION_PLAYER
	trait_fleet.ships = [{
		"hull": &"hull_fighter",
		"drive": &"drive_t1",
		"weapon": &"weapon_t1",
		"shield": &"shield_t1",
		"scanner": &"scanner_drone",
		"modules": []
	}]
	trait_fleet.calculate_stats()
	if not ctx.check(trait_fleet.total_dps > 10.0 and trait_fleet.total_hull_hp > 50.0 and trait_fleet.speed > 0.0, "drive, weapon, and shield traits were not consumed by FleetSnapshot"):
		return false

	# 3c. Battle spawn HP and damage must agree with FleetSnapshot when all
	# combat slots and persisted variants are present. This catches the former
	# split where the battle simulator recomputed only hull/module stats.
	var consistency_catalog: ShipPartCatalog = preload("res://resources/config/ship_part_catalog_default.tres")
	var consistency_fleet := FleetSnapshot.new()
	consistency_fleet.fleet_id = &"fleet_consistency_a"
	consistency_fleet.faction = GameState.FACTION_PLAYER
	var consistency_ship: Dictionary = {
		"hull": &"hull_t2",
		"drive": &"drive_t1",
		"weapon": &"weapon_t1",
		"shield": &"shield_t1",
		"scanner": &"scanner_t2",
		"modules": [&"module_reinforced"],
		"variants": {
			&"drive": &"drive_fast",
			&"weapon": &"weapon_precision",
			&"shield": &"shield_reactive",
			&"utility": [],
		},
	}
	consistency_fleet.ships = [consistency_ship]
	consistency_fleet.calculate_stats(consistency_catalog)
	var variant_fleet := FleetSnapshot.new()
	variant_fleet.fleet_id = &"fleet_consistency_variant"
	variant_fleet.faction = GameState.FACTION_PLAYER
	var variant_ship: Dictionary = consistency_ship.duplicate(true)
	var variant_ids: Dictionary = variant_ship.get("variants", {}) as Dictionary
	variant_ids[&"weapon"] = &"weapon_burst"
	variant_ids[&"shield"] = &"shield_lattice"
	variant_ship["variants"] = variant_ids
	variant_fleet.ships = [variant_ship]
	variant_fleet.calculate_stats(consistency_catalog)
	var consistency_defender := FleetSnapshot.new()
	consistency_defender.fleet_id = &"fleet_consistency_b"
	consistency_defender.faction = GameState.FACTION_CPU
	consistency_defender.ships = [{
		"hull": &"hull_t1",
		"drive": &"drive_t1",
		"weapon": &"weapon_t1",
		"shield": &"shield_t1",
		"scanner": &"scanner_t1",
		"modules": [],
	}]
	consistency_defender.calculate_stats(consistency_catalog)
	var consistency_battle: CombatReplay = FleetBattleSimulator.simulate_battle(consistency_fleet, consistency_defender, 1818, consistency_catalog)
	var variant_battle: CombatReplay = FleetBattleSimulator.simulate_battle(variant_fleet, consistency_defender, 1818, consistency_catalog)
	var consistency_spawn: BattleEvent = null
	var consistency_fire: BattleEvent = null
	var variant_fire: BattleEvent = null
	for event_value in consistency_battle.events:
		var event: BattleEvent = event_value as BattleEvent
		if event == null:
			continue
		if event.event_type == BattleEvent.TYPE_SPAWN and event.source_id == &"a_0":
			consistency_spawn = event
		elif event.event_type == BattleEvent.TYPE_FIRE and event.source_id == &"a_0" and consistency_fire == null:
			consistency_fire = event
	for event_value in variant_battle.events:
		var event: BattleEvent = event_value as BattleEvent
		if event != null and event.event_type == BattleEvent.TYPE_FIRE and event.source_id == &"a_0":
			variant_fire = event
			break
	if not ctx.check(consistency_spawn != null and is_equal_approx(consistency_spawn.value, consistency_fleet.total_hull_hp), "battle spawn HP must match FleetSnapshot hull HP including shield/module variants"):
		return false
	var persisted_variants: Dictionary = consistency_spawn.ship_data.get("variants", {}) as Dictionary if consistency_spawn != null else {}
	if not ctx.check(persisted_variants.get(&"weapon", &"") == &"weapon_precision" and persisted_variants.get(&"shield", &"") == &"shield_reactive", "battle spawn event lost persisted combat variants"):
		return false
	var expected_damage_delta: float = absf(consistency_fleet.total_dps - variant_fleet.total_dps)
	var actual_damage_delta: float = absf(consistency_fire.value - variant_fire.value) if consistency_fire != null and variant_fire != null else 0.0
	if not ctx.check(expected_damage_delta > 0.01, "combat variant probe must change FleetSnapshot DPS"):
		return false
	if not ctx.check(actual_damage_delta > 0.01, "battle damage must change with the same weapon/shield variant change"):
		return false
	var consistency_conquest: CombatReplay = ConquestSimulator.simulate_conquest(consistency_fleet, 0, 3, 2, 2, 150.0, 1818)
	var variant_conquest: CombatReplay = ConquestSimulator.simulate_conquest(variant_fleet, 0, 3, 2, 2, 150.0, 1818)
	if not ctx.check(is_equal_approx(consistency_conquest.attacker_initial_hp, consistency_fleet.total_hull_hp), "conquest attacker HP must match FleetSnapshot hull HP"):
		return false
	if not ctx.check(is_equal_approx(consistency_conquest.attacker_initial_dps, consistency_fleet.total_dps), "conquest attacker DPS must match FleetSnapshot DPS"):
		return false
	var expected_conquest_dps_delta: float = absf(consistency_fleet.total_dps - variant_fleet.total_dps)
	var actual_conquest_dps_delta: float = absf(consistency_conquest.attacker_initial_dps - variant_conquest.attacker_initial_dps)
	if not ctx.check(expected_conquest_dps_delta > 0.01 and actual_conquest_dps_delta > 0.01, "conquest attacker stats must change with the same weapon/shield variant change"):
		return false

	# 4. Deterministic Layer 2 Simulation
	var result_1 := FleetBattleSimulator.simulate_battle(fleet_a, fleet_b, 9999)
	var result_2 := FleetBattleSimulator.simulate_battle(fleet_a, fleet_b, 9999)
	if not ctx.check(result_1.winner == result_2.winner, "FleetBattleSimulator must be deterministic"):
		return false
	if not ctx.check(result_1.events.size() == result_2.events.size(), "FleetBattleSimulator event count must match across identical seeds"):
		return false

	# 5. Deterministic Layer 3 Conquest
	var conq_1 := ConquestSimulator.simulate_conquest(fleet_a, 5, 3, 2, 2, 150.0, 777)
	var conq_2 := ConquestSimulator.simulate_conquest(fleet_a, 5, 3, 2, 2, 150.0, 777)
	if not ctx.check(conq_1.captured == conq_2.captured, "ConquestSimulator capture result must be deterministic"):
		return false
	if not ctx.check(conq_1.surviving_attackers == conq_2.surviving_attackers, "ConquestSimulator survivor count must be deterministic"):
		return false
	if not ctx.check(
		conq_1.perimeter_slots == 2 and conq_1.tower_count == 2 and conq_1.defense_range == 150.0 and conq_1.conquest_seed == 777,
		"CombatReplay must preserve the conquest inputs"):
		return false
	if not ctx.check(consistency_battle is CombatReplay and consistency_battle.is_battle() and consistency_battle.validate().is_empty(), "battle simulator must return a valid typed CombatReplay"):
		return false
	if not ctx.check(consistency_conquest is CombatReplay and consistency_conquest.is_conquest() and consistency_conquest.validate().is_empty(), "conquest simulator must return a valid typed CombatReplay"):
		return false
	var round_trip: CombatReplay = CombatReplay.from_dictionary(consistency_battle.to_dictionary())
	if not ctx.check(round_trip != null and round_trip.events.size() == consistency_battle.events.size() and round_trip.events[0].ship_data.get("hull", &"") == &"hull_t2", "CombatReplay dictionary round-trip must preserve typed battle events"):
		return false
	var replay_path := "user://preflight_combat_replay.tres"
	var save_error: Error = ResourceSaver.save(consistency_battle, replay_path)
	var loaded_replay: CombatReplay = ResourceLoader.load(replay_path) as CombatReplay
	DirAccess.remove_absolute(ProjectSettings.globalize_path(replay_path))
	if not ctx.check(save_error == OK and loaded_replay != null and loaded_replay.events.size() == consistency_battle.events.size() and loaded_replay.events[0].ship_data.get("hull", &"") == &"hull_t2", "CombatReplay must round-trip through ResourceSaver/ResourceLoader"):
		return false

	# 6. Planet.resolve_ship_arrival integrates the L2/L3 simulators into
	#    overworld arrival – FRESH same-faction reinforce registers workers,
	#    CAPTURED runs the matching simulator, REJECTED defends empty input.
	if ctx.field == null:
		if not ctx.check(false, "field missing for arrival integration test"):
			return false
		return true

	var arrival_planet_id: StringName = (ctx.game_state as Node).call("homeworld_for", GameState.FACTION_CPU) as StringName
	var arrival_planet: Planet = ctx.find_planet_by_id(ctx.field, arrival_planet_id)
	if arrival_planet == null:
		if not ctx.check(false, "cpu homeworld missing for arrival integration test"):
			return false
		return true

	# 6a. Same-faction reinforce -> ARRIVAL_FRIENDLY + registered workers
	var reinforce := FleetSnapshot.new()
	reinforce.fleet_id = &"fleet_reinforce"
	reinforce.faction = arrival_planet.get_faction()
	reinforce.source_planet_id = arrival_planet_id
	reinforce.ships = [
		{"hull": &"hull_fighter", "scanner": &"scanner_drone", "modules": [&"mod_laser"]}
	]
	reinforce.calculate_stats()
	var reinforce_result: Dictionary = arrival_planet.resolve_ship_arrival(reinforce)
	if not ctx.check(String(reinforce_result.get("result", "")) == String(Planet.ARRIVAL_FRIENDLY), "same-faction ship arrival must be FRIENDLY"):
		return false
	var reinforce_gain: int = int(reinforce_result.get("surviving_attackers", 0))
	if not ctx.check(reinforce_gain > 0, "FRIENDLY ship reinforce must register surviving attackers as workers"):
		return false

	# 6b. Enemy fleet vs defender fleet -> FleetBattleSimulator route
	var enemy_arrival_planet_id: StringName = (ctx.game_state as Node).call("homeworld_for", GameState.FACTION_PLAYER) as StringName
	var enemy_arrival_planet: Planet = ctx.find_planet_by_id(ctx.field, enemy_arrival_planet_id)
	if enemy_arrival_planet != null:
		# Defender fleet = existing player assemblies as best-effort snapshot
		var defender := FleetSnapshot.new()
		defender.fleet_id = &"fleet_def"
		defender.faction = enemy_arrival_planet.get_faction()
		defender.source_planet_id = enemy_arrival_planet_id
		defender.ships = [
			{"hull": &"hull_fighter", "scanner": &"scanner_drone", "modules": []}
		]
		defender.calculate_stats()

		var attacker := FleetSnapshot.new()
		attacker.fleet_id = &"fleet_atk"
		attacker.faction = GameState.FACTION_CPU
		attacker.source_planet_id = arrival_planet_id
		attacker.ships = [
			{"hull": &"hull_fighter", "scanner": &"scanner_drone", "modules": [&"mod_laser"]},
			{"hull": &"hull_fighter", "scanner": &"scanner_drone", "modules": [&"mod_laser"]}
		]
		attacker.calculate_stats()

		var battle_result: Dictionary = enemy_arrival_planet.resolve_ship_arrival(attacker, defender, 2024)
		var battle_outcome: String = String(battle_result.get("result", ""))
		if not ctx.check(
			battle_outcome == String(Planet.ARRIVAL_CAPTURED) or battle_outcome == String(Planet.ARRIVAL_REPELLED),
			"fleet-vs-fleet arrival must resolve through simulator (got %s)" % battle_outcome):
			return false
		if not ctx.check(replay_kinds.has(&"battle"), "live fleet battle did not hand its result to the replay layer"):
			return false
		if not ctx.check(conflict_manager.get_node_or_null("BattleReplay") is BattleScene, "fleet battle did not create a BattleScene replay"):
			return false

	# 6c. No defender fleet -> ConquestSimulator route. Use a neutral planet
	#    (not the player homeworld captured by 6b) so the destination faction
	#    does not match the attacker.
	var conquest_target: Planet = null
	for child in ctx.field.get_children():
		if child is Planet and (child as Planet).get_faction() == GameState.FACTION_NEUTRAL:
			conquest_target = child as Planet
			break
	if conquest_target != null:
		var attacker_only := FleetSnapshot.new()
		attacker_only.fleet_id = &"fleet_atk_only"
		attacker_only.faction = GameState.FACTION_CPU
		attacker_only.source_planet_id = arrival_planet_id
		attacker_only.ships = [
			{"hull": &"hull_fighter", "scanner": &"scanner_drone", "modules": [&"mod_laser"]}
		]
		attacker_only.calculate_stats()
		var conquest_result: Dictionary = conquest_target.resolve_ship_arrival(attacker_only, null, 0, 1234)
		var conquest_outcome: String = String(conquest_result.get("result", ""))
		if not ctx.check(
			conquest_outcome == String(Planet.ARRIVAL_CAPTURED) or conquest_outcome == String(Planet.ARRIVAL_REPELLED),
			"fleet-vs-ground arrival must resolve through ConquestSimulator (got %s)" % conquest_outcome):
			return false
		if not ctx.check(replay_kinds.has(&"conquest"), "live conquest did not hand its result to the replay layer"):
			return false
		var conquest_replay: CombatReplay = replay_payloads.get(&"conquest") as CombatReplay
		if not ctx.check(conquest_replay != null and conquest_replay.planet_id == conquest_target.planet_id, "conquest replay must identify the attacked planet"):
			return false
		if not ctx.check(conquest_replay.planet_texture_path == conquest_target.planet_texture.resource_path, "conquest replay must preserve the stable planet texture path"):
			return false
		# ConflictManager may have queued the previous replay for deletion; a
		# name lookup can then return that stale node while the new replay is
		# already active. Assert against the manager's current typed reference.
		var live_conquest: ConquestScene = conflict_manager.get("_conquest_replay") as ConquestScene
		var rendered_texture: Texture2D = live_conquest._planet_sprite.texture if live_conquest != null and live_conquest._planet_sprite != null else null
		var rendered_path: String = rendered_texture.resource_path if rendered_texture != null else ""
		var target_path: String = conquest_target.planet_texture.resource_path if conquest_target.planet_texture != null else ""
		if not ctx.check(live_conquest != null and rendered_texture != null and rendered_path == target_path, "conquest replay must resolve the attacked planet visual from its stable identity"):
			return false
		if not ctx.check(live_conquest != null and is_instance_valid(live_conquest), "fleet conquest did not create a ConquestScene replay"):
			return false

	# 6d. Empty/defensive inputs -> REJECTED untouched
	var rejection_planet_id: StringName = (ctx.game_state as Node).call("homeworld_for", GameState.FACTION_NEUTRAL) as StringName
	var rejection_planet: Planet = ctx.find_planet_by_id(ctx.field, rejection_planet_id)
	if rejection_planet != null:
		var pre_faction: StringName = rejection_planet.get_faction()
		var empty_result: Dictionary = rejection_planet.resolve_ship_arrival(null)
		if not ctx.check(String(empty_result.get("result", "")) == String(Planet.ARRIVAL_REJECTED), "null fleet must be REJECTED"):
			return false
		if not ctx.check(rejection_planet.get_faction() == pre_faction, "REJECTED arrival must not change faction"):
			return false

		var neutral_snap := FleetSnapshot.new()
		neutral_snap.fleet_id = &"fleet_neutral"
		neutral_snap.faction = GameState.FACTION_NEUTRAL
		neutral_snap.ships = [{"hull": &"hull_fighter"}]
		neutral_snap.calculate_stats()
		var neutral_result: Dictionary = rejection_planet.resolve_ship_arrival(neutral_snap)
		if not ctx.check(String(neutral_result.get("result", "")) == String(Planet.ARRIVAL_REJECTED), "neutral-faction fleet must be REJECTED"):
			return false

	# 7. Worker military arrivals use the ConquestSimulator adapter. Assemblies
	#    remain in the source inventory because no ship was explicitly launched.
	var neutral_home_id: StringName = (ctx.game_state as Node).call("homeworld_for", GameState.FACTION_NEUTRAL) as StringName
	var draft_source_id: StringName = (ctx.game_state as Node).call("homeworld_for", GameState.FACTION_CPU) as StringName
	var draft_source: Planet = ctx.find_planet_by_id(ctx.field, draft_source_id)
	if draft_source != null:
		var seeded := FleetSnapshot.new()
		seeded.fleet_id = &"fleet_seeded"
		seeded.faction = draft_source.get_faction()
		seeded.source_planet_id = draft_source_id
		seeded.ships = [{
			"hull": &"hull_fighter",
			"drive": &"drive_t1",
			"weapon": &"weapon_t1",
			"shield": &"shield_t1",
			"scanner": &"scanner_drone",
			"modules": [],
		}]
		seeded.calculate_stats()
		(ctx.game_state as Node).call("disband_fleet_to_planet", seeded, draft_source_id)
		if not ctx.check(int((ctx.game_state as Node).get_ship_assemblies(draft_source_id).size()) == 1, "seeded assembly did not land on the source"):
			return false
		var draft_target: Planet = null
		for child in ctx.field.get_children():
			if child is Planet and (child as Planet).get_faction() == GameState.FACTION_NEUTRAL and (child as Planet).planet_id != neutral_home_id and child != draft_source:
				draft_target = child as Planet
				break
		if draft_target != null:
			var conquest_replays_before: int = replay_kinds.count(&"conquest")
			var draft_result: StringName = draft_target.resolve_military_arrival(draft_source.get_faction(), 4, draft_source_id)
			if not ctx.check(
				String(draft_result) == String(Planet.ARRIVAL_CAPTURED) or String(draft_result) == String(Planet.ARRIVAL_REPELLED),
				"worker military arrival must resolve through ConquestSimulator (got %s)" % draft_result):
				return false
			if not ctx.check((ctx.game_state as Node).get_ship_assemblies(draft_source_id).size() == 1, "worker military arrival consumed an unlaunched source assembly"):
				return false
			if not ctx.check(replay_kinds.count(&"conquest") > conquest_replays_before, "worker military arrival did not start a conquest replay"):
				return false

	# 7b. An assembly-less worker military arrival uses the same conquest adapter.
	var fallback_target: Planet = null
	for child in ctx.field.get_children():
		if child is Planet and (child as Planet).get_faction() == GameState.FACTION_NEUTRAL and (child as Planet).planet_id != neutral_home_id:
			fallback_target = child as Planet
			break
	if fallback_target != null:
		fallback_target.unregister_workers(fallback_target.worker_count)
		var fallback_result: StringName = fallback_target.resolve_military_arrival(GameState.FACTION_CPU, 4, &"")
		if not ctx.check(String(fallback_result) == String(Planet.ARRIVAL_CAPTURED), "assembly-less worker military arrival should capture through conquest (got %s)" % fallback_result):
			return false

	return true
