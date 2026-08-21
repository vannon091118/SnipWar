class_name PreflightConstraintUpgradesMissionsAndAi
extends RefCounted

## Upgrade catalog branches/prerequisites/traits, mission semantics, CPU dispatch
## AI, worker costs and resource generation tied to size profiles.

func constraint_name() -> String:
	return "upgrades_missions_and_ai"


func run(ctx: PreflightContext) -> bool:
	var field: Node = ctx.field
	var network: Node = ctx.network
	var manager: Node = ctx.manager
	var game_state: Node = ctx.game_state
	var world_config: WorldConfig = ctx.world_config
	var planet_catalog: PlanetCatalog = ctx.planet_catalog
	var upgrade_catalog: PlanetUpgradeCatalog = ctx.upgrade_catalog
	var ui: PlanetNetworkUI = network.get_ui()
	var transit_config: TransitConfig = manager.get("transit_config") as TransitConfig

	# --- UPGRADE SYSTEM TESTS ---
	if not ctx.check(upgrade_catalog != null and upgrade_catalog.validate().is_empty(), "upgrade catalog validation failed"):
		return false
	if not ctx.check(upgrade_catalog.upgrades.size() == 17, "upgrade catalog should have 17 upgrades"):
		return false
	var automated_mine: PlanetUpgradeDefinition = upgrade_catalog.resolve(&"automated_mine")
	var trade_hub: PlanetUpgradeDefinition = upgrade_catalog.resolve(&"trade_hub")
	var comms_array: PlanetUpgradeDefinition = upgrade_catalog.resolve(&"comms_array")
	if not ctx.check(automated_mine != null and trade_hub != null and comms_array != null, "one or more new planet upgrades are missing"):
		return false
	if not ctx.check(automated_mine.branch == &"economy" and automated_mine.parent_upgrade_id.is_empty() and automated_mine.required_technology_id == &"automated_refinery" and automated_mine.cost_resource == GameState.RES_MATERIAL and automated_mine.cost_amount == 20, "automated_mine definition does not match its economy branch contract"):
		return false
	if not ctx.check(automated_mine.trait_definition != null and is_equal_approx(automated_mine.trait_definition.production_boost, 0.4) and automated_mine.trait_definition.maintenance_cost_resource == GameState.RES_ENERGY and automated_mine.trait_definition.maintenance_cost_amount == 1, "automated_mine traits are incorrect"):
		return false
	if not ctx.check(trade_hub.branch == &"economy" and trade_hub.parent_upgrade_id.is_empty() and trade_hub.exclusive_with == &"automated_mine" and trade_hub.required_technology_id == &"bulk_processing" and trade_hub.cost_resource == GameState.RES_BIOMASS and trade_hub.cost_amount == 20, "trade_hub definition does not match its economy branch contract"):
		return false
	if not ctx.check(trade_hub.trait_definition != null and is_equal_approx(trade_hub.trait_definition.gather_income_multiplier, 1.3) and trade_hub.trait_definition.maintenance_cost_resource == GameState.RES_ENERGY and trade_hub.trait_definition.maintenance_cost_amount == 1, "trade_hub traits are incorrect"):
		return false
	if not ctx.check(comms_array.branch == &"infrastructure" and comms_array.parent_upgrade_id == &"orbital_station" and comms_array.cost_resource == GameState.RES_RARE and comms_array.cost_amount == 25 and comms_array.trait_definition != null and is_equal_approx(comms_array.trait_definition.range_bonus, 100.0) and comms_array.trait_definition.perimeter_slots_bonus == 1, "comms_array definition does not match its infrastructure branch contract"):
		return false

	# Verify 4 branches exist
	var branches: Dictionary = {}
	for up in upgrade_catalog.upgrades:
		if up != null:
			branches[up.branch] = true
	if not ctx.check(branches.has(&"economy") and branches.has(&"military") and branches.has(&"tech") and branches.has(&"infrastructure"), "all 4 upgrade branches must exist"):
		return false

	# Verify tier structure
	var economy_upgrades := upgrade_catalog.get_upgrades_for_branch(&"economy")
	var military_upgrades := upgrade_catalog.get_upgrades_for_branch(&"military")
	var tech_upgrades := upgrade_catalog.get_upgrades_for_branch(&"tech")
	var infra_upgrades := upgrade_catalog.get_upgrades_for_branch(&"infrastructure")

	if not ctx.check(economy_upgrades.size() >= 3 and military_upgrades.size() >= 4 and tech_upgrades.size() >= 3 and infra_upgrades.size() >= 3, "each branch should have multiple tiers"):
		return false

	# Test upgrade prerequisite chain: extractor -> refinery/trade_post
	var extractor := upgrade_catalog.resolve(&"extractor")
	var refinery := upgrade_catalog.resolve(&"refinery")
	var trade_post := upgrade_catalog.resolve(&"trade_post")
	if not ctx.check(extractor != null and refinery != null and trade_post != null, "core economy upgrades missing"):
		return false
	if not ctx.check(refinery.parent_upgrade_id == &"extractor" and trade_post.parent_upgrade_id == &"extractor", "economy tier 2 should require extractor"):
		return false
	if not ctx.check(refinery.exclusive_with == &"trade_post" and trade_post.exclusive_with == &"refinery", "refinery and trade_post should be mutually exclusive"):
		return false

	# Test military branch: shipyard -> colony_shipyard/war_shipyard
	var shipyard := upgrade_catalog.resolve(&"shipyard")
	var colony_shipyard := upgrade_catalog.resolve(&"colony_shipyard")
	var war_shipyard := upgrade_catalog.resolve(&"war_shipyard")
	if not ctx.check(shipyard != null and colony_shipyard != null and war_shipyard != null, "military upgrades missing"):
		return false
	if not ctx.check(colony_shipyard.parent_upgrade_id == &"shipyard" and war_shipyard.parent_upgrade_id == &"shipyard", "military tier 2 should require shipyard"):
		return false
	if not ctx.check(colony_shipyard.exclusive_with == &"war_shipyard" and war_shipyard.exclusive_with == &"colony_shipyard", "colony_shipyard and war_shipyard should be mutually exclusive"):
		return false
	if not ctx.check(war_shipyard.trait_definition != null and war_shipyard.trait_definition.cluster_tier_bonus == 1, "war_shipyard should unlock one heavier cluster tier"):
		return false

	# Test tech branch: tech_center -> weapon_lab/armor_lab
	var tech_center := upgrade_catalog.resolve(&"tech_center")
	var weapon_lab := upgrade_catalog.resolve(&"weapon_lab")
	var armor_lab := upgrade_catalog.resolve(&"armor_lab")
	if not ctx.check(tech_center != null and weapon_lab != null and armor_lab != null, "tech upgrades missing"):
		return false
	if not ctx.check(weapon_lab.parent_upgrade_id == &"tech_center" and armor_lab.parent_upgrade_id == &"tech_center", "tech tier 2 should require tech_center"):
		return false
	if not ctx.check(weapon_lab.exclusive_with == &"armor_lab" and armor_lab.exclusive_with == &"weapon_lab", "weapon_lab and armor_lab should be mutually exclusive"):
		return false
	if not ctx.check(weapon_lab.trait_definition != null and weapon_lab.trait_definition.cluster_tier_bonus == 1, "weapon_lab should unlock one heavier cluster tier"):
		return false

	# Test infrastructure branch: orbital_station -> colony_hub -> trade_network
	var orbital_station := upgrade_catalog.resolve(&"orbital_station")
	var colony_hub := upgrade_catalog.resolve(&"colony_hub")
	var trade_network := upgrade_catalog.resolve(&"trade_network")
	if not ctx.check(orbital_station != null and colony_hub != null and trade_network != null, "infrastructure upgrades missing"):
		return false
	if not ctx.check(colony_hub.parent_upgrade_id == &"orbital_station" and trade_network.parent_upgrade_id == &"colony_hub", "infrastructure chain broken"):
		return false

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

	# Test defense traits on arrival resolution
	var defense_grid := upgrade_catalog.resolve(&"defense_grid")
	if not ctx.check(defense_grid != null and defense_grid.trait_definition != null and defense_grid.trait_definition.defense_rating == 5, "defense_grid should have defense_rating 5"):
		return false
	var armor_lab_upg := upgrade_catalog.resolve(&"armor_lab")
	if not ctx.check(armor_lab_upg != null and armor_lab_upg.trait_definition != null and armor_lab_upg.trait_definition.defense_rating == 6, "armor_lab should have defense_rating 6"):
		return false

	# Test mission type constants
	if not ctx.check(GameState.MISSION_MILITARY == &"military" and GameState.MISSION_CARGO == &"cargo" and GameState.MISSION_COLONY == &"colony" and GameState.MISSION_COLLECT == &"collect", "mission type constants defined"):
		return false

	# Faction indicators must be visually distinct per faction.
	var faction_transformer_config: TransformerConfig = preload("res://resources/config/transformer_default.tres")
	if not ctx.check(faction_transformer_config.faction_player_tint != faction_transformer_config.faction_cpu_tint and faction_transformer_config.faction_player_tint != faction_transformer_config.faction_neutral_tint and faction_transformer_config.faction_cpu_tint != faction_transformer_config.faction_neutral_tint, "faction indicator colors are not distinguishable"):
		return false

	# Test transformer tint modes
	if not ctx.check(extractor.transformer_tint_mode == &"resource", "extractor should use resource tint"):
		return false
	if not ctx.check(refinery.transformer_tint_mode == &"resource", "refinery should use resource tint"):
		return false
	if not ctx.check(trade_post.transformer_tint_mode == &"faction", "trade_post should use faction tint"):
		return false
	if not ctx.check(defense_grid.transformer_tint_mode == &"faction", "defense_grid should use faction tint"):
		return false
	if not ctx.check(tech_center.transformer_tint_mode == &"faction", "tech_center should use faction tint"):
		return false
	if not ctx.check(orbital_station.transformer_tint_mode == &"faction", "orbital_station should use faction tint"):
		return false

	# Test visual assets exist for upgrades
	for up in upgrade_catalog.upgrades:
		if up != null and up.visual_asset == null:
			ctx.check(false, "upgrade %s missing visual_asset" % up.id)
			return false

	# --- MISSION SEMANTICS ---
	var mission_source: Planet = null
	var mission_cpu: Planet = null
	var mission_neutral: Planet = null
	for planet_child in field.get_children():
		if planet_child is Planet:
			match (planet_child as Planet).planet_id:
				&"ocean":
					mission_source = planet_child as Planet
				&"paper":
					mission_cpu = planet_child as Planet
				&"toxic":
					mission_neutral = planet_child as Planet
	if not ctx.check(mission_source != null and mission_cpu != null and mission_neutral != null, "mission test planets missing"):
		return false

	# Colony settles a neutral planet peacefully
	game_state.set_faction(mission_neutral.planet_id, GameState.FACTION_NEUTRAL)
	mission_neutral.unregister_workers(mission_neutral.worker_count)
	var colony_result: StringName = mission_neutral.resolve_mission(GameState.FACTION_PLAYER, 2, GameState.MISSION_COLONY)
	if not ctx.check(colony_result == Planet.ARRIVAL_SETTLED and mission_neutral.get_faction() == GameState.FACTION_PLAYER and mission_neutral.worker_count == 2, "colony mission did not settle a neutral planet"):
		return false

	# Colony on an already owned planet is rejected
	var colony_owned_result: StringName = mission_neutral.resolve_mission(GameState.FACTION_CPU, 1, GameState.MISSION_COLONY)
	if not ctx.check(colony_owned_result == Planet.ARRIVAL_REJECTED and mission_neutral.get_faction() == GameState.FACTION_PLAYER, "colony mission must be rejected on an owned planet"):
		return false

	# Cargo reinforces an own planet (resource transfer)
	game_state.set_faction(mission_source.planet_id, GameState.FACTION_PLAYER)
	var cargo_before: int = mission_source.worker_count
	var cargo_result: StringName = mission_source.resolve_mission(GameState.FACTION_PLAYER, 3, GameState.MISSION_CARGO)
	if not ctx.check(cargo_result == Planet.ARRIVAL_FRIENDLY and mission_source.worker_count == cargo_before + 3, "cargo mission did not reinforce an own planet"):
		return false

	# Cargo against an enemy planet is rejected
	var cargo_enemy_result: StringName = mission_cpu.resolve_mission(GameState.FACTION_PLAYER, 3, GameState.MISSION_CARGO)
	if not ctx.check(cargo_enemy_result == Planet.ARRIVAL_REJECTED and mission_cpu.get_faction() == GameState.FACTION_CPU, "cargo mission must be rejected against an enemy planet"):
		return false

	# Military missions keep attack semantics via resolve_arrival
	var military_result: StringName = mission_neutral.resolve_mission(GameState.FACTION_CPU, 4, GameState.MISSION_MILITARY)
	if not ctx.check(military_result == Planet.ARRIVAL_CAPTURED and mission_neutral.get_faction() == GameState.FACTION_CPU, "military mission should capture an undefended planet"):
		return false

	# --- CPU DISPATCH ---
	var cpu_homeworld: Planet = ctx.find_planet_by_id(field, game_state.homeworld_for(GameState.FACTION_CPU))
	if not ctx.check(cpu_homeworld != null, "CPU homeworld for dispatch test is missing"):
		return false
	var cpu_ai: Node = field.get_node_or_null("CpuDispatchAI")
	var cpu_dispatch_config: CpuDispatchConfig = cpu_ai.get("dispatch_config") as CpuDispatchConfig
	var cpu_workers_before: int = cpu_homeworld.worker_count
	if cpu_workers_before < cpu_dispatch_config.minimum_source_workers:
		cpu_homeworld.register_workers(cpu_dispatch_config.minimum_source_workers - cpu_workers_before)
	cpu_workers_before = cpu_homeworld.worker_count
	var manager_children_before_cpu: int = manager.get_child_count()
	var cpu_dispatched: bool = cpu_ai.call("dispatch_once", true)
	if not ctx.check(cpu_dispatched and manager.get_child_count() > manager_children_before_cpu, "CPU dispatch AI did not launch a mission"):
		return false
	var cpu_cluster: WorkerCluster = null
	for manager_child in manager.get_children():
		if manager_child is WorkerCluster:
			cpu_cluster = manager_child as WorkerCluster
			break
	if not ctx.check(cpu_cluster != null and cpu_cluster.source_faction == GameState.FACTION_CPU and cpu_cluster.mission_type == GameState.MISSION_COLONY, "CPU dispatch AI did not choose a colony mission"):
		return false
	for manager_child in manager.get_children():
		if manager_child is WorkerCluster:
			(manager_child as WorkerCluster).queue_free()
	await ctx.await_frame()
	if cpu_homeworld.worker_count < cpu_workers_before:
		cpu_homeworld.register_workers(cpu_workers_before - cpu_homeworld.worker_count)
	if not ctx.check(cpu_homeworld.worker_count == cpu_workers_before, "CPU dispatch test did not restore source workers"):
		return false

	# --- WORKER COSTS ---
	var upgrade_test_technology_catalog: TechnologyCatalog = preload("res://resources/config/technology_catalog_default.tres")
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY, 50)
	if not game_state.has_technology(GameState.FACTION_PLAYER, &"shipyard_construction"):
		if not ctx.check(game_state.research_technology(GameState.FACTION_PLAYER, &"shipyard_construction", upgrade_test_technology_catalog), "shipyard construction research should unlock the shipyard build"):
			return false
		game_state.call("advance_research", 999.0)
	var shipyard_upgrade: PlanetUpgradeDefinition = upgrade_catalog.resolve(&"shipyard")
	if not ctx.check(shipyard_upgrade != null and shipyard_upgrade.cost_workers == 2, "shipyard should cost 2 workers"):
		return false
	if not ctx.check(not game_state.can_purchase_upgrade(player_homeworld, &"shipyard", upgrade_catalog, 1), "shipyard must not be buyable with only 1 worker"):
		return false
	if not ctx.check(game_state.can_purchase_upgrade(player_homeworld, &"shipyard", upgrade_catalog, 2), "shipyard must be buyable with 2 workers"):
		return false

	# Test source traits flowing into visible dispatch tiers
	var upgrade_planet: Planet = null
	for planet_child in field.get_children():
		if planet_child is Planet and (planet_child as Planet).planet_id == player_homeworld:
			upgrade_planet = planet_child as Planet
			break
	if not ctx.check(upgrade_planet != null and upgrade_planet.get_cluster_tier_bonus() == 0, "planet cluster tier bonus should start at zero"):
		return false
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_BIOMASS, 100)
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_MATERIAL, 100)
	if not ctx.check(game_state.purchase_upgrade(player_homeworld, &"shipyard", upgrade_catalog), "shipyard purchase for tier bonus test should succeed"):
		return false
	if not ctx.check(game_state.purchase_upgrade(player_homeworld, &"war_shipyard", upgrade_catalog), "war_shipyard purchase for tier bonus test should succeed"):
		return false
	var source_tier_bonus: int = upgrade_planet.get_cluster_tier_bonus()
	if not ctx.check(source_tier_bonus == 1, "war_shipyard bonus did not reach the source planet"):
		return false
	if not ctx.check(Dispatch.cluster_tier(5, transit_config, source_tier_bonus) == &"l", "source tier bonus did not reach visible dispatch tier"):
		return false
	var bonus_route: Array[Vector2] = [upgrade_planet.global_position, mission_cpu.global_position]
	manager.call("_dispatch_clusters", upgrade_planet, mission_cpu, 1, bonus_route, GameState.MISSION_MILITARY)
	var bonus_cluster: WorkerCluster = null
	for manager_child in manager.get_children():
		if manager_child is WorkerCluster:
			bonus_cluster = manager_child as WorkerCluster
			break
	if not ctx.check(bonus_cluster != null and bonus_cluster.cluster_tier_bonus == source_tier_bonus, "worker manager did not pass the source tier bonus"):
		return false
	var bonus_sprite: Sprite2D = bonus_cluster.get_node_or_null("Sprite2D") as Sprite2D
	var expected_bonus_tier: ClusterTierDefinition = Dispatch.cluster_definition(1, transit_config, source_tier_bonus)
	if not ctx.check(bonus_sprite != null and expected_bonus_tier != null and bonus_sprite.texture == expected_bonus_tier.texture, "worker cluster did not render the bonus tier"):
		return false
	bonus_cluster.queue_free()
	await ctx.await_frame()

	# --- RESOURCE BASE FROM SIZE PROFILE ---
	var profile_base: int = 1
	if mission_source != null and mission_source.planet_id == player_homeworld:
		profile_base = mission_source.get_size_profile().resource_base
	else:
		for planet_child in field.get_children():
			if planet_child is Planet and (planet_child as Planet).planet_id == player_homeworld:
				profile_base = (planet_child as Planet).get_size_profile().resource_base
				break
	if not ctx.check(profile_base >= 1, "player homeworld size profile resource_base is invalid"):
		return false
	var base_generated: int = game_state.generate_resources_for_planet(player_homeworld, upgrade_catalog, profile_base)
	if not ctx.check(base_generated >= profile_base, "resource generation should honor the size profile resource_base (base %d, got %d)" % [profile_base, base_generated]):
		return false

	# Resetting GameState must also remove visual upgrade structures from existing planets.
	var reset_visual_planet: Planet = null
	for planet_child in field.get_children():
		if planet_child is Planet and (planet_child as Planet).planet_id == player_homeworld:
			reset_visual_planet = planet_child as Planet
			break
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
