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
	var replay_capture: Callable = func(simulation_type, result):
		replay_kinds.append(simulation_type as StringName)
		replay_payloads[simulation_type] = result as Dictionary
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

	# 4. Deterministic Layer 2 Simulation
	var result_1 := FleetBattleSimulator.simulate_battle(fleet_a, fleet_b, 9999)
	var result_2 := FleetBattleSimulator.simulate_battle(fleet_a, fleet_b, 9999)
	if not ctx.check(result_1.get("winner") == result_2.get("winner"), "FleetBattleSimulator must be deterministic"):
		return false
	if not ctx.check(result_1.get("events").size() == result_2.get("events").size(), "FleetBattleSimulator event count must match across identical seeds"):
		return false

	# 5. Deterministic Layer 3 Conquest
	var conq_1 := ConquestSimulator.simulate_conquest(fleet_a, 5, 3, 2, 2, 150.0, 777)
	var conq_2 := ConquestSimulator.simulate_conquest(fleet_a, 5, 3, 2, 2, 150.0, 777)
	if not ctx.check(conq_1.get("captured") == conq_2.get("captured"), "ConquestSimulator capture result must be deterministic"):
		return false
	if not ctx.check(conq_1.get("surviving_attackers") == conq_2.get("surviving_attackers"), "ConquestSimulator survivor count must be deterministic"):
		return false
	if not ctx.check(
		conq_1.get("perimeter_slots") == 2 and conq_1.get("tower_count") == 2 and conq_1.get("defense_range") == 150.0 and conq_1.get("conquest_seed") == 777,
		"ConquestResult must preserve the replay inputs"):
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
		var conquest_replay: Dictionary = replay_payloads.get(&"conquest", {}) as Dictionary
		if not ctx.check(conquest_replay.get("planet_id") == conquest_target.planet_id, "conquest replay must identify the attacked planet"):
			return false
		if not ctx.check(conquest_replay.get("planet_texture") == conquest_target.planet_texture, "conquest replay must carry the attacked planet visual"):
			return false
		if not ctx.check(conflict_manager.get_node_or_null("ConquestReplay") is ConquestScene, "fleet conquest did not create a ConquestScene replay"):
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
