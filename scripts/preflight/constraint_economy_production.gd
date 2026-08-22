class_name PreflightConstraintEconomyProduction
extends RefCounted

## Upgrade purchase cycles, trait-driven resource generation, maintenance,
## refinery conversion, size-profile resource base and upgrade-structure reset.

func constraint_name() -> String:
	return "economy_production"


func run(ctx: PreflightContext) -> bool:
	var field: Node = ctx.field
	var game_state: Node = ctx.game_state
	var world_config: WorldConfig = ctx.world_config
	var planet_catalog: PlanetCatalog = ctx.planet_catalog
	var upgrade_catalog: PlanetUpgradeCatalog = ctx.upgrade_catalog

	# The gather-income trait is consumed by the persistent gathering path, not
	# just displayed on the upgrade card.
	var gather_probe: EconomyDomain = EconomyDomain.new()
	gather_probe.reset()
	gather_probe.set_planet_resource(&"gather_probe", GameState.RES_MATERIAL)
	gather_probe.planet_upgrades[&"gather_probe"] = [&"trade_hub"]
	gather_probe.gathering_workers[GameState.FACTION_PLAYER] = {&"gather_probe": 10}
	var gather_amount: int = gather_probe.gather_income_tick({&"gather_probe": 1}, upgrade_catalog)
	if not ctx.check(gather_amount == 13, "trade_hub gather-income trait should turn 10 base workers into 13 gathered resources"):
		return false

	# Test can_purchase_upgrade logic
	var player_homeworld: StringName = game_state.homeworld_for(GameState.FACTION_PLAYER)
	if not ctx.check(not String(player_homeworld).is_empty(), "player homeworld missing"):
		return false

	# Capture initial resources before purchases
	var initial_energy: int = game_state.get_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY)
	var initial_material: int = game_state.get_faction_resource(GameState.FACTION_PLAYER, GameState.RES_MATERIAL)

	# Initially can buy extractor (tier 1, no parent)
	if not ctx.check(game_state.can_purchase_upgrade(player_homeworld, &"extractor", upgrade_catalog), "should be able to buy extractor initially"):
		return false

	# Cannot buy refinery without extractor
	if not ctx.check(not game_state.can_purchase_upgrade(player_homeworld, &"refinery", upgrade_catalog), "should not buy refinery without extractor"):
		return false

	# Buy extractor
	if not ctx.check(game_state.purchase_upgrade(player_homeworld, &"extractor", upgrade_catalog), "purchase extractor should succeed"):
		return false

	# Now can buy refinery or trade_post
	if not ctx.check(game_state.can_purchase_upgrade(player_homeworld, &"refinery", upgrade_catalog), "should be able to buy refinery after extractor"):
		return false
	if not ctx.check(game_state.can_purchase_upgrade(player_homeworld, &"trade_post", upgrade_catalog), "should be able to buy trade_post after extractor"):
		return false

	# Buy refinery
	if not ctx.check(game_state.purchase_upgrade(player_homeworld, &"refinery", upgrade_catalog), "purchase refinery should succeed"):
		return false

	# After buying refinery, cannot buy trade_post (exclusive)
	if not ctx.check(not game_state.can_purchase_upgrade(player_homeworld, &"trade_post", upgrade_catalog), "should not buy trade_post after refinery (exclusive)"):
		return false

	# Verify resource deduction
	# Extractor costs 15 energy, refinery costs 25 material
	if not ctx.check(game_state.get_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY) == initial_energy - 15, "extractor should cost 15 energy"):
		return false
	if not ctx.check(game_state.get_faction_resource(GameState.FACTION_PLAYER, GameState.RES_MATERIAL) == initial_material - 25, "refinery should cost 25 material"):
		return false

	# Verify upgrades recorded
	var hw_upgrades: Array[StringName] = game_state.get_planet_upgrades(player_homeworld)
	if not ctx.check(hw_upgrades.size() == 2 and hw_upgrades.has(&"extractor") and hw_upgrades.has(&"refinery"), "upgrades should be recorded on planet"):
		return false

	# Test trait effects on resource generation
	# Extractor gives +50% production_boost, refinery gives +100% but -2 energy maintenance.
	game_state.call("deal_resources", planet_catalog, preload("res://resources/config/resource_pool_default.tres"), world_config.layout_seed)
	var energy_before_generation: int = game_state.get_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY)
	var generated_resource: StringName = game_state.resource_of(player_homeworld)
	var floating_before := 0
	for field_child in field.get_children():
		if field_child is FloatingText:
			floating_before += 1
	var generated: int = game_state.generate_resources_for_planet(player_homeworld, upgrade_catalog)
	var floating_after := 0
	for field_child in field.get_children():
		if field_child is FloatingText:
			floating_after += 1
	if not ctx.check(floating_after > floating_before, "economy resource generation did not create floating feedback"):
		return false
	for field_child in field.get_children():
		if field_child is FloatingText:
			field.remove_child(field_child)
			field_child.queue_free()
	# Base 1 * (1 + 0.5 + 1.0) = 2.5 -> 2; the generated resource may itself be energy.
	if not ctx.check(generated >= 2, "resource generation with traits should apply production boost"):
		return false

	# Verify maintenance cost was deducted without assuming the homeworld's dealt resource.
	var energy_after_gen: int = game_state.get_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY)
	var expected_energy_after_generation: int = energy_before_generation - 2
	if generated_resource == GameState.RES_ENERGY:
		expected_energy_after_generation += generated
	if not ctx.check(energy_after_gen == expected_energy_after_generation, "maintenance cost should be deducted during generation"):
		return false

	# Test refinery conversion logic
	var pre_conv_mat: int = game_state.get_faction_resource(GameState.FACTION_PLAYER, GameState.RES_MATERIAL)
	var pre_conv_energy: int = game_state.get_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY)
	var pre_conv_rare: int = game_state.get_faction_resource(GameState.FACTION_PLAYER, GameState.RES_RARE)
	var conv_result: Dictionary = game_state.convert_refinery_resources(player_homeworld)
	if not ctx.check(conv_result.get("converted", false) == true, "refinery conversion should succeed with sufficient material and energy"):
		return false
	if not ctx.check(game_state.get_faction_resource(GameState.FACTION_PLAYER, GameState.RES_MATERIAL) == pre_conv_mat - 2, "refinery conversion should consume 2 material"):
		return false
	if not ctx.check(game_state.get_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY) == pre_conv_energy - 1, "refinery conversion should consume 1 energy"):
		return false
	if not ctx.check(game_state.get_faction_resource(GameState.FACTION_PLAYER, GameState.RES_RARE) == pre_conv_rare + 1, "refinery conversion should produce 1 rare"):
		return false

	# --- RESOURCE BASE FROM SIZE PROFILE ---
	var profile_planet: Planet = ctx.find_planet_by_id(field, player_homeworld)
	var profile_base: int = profile_planet.get_size_profile().resource_base if profile_planet != null else 1
	if not ctx.check(profile_base >= 1, "player homeworld size profile resource_base is invalid"):
		return false
	var base_generated: int = game_state.generate_resources_for_planet(player_homeworld, upgrade_catalog, profile_base)
	if not ctx.check(base_generated >= profile_base, "resource generation should honor the size profile resource_base (base %d, got %d)" % [profile_base, base_generated]):
		return false

	# Resetting GameState must also remove visual upgrade structures from existing planets.
	var reset_visual_planet: Planet = ctx.find_planet_by_id(field, player_homeworld)
	if not ctx.check(reset_visual_planet != null, "planet for upgrade structure reset test is missing"):
		return false
	var reset_details: PlanetDetails = reset_visual_planet.get_node_or_null("PlanetDetails") as PlanetDetails
	if not ctx.check(reset_details != null and reset_details.get_node_or_null("UpgradeStructure_extractor") != null, "upgrade structure was not created before reset"):
		return false
	game_state.reset_from_catalog(planet_catalog)
	if not ctx.check(reset_details.get_node_or_null("UpgradeStructure_extractor") == null, "GameState reset left a stale upgrade structure"):
		return false
	if not ctx.check(game_state.purchase_upgrade(player_homeworld, &"extractor", upgrade_catalog), "upgrade could not be repurchased after reset"):
		return false
	if not ctx.check(reset_details.get_node_or_null("UpgradeStructure_extractor") != null, "upgrade structure was not recreated in the same frame"):
		return false
	return true
