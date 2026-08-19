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

	return true
