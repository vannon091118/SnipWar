class_name PreflightConstraintUpgradeCatalog
extends RefCounted

## Upgrade catalog structure: branch composition, prerequisite chains,
## exclusivity pairs, trait contracts, tint modes and per-tier visual assets.
## Pure — only reads the authored catalog, no scene boot.

const UPGRADE_CATALOG: PlanetUpgradeCatalog = preload("res://resources/config/planet_upgrade_catalog_default.tres")
const TRANSFORMER_CONFIG: TransformerConfig = preload("res://resources/config/transformer_default.tres")


func constraint_name() -> String:
	return "upgrade_catalog"


func run(ctx: PreflightContext) -> bool:
	var upgrade_catalog: PlanetUpgradeCatalog = UPGRADE_CATALOG

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

	# Defense traits carried by defensive upgrades.
	var defense_grid := upgrade_catalog.resolve(&"defense_grid")
	if not ctx.check(defense_grid != null and defense_grid.trait_definition != null and defense_grid.trait_definition.defense_rating == 5, "defense_grid should have defense_rating 5"):
		return false
	var armor_lab_upg := upgrade_catalog.resolve(&"armor_lab")
	if not ctx.check(armor_lab_upg != null and armor_lab_upg.trait_definition != null and armor_lab_upg.trait_definition.defense_rating == 6, "armor_lab should have defense_rating 6"):
		return false

	# Transformer tint modes.
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

	# Test visual assets exist for upgrades, including every authored tier.
	for up in upgrade_catalog.upgrades:
		if up == null:
			continue
		if not ctx.check(up.visual_asset != null and up.visual_assets_by_tier.size() == 3, "upgrade %s is missing its three tier visual assets" % up.id):
			return false
		for tier_asset in up.visual_assets_by_tier:
			if not ctx.check(tier_asset != null, "upgrade %s contains a null tier visual asset" % up.id):
				return false

	return true
