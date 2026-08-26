class_name PreflightConstraintLayers2And3
extends RefCounted

## Perimeter/defense slots, CompositeShipView and deterministic Layer 2/3 simulators.

func constraint_name() -> String:
	return "layers_2_and_3"

func requires_scene() -> bool:
	return true


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
	var replay_requested_kinds: Array[StringName] = []
	var replay_requested_capture: Callable = func(simulation_type, _replay):
		replay_requested_kinds.append(simulation_type as StringName)
	if conflict_manager.has_signal("replay_requested"):
		conflict_manager.connect("replay_requested", replay_requested_capture)

	var fleet_a := FleetSnapshot.new()
	fleet_a.fleet_id = &"fleet_test_a"
	fleet_a.faction = GameState.FACTION_PLAYER
	fleet_a.ships = [ctx.make_ship_assembly(&"hull_fighter", &"scanner_drone", [&"mod_laser"])]
	fleet_a.calculate_stats()
	if not ctx.check(fleet_a.total_hull_hp > 0.0 and fleet_a.total_dps > 0.0, "FleetSnapshot stat calculation failed"):
		return false

	var fleet_b := FleetSnapshot.new()
	fleet_b.fleet_id = &"fleet_test_b"
	fleet_b.faction = GameState.FACTION_CPU
	fleet_b.ships = [ctx.make_ship_assembly(&"hull_fighter", &"scanner_drone")]
	fleet_b.calculate_stats()

	# 3b. Ship-part traits feed the fleet stats used by the simulators.
	var trait_fleet := FleetSnapshot.new()
	trait_fleet.fleet_id = &"fleet_trait_readback"
	trait_fleet.faction = GameState.FACTION_PLAYER
	trait_fleet.ships = [ctx.make_ship_assembly(&"hull_fighter", &"scanner_drone", [], &"weapon_t1", &"drive_t1", &"shield_t1")]
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
	var consistency_ship: ShipAssembly = ctx.make_ship_assembly(&"hull_t2", &"scanner_t2", [&"module_reinforced"], &"weapon_t1", &"drive_t1", &"shield_t1")
	consistency_ship.drive_variant_id = &"drive_fast"
	consistency_ship.weapon_variant_id = &"weapon_precision"
	consistency_ship.shield_variant_id = &"shield_reactive"
	consistency_fleet.ships = [consistency_ship]
	consistency_fleet.calculate_stats(consistency_catalog)
	var variant_fleet := FleetSnapshot.new()
	variant_fleet.fleet_id = &"fleet_consistency_variant"
	variant_fleet.faction = GameState.FACTION_PLAYER
	var variant_ship: ShipAssembly = consistency_ship.copy()
	variant_ship.weapon_variant_id = &"weapon_burst"
	variant_ship.shield_variant_id = &"shield_lattice"
	variant_fleet.ships = [variant_ship]
	variant_fleet.calculate_stats(consistency_catalog)
	var consistency_defender := FleetSnapshot.new()
	consistency_defender.fleet_id = &"fleet_consistency_b"
	consistency_defender.faction = GameState.FACTION_CPU
	consistency_defender.ships = [ctx.make_ship_assembly(&"hull_t1", &"scanner_t1", [], &"weapon_t1", &"drive_t1", &"shield_t1")]
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
	if not ctx.check(
		consistency_spawn != null
		and consistency_spawn.ship_data.weapon_variant_id == &"weapon_precision"
		and consistency_spawn.ship_data.shield_variant_id == &"shield_reactive",
		"battle spawn event lost persisted combat variants"):
		return false
	var expected_damage_delta: float = absf(consistency_fleet.total_dps - variant_fleet.total_dps)
	var actual_damage_delta: float = absf(consistency_fire.value - variant_fire.value) if consistency_fire != null and variant_fire != null else 0.0
	if not ctx.check(
		consistency_spawn != null
		and consistency_spawn.ship_data.hull_id == &"hull_t2"
		and consistency_spawn.ship_data.drive_id == &"drive_t1"
		and consistency_spawn.ship_data.weapon_id == &"weapon_t1"
		and consistency_spawn.ship_data.shield_id == &"shield_t1"
		and consistency_spawn.ship_data.scanner_id == &"scanner_t2"
		and consistency_spawn.ship_data.module_ids.has(&"module_reinforced"),
		"battle spawn event must preserve every combat slot"):
		return false
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
	if not ctx.check(consistency_conquest.attacker_initial_hp > 0.0 and consistency_conquest.attacker_initial_dps > 0.0 and consistency_conquest.attacker_initial_hp == consistency_fleet.total_hull_hp and consistency_conquest.attacker_initial_dps == consistency_fleet.total_dps, "conquest must consume the complete FleetSnapshot combat profile"):
		return false

	# 4. Deterministic Layer 2 Simulation
	var result_1 := FleetBattleSimulator.simulate_battle(fleet_a, fleet_b, 9999)
	var result_2 := FleetBattleSimulator.simulate_battle(fleet_a, fleet_b, 9999)
	if not ctx.check(result_1.winner == result_2.winner, "FleetBattleSimulator must be deterministic"):
		return false
	if not ctx.check(result_1.events.size() == result_2.events.size(), "FleetBattleSimulator event count must match across identical seeds"):
		return false

	# 4b. Route engagement detection: shared waypoints and true crossings are
	# deterministic, while parallel routes and invalid speeds are ignored.
	var crossing_a: Array[Vector2] = [Vector2(0, 0), Vector2(100, 100)]
	var crossing_b: Array[Vector2] = [Vector2(0, 100), Vector2(100, 0)]
	var crossing := RouteEngagementResolver.detect_engagement(crossing_a, 10.0, crossing_b, 10.0)
	if not ctx.check(not crossing.is_empty() and crossing.get("type", &"") == &"path_crossing", "route resolver must detect a timed path crossing"):
		return false
	if not ctx.check(is_equal_approx(float(crossing.get("time_a", 0.0)), float(crossing.get("time_b", 0.0))), "symmetric crossing should have equal arrival times"):
		return false
	var shared := RouteEngagementResolver.detect_engagement(
		[Vector2(0, 0), Vector2(50, 0), Vector2(100, 0)],
		10.0,
		[Vector2(0, 100), Vector2(50, 0), Vector2(100, 100)],
		10.0
	)
	if not ctx.check(shared.get("type", &"") == &"waypoint_convergence", "route resolver must detect a shared waypoint"):
		return false
	var parallel := RouteEngagementResolver.detect_engagement(
		[Vector2(0, 0), Vector2(100, 0)], 10.0,
		[Vector2(0, 20), Vector2(100, 20)], 10.0
	)
	if not ctx.check(parallel.is_empty(), "parallel routes must not create an engagement"):
		return false
	if not ctx.check(RouteEngagementResolver.detect_engagement(crossing_a, 0.0, crossing_b, 10.0).is_empty(), "non-positive speed must not create an engagement"):
		return false
	var route_replay := FleetBattleSimulator.simulate_route_battle(fleet_a, fleet_b, crossing_a, crossing_b, crossing, 9999)
	if not ctx.check(route_replay.route_a.size() == 2 and route_replay.route_b.size() == 2 and route_replay.engagement_type == &"path_crossing", "route battle replay must preserve its route context"):
		return false
	var route_spawn: BattleEvent = route_replay.events[0] as BattleEvent if not route_replay.events.is_empty() else null
	if not ctx.check(route_spawn != null and route_spawn.source_pos == crossing_a[0], "route battle spawn must begin at the route origin"):
		return false

	# 4c. Route battle commit: the surviving transit stays in flight with its
	# reduced fleet while a fully destroyed transit is removed. Guards against
	# a commit that drops survivors instead of returning them to the overworld.
	var gs_route: Node = ctx.game_state
	var cycle: Node = ctx.root().get_node_or_null("GameCycleManager")
	if gs_route != null and cycle != null and gs_route.has_method("register_transit"):
		var survivor_ship: ShipAssembly = ctx.make_ship_assembly(&"hull_fighter", &"scanner_drone", [&"mod_laser"])
		var doomed_ship: ShipAssembly = ctx.make_ship_assembly(&"hull_fighter", &"scanner_drone")
		var survivor_fleet := FleetSnapshot.new()
		survivor_fleet.fleet_id = &"fleet_route_survivor"
		survivor_fleet.faction = GameState.FACTION_PLAYER
		survivor_fleet.ships = [survivor_ship, survivor_ship.copy()]
		survivor_fleet.calculate_stats()
		var doomed_fleet := FleetSnapshot.new()
		doomed_fleet.fleet_id = &"fleet_route_doomed"
		doomed_fleet.faction = GameState.FACTION_CPU
		doomed_fleet.ships = [doomed_ship]
		doomed_fleet.calculate_stats()
		var record_survivor := TransitRecord.new()
		record_survivor.transit_id = &"transit_route_survivor"
		record_survivor.fleet = survivor_fleet.copy()
		record_survivor.route_path = crossing_a
		record_survivor.duration = 10.0
		record_survivor.status = TransitRecord.STATUS_ENGAGED
		var record_doomed := TransitRecord.new()
		record_doomed.transit_id = &"transit_route_doomed"
		record_doomed.fleet = doomed_fleet.copy()
		record_doomed.route_path = crossing_b
		record_doomed.duration = 10.0
		record_doomed.status = TransitRecord.STATUS_ENGAGED
		gs_route.register_transit(record_survivor)
		gs_route.register_transit(record_doomed)

		var route_replay_commit := CombatReplay.new_battle(4242)
		route_replay_commit.winner = GameState.FACTION_PLAYER
		route_replay_commit.survivors_a = [survivor_ship.copy()]
		route_replay_commit.survivors_b = []
		route_replay_commit.route_a = crossing_a
		route_replay_commit.route_b = crossing_b
		route_replay_commit.engagement_point = Vector2(50, 50)
		route_replay_commit.engagement_type = &"path_crossing"
		route_replay_commit.engagement_time_a = 5.0
		route_replay_commit.engagement_time_b = 5.0

		var route_context := BattleContext.new()
		route_context.battle_id = &"battle_route_commit"
		route_context.transit_ids = [record_survivor.transit_id, record_doomed.transit_id]
		route_context.fleet_a = survivor_fleet.copy()
		route_context.fleet_b = doomed_fleet.copy()
		route_context.replay = route_replay_commit
		route_context.route_engagement = true

		if not ctx.check(cycle.call("apply_battle_result", route_context) == true, "route battle commit must apply"):
			return false
		var committed_survivor: TransitRecord = gs_route.call("get_transit", record_survivor.transit_id) as TransitRecord
		if not ctx.check(
			committed_survivor != null
			and committed_survivor.status == TransitRecord.STATUS_IN_FLIGHT
			and committed_survivor.fleet.ships.size() == 1,
			"route battle commit must keep the surviving transit in flight with its reduced fleet"):
			return false
		if not ctx.check(gs_route.call("get_transit", record_doomed.transit_id) == null, "route battle commit must remove a fully destroyed transit"):
			return false
		gs_route.call("remove_transit", record_survivor.transit_id)
		gs_route.call("remove_transit", record_doomed.transit_id)

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

	reinforce.ships =  [ctx.make_ship_assembly(&"hull_fighter", &"scanner_drone", [&"mod_laser"])]

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
		defender.ships = [ctx.make_ship_assembly(&"hull_fighter", &"scanner_drone")]
		defender.calculate_stats()

		var attacker := FleetSnapshot.new()
		attacker.fleet_id = &"fleet_atk"
		attacker.faction = GameState.FACTION_CPU
		attacker.source_planet_id = arrival_planet_id
		attacker.ships = [
			ctx.make_ship_assembly(&"hull_fighter", &"scanner_drone", [&"mod_laser"]),
			ctx.make_ship_assembly(&"hull_fighter", &"scanner_drone", [&"mod_laser"])
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
		if not ctx.check(replay_requested_kinds.has(&"battle"), "live fleet battle did not request visual playback via replay_requested"):
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
		attacker_only.ships = [ctx.make_ship_assembly(&"hull_fighter", &"scanner_drone", [&"mod_laser"])]
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
		# ConflictManager no longer creates inline scene children; verify via
		# signal that visual playback was requested (GameCycleManager handles
		# instantiation now).
		if not ctx.check(replay_requested_kinds.has(&"conquest"), "live conquest did not request visual playback via replay_requested"):
			return false
		# Verify the replay payload carries the planet identity for visual resolution.
		if not ctx.check(conquest_replay.planet_texture_path == conquest_target.planet_texture.resource_path, "conquest replay must preserve the stable planet texture path for visual resolution"):
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
		neutral_snap.ships = [ctx.make_ship_assembly(&"hull_fighter")]
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
		seeded.ships = [ctx.make_ship_assembly(&"hull_fighter", &"scanner_drone", [], &"weapon_t1", &"drive_t1", &"shield_t1", &"seeded_ship", &"military")]
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
