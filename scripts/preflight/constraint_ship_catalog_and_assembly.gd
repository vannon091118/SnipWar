class_name PreflightConstraintShipCatalogAndAssembly
extends RefCounted

## Ship part catalog branches, tech-gated purchases, timed assembly/disassembly,
## variant determinism, composite overlays and the weapon slot tech gate.

func constraint_name() -> String:
	return "ship_catalog_and_assembly"


func run(ctx: PreflightContext) -> bool:
	var field: Node = ctx.field
	var game_state: Node = ctx.game_state
	var ui_theme_config: UIThemeConfig = ctx.network.get("ui_theme_config") as UIThemeConfig
	var ship_manager: ShipManager = field.get_node_or_null("ShipManager") as ShipManager
	if not ctx.check(ship_manager != null, "ShipManager runtime module is missing"):
		return false
	var catalog: ShipPartCatalog = ship_manager.get_part_catalog()
	if not ctx.check(catalog != null and catalog.validate().is_empty(), "ship part catalog validation failed"):
		return false
	var ship_asset_contract_valid := true
	for part in catalog.parts:
		if part == null:
			ship_asset_contract_valid = false
			continue
		if part.visual_asset == null:
			ship_asset_contract_valid = false
		for variant in part.variant_pool:
			if variant == null or variant.visual_asset == null:
				ship_asset_contract_valid = false
	if not ctx.check(ship_asset_contract_valid, "ship part catalog contains a part or variant without a graphical asset"):
		return false
	if not ctx.check(
		not catalog.for_slot(ShipPartDefinition.SLOT_HULL).is_empty()
		and not catalog.for_slot(ShipPartDefinition.SLOT_DRIVE).is_empty()
		and not catalog.for_slot(ShipPartDefinition.SLOT_WEAPON).is_empty()
		and not catalog.for_slot(ShipPartDefinition.SLOT_SHIELD).is_empty()
		and not catalog.for_slot(ShipPartDefinition.SLOT_SCANNER).is_empty()
		and not catalog.for_slot(ShipPartDefinition.SLOT_MODULE).is_empty(),
		"ship part catalog is missing a hull, drive, weapon, shield, scanner, or module branch"):
		return false
	var scanner_t2: ShipPartDefinition = catalog.resolve(&"scanner_t2")
	var reactor_module: ShipPartDefinition = catalog.resolve(&"module_reactor")
	var reinforced_module: ShipPartDefinition = catalog.resolve(&"module_reinforced")
	var sensor_array_module: ShipPartDefinition = catalog.resolve(&"module_sensor_array")
	if not ctx.check(scanner_t2 != null and reactor_module != null and reinforced_module != null and sensor_array_module != null, "one or more branching ship parts are missing"):
		return false
	if not ctx.check(scanner_t2.slot_type == ShipPartDefinition.SLOT_SCANNER and scanner_t2.tier == 2 and scanner_t2.required_tech_id == &"deep_scan" and scanner_t2.cost_resource == GameState.RES_ENERGY and scanner_t2.cost_amount == 12, "scanner_t2 definition does not match the deep-scan branch contract"):
		return false
	if not ctx.check(reactor_module.required_tech_id == &"advanced_propulsion" and reactor_module.cost_resource == GameState.RES_VOLATILE and reactor_module.cost_amount == 8 and reactor_module.trait_definition != null and is_equal_approx(reactor_module.trait_definition.transfer_speed_multiplier, 1.1), "module_reactor definition does not match the advanced-propulsion branch contract"):
		return false
	if not ctx.check(reinforced_module.required_tech_id == &"heavy_armor_plating" and reinforced_module.cost_resource == GameState.RES_MATERIAL and reinforced_module.cost_amount == 8 and reinforced_module.trait_definition != null and reinforced_module.trait_definition.hull_hp_bonus == 15, "module_reinforced definition does not match the heavy-armor branch contract"):
		return false
	if not ctx.check(sensor_array_module.required_tech_id == &"long_range_sensors" and sensor_array_module.cost_resource == GameState.RES_RARE and sensor_array_module.cost_amount == 8 and sensor_array_module.trait_definition != null and is_equal_approx(sensor_array_module.trait_definition.range_bonus, 40.0), "module_sensor_array definition does not match the long-range branch contract"):
		return false
	var colony_module: ShipPartDefinition = catalog.resolve(&"colony_module")
	var transport_module: ShipPartDefinition = catalog.resolve(&"transport_module")
	var science_module: ShipPartDefinition = catalog.resolve(&"science_module")
	var defense_module: ShipPartDefinition = catalog.resolve(&"defense_module")
	if not ctx.check(colony_module != null and transport_module != null and science_module != null and defense_module != null and colony_module.module_role == "colony" and transport_module.module_role == "transport" and science_module.module_role == "research" and defense_module.module_role == "military", "canonical role modules are missing or have invalid roles"):
		return false
	var role_probe := ShipAssembly.new()
	role_probe.weapon_id = &""
	role_probe.set_module_ids([transport_module.id])
	if not ctx.check(ShipAssembly.derive_role_from_modules(role_probe, catalog) == &"transport", "transport module should derive the transport role"):
		return false
	role_probe.set_module_ids([colony_module.id, science_module.id])
	if not ctx.check(ShipAssembly.derive_role_from_modules(role_probe, catalog) == &"colony", "role derivation should prioritize colony modules"):
		return false
	if not ctx.check(ctx.fixture.prepare_ship_builder(), "ship-builder fixture could not prepare the shipyard prerequisite"):
		return false
	await ctx.await_frame()
	var source: Planet = ctx.find_planet_by_id(field, game_state.homeworld_for(GameState.FACTION_PLAYER) as StringName)
	if not ctx.check(source != null and game_state.has_planet_upgrade(source.planet_id, ShipManager.SHIPYARD_UPGRADE_ID), "player homeworld should carry a shipyard before the ship builder runs"):
		return false
	var hull_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_HULL)[0]
	var drive_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_DRIVE)[0]
	var weapon_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_WEAPON)[0]
	var shield_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_SHIELD)[0]
	var scanner_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_SCANNER)[0]
	var module_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_MODULE)[0]
	if not ctx.check(drive_part.trait_definition != null and weapon_part.trait_definition != null and shield_part.trait_definition != null, "drive, weapon, and shield parts must carry trait definitions"):
		return false
	# --- PACING: hull carries the tier base; weapon and modules extend it ---
	var hull_t2: ShipPartDefinition = catalog.resolve(&"hull_t2")
	var hull_t3: ShipPartDefinition = catalog.resolve(&"hull_t3")
	if not ctx.check(
		hull_part.build_time == 63.0
		and hull_t2 != null and hull_t2.build_time == 123.0
		and hull_t3 != null and hull_t3.build_time == 183.0
		and weapon_part.build_time == 15.0
		and drive_part.build_time == 6.0
		and shield_part.build_time == 6.0
		and module_part.build_time == 10.0,
		"build time should scale with hull tier (63/123/183s) plus ship components"):
		return false
	if not ctx.check(not catalog.for_slot(ShipPartDefinition.SLOT_UTILITY).is_empty(), "ship part catalog is missing the utility slot"):
		return false
	var blueprint: ShipBlueprint = catalog.default_blueprint()
	if not ctx.check(blueprint != null and blueprint.validate().is_empty(), "default ship blueprint is missing or invalid"):
		return false
	var first_variant: ShipComponentVariant = catalog.select_variant(drive_part, blueprint, 7, drive_part.tier, &"drive")
	var repeat_variant: ShipComponentVariant = catalog.select_variant(drive_part, blueprint, 7, drive_part.tier, &"drive")
	if not ctx.check(first_variant != null and repeat_variant != null and first_variant.id == repeat_variant.id, "variant selection must be deterministic for identical blueprint and instance seeds"):
		return false
	var variant_changed: bool = false
	for seed in range(8, 32):
		var candidate: ShipComponentVariant = catalog.select_variant(drive_part, blueprint, seed, drive_part.tier, &"drive")
		if candidate != null and candidate.id != first_variant.id:
			variant_changed = true
			break
	if not ctx.check(variant_changed, "variant selection should expose seed-based instance variation"):
		return false
	if not ctx.check(catalog.combined_trait(drive_part, first_variant) != null, "variant trait merge returned no drive trait"):
		return false
	var weapon_variant: ShipComponentVariant = catalog.select_variant(weapon_part, blueprint, 7, weapon_part.tier, &"weapon")
	var shield_variant: ShipComponentVariant = catalog.select_variant(shield_part, blueprint, 7, shield_part.tier, &"shield")
	if not ctx.check(weapon_variant != null and shield_variant != null, "weapon and shield variants should be selectable"):
		return false
	var overlay_variants: Dictionary = {
		&"drive": first_variant,
		&"weapon": weapon_variant,
		&"shield": shield_variant,
	}

	var build_view: CompositeShipView = CompositeShipView.new()
	var build_modules: Array[ShipPartDefinition] = [module_part]
	build_view.setup_from_parts(hull_part, scanner_part, drive_part, weapon_part, shield_part, build_modules, GameState.FACTION_PLAYER, null, overlay_variants)
	if not ctx.check(build_view.get_node_or_null("EngineOverlay").visible, "CompositeShipView did not render the drive overlay"):
		return false
	if not ctx.check(build_view.get_node_or_null("WeaponOverlay").visible, "CompositeShipView did not render the weapon overlay"):
		return false
	if not ctx.check(build_view.get_node_or_null("ShieldOverlay").visible, "CompositeShipView did not render the shield overlay"):
		return false
	if not ctx.check(not String(build_view.get_node_or_null("EngineOverlay").get_meta("trait_id", "")).is_empty(), "engine overlay lost its trait readback metadata"):
		return false
	if not ctx.check(not String(build_view.get_node_or_null("WeaponOverlay").get_meta("trait_id", "")).is_empty(), "weapon overlay lost its trait readback metadata"):
		return false
	if not ctx.check(not String(build_view.get_node_or_null("ShieldOverlay").get_meta("trait_id", "")).is_empty(), "shield overlay lost its trait readback metadata"):
		return false
	if not ctx.check(String(build_view.get_node_or_null("EngineOverlay").get_meta("variant_id", "")) == String(first_variant.id), "engine overlay did not retain the selected variant"):
		return false
	if not ctx.check(String(build_view.get_node_or_null("WeaponOverlay").get_meta("variant_id", "")) == String(weapon_variant.id), "weapon overlay did not retain the selected variant"):
		return false
	if not ctx.check(String(build_view.get_node_or_null("ShieldOverlay").get_meta("variant_id", "")) == String(shield_variant.id), "shield overlay did not retain the selected variant"):
		return false
	build_view.queue_free()

	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_MATERIAL, 100)
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY, 100)
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_VOLATILE, 100)

	if not ctx.check(ship_manager.can_buy_part(source, hull_part.id), "hull part should be purchasable"):
		return false
	if not ctx.check(ship_manager.buy_part(source, hull_part.id), "hull part purchase should succeed"):
		return false
	if not ctx.check(ship_manager.buy_part(source, scanner_part.id), "scanner part purchase should succeed"):
		return false
	if not ctx.check(ship_manager.buy_part(source, module_part.id), "module part purchase should succeed"):
		return false
	if not ctx.check(ship_manager.buy_part(source, drive_part.id), "drive part purchase should succeed"):
		return false
	if not ctx.check(ship_manager.buy_part(source, shield_part.id), "shield part purchase should succeed"):
		return false
	if not ctx.check(
		game_state.get_ship_part_count(source.planet_id, hull_part.id) == 1
		and game_state.get_ship_part_count(source.planet_id, scanner_part.id) == 1
		and game_state.get_ship_part_count(source.planet_id, module_part.id) == 1
		and game_state.get_ship_part_count(source.planet_id, drive_part.id) == 1
		and game_state.get_ship_part_count(source.planet_id, shield_part.id) == 1,
		"purchased parts were not recorded in the inventory"):
		return false

	if not ctx.check(not game_state.can_assemble_ship(source.planet_id, hull_part.id, scanner_part.id, [module_part.id, module_part.id], catalog, &"", drive_part.id, shield_part.id), "assembling beyond module ownership should be rejected"):
		return false
	if not ctx.check(not game_state.can_assemble_ship(source.planet_id, hull_part.id, scanner_part.id, [], catalog, &"", &"", shield_part.id), "assembly without a drive must be rejected"):
		return false
	if not ctx.check(not game_state.can_assemble_ship(source.planet_id, hull_part.id, scanner_part.id, [], catalog, &"", drive_part.id, &""), "assembly without a shield must be rejected"):
		return false
	var ship_id: StringName = ship_manager.assemble_ship(source, hull_part.id, scanner_part.id, [module_part.id], &"", drive_part.id, shield_part.id)
	if not ctx.check(not String(ship_id).is_empty(), "ship assembly did not start (ship_id=%s)" % ship_id):
		return false
	if not ctx.check(game_state.call("ship_build_in_progress", source.planet_id, ship_id), "timed ship build was not queued"):
		return false
	var build_network: Node = field.get_node_or_null("PlanetNetwork")
	var build_menu: TechnologyMenu = build_network.get_technology_menu() as TechnologyMenu if build_network != null and build_network.has_method("get_technology_menu") else null
	if not ctx.check(build_menu != null, "technology menu is missing for ship-build progress feedback"):
		return false
	build_menu.set("_category", TechnologyDefinition.CATEGORY_SHIPS)
	build_menu.call("_set_open", true)
	build_menu.call("_refresh")
	await ctx.await_frame()
	var build_list: VBoxContainer = build_menu.get_node_or_null("TechTabUI/TechPanel/TechMargin/TechVBox/TechScroll/TechList") as VBoxContainer
	var hangar_backdrop: TextureRect = build_list.find_child("ShipHangarBackdrop", true, false) as TextureRect if build_list != null else null
	if not ctx.check(hangar_backdrop != null and ui_theme_config != null and hangar_backdrop.texture == ui_theme_config.ship_hangar_background_texture, "ship hangar background asset was not retained during builder refresh"):
		return false
	var build_progress_visible := false
	if build_list != null:
		for progress_node in build_list.find_children("ShipBuildProgress", "ProgressBar", true, false):
			var build_progress: ProgressBar = progress_node as ProgressBar
			if build_progress != null and build_progress.visible and build_progress.max_value > 0.0 and build_progress.value < build_progress.max_value:
				build_progress_visible = true
				break
	if not ctx.check(build_progress_visible, "active ship build did not render a visible progress bar"):
		return false
	build_menu.close()
	if not ctx.check(not game_state.has_ship_assembly(source.planet_id, ship_id), "ship build should not register before the timer completes"):
		return false
	var build_remaining: float = game_state.ship_build_remaining(source.planet_id, ship_id)
	if not ctx.check(build_remaining > 63.0, "complete T1 loadout should take its hull base plus component assembly time"):
		return false
	game_state.call("advance_builds", 999.0)
	if not ctx.check(game_state.has_ship_assembly(source.planet_id, ship_id), "ship assembly did not register after the build timer (ship_id=%s)" % ship_id):
		return false
	if not ctx.check(
		game_state.get_ship_part_count(source.planet_id, hull_part.id) == 0
		and game_state.get_ship_part_count(source.planet_id, scanner_part.id) == 0
		and game_state.get_ship_part_count(source.planet_id, module_part.id) == 0
		and game_state.get_ship_part_count(source.planet_id, drive_part.id) == 0
		and game_state.get_ship_part_count(source.planet_id, shield_part.id) == 0,
		"ship assembly did not consume the parts"):
		return false
	var hangar: ShipyardHangar = source.get_node_or_null("PlanetDetails/UpgradeStructure_shipyard/Hangar") as ShipyardHangar
	var builder_node: Node2D = hangar.get_node_or_null("FutureShipBuilder") as Node2D if hangar != null else null
	if not ctx.check(builder_node != null and builder_node.visible, "assembled ship did not reveal the FutureShipBuilder display"):
		return false

	if not ctx.check(ship_manager.disassemble_ship(source, ship_id), "ship disassembly should succeed"):
		return false
	if not ctx.check(not game_state.has_ship_assembly(source.planet_id, ship_id), "disassembled ship should be removed"):
		return false
	if not ctx.check(
		game_state.get_ship_part_count(source.planet_id, hull_part.id) == 1
		and game_state.get_ship_part_count(source.planet_id, scanner_part.id) == 1
		and game_state.get_ship_part_count(source.planet_id, module_part.id) == 1
		and game_state.get_ship_part_count(source.planet_id, drive_part.id) == 1
		and game_state.get_ship_part_count(source.planet_id, shield_part.id) == 1,
		"disassembly did not refund the parts"):
		return false
	if not ctx.check(builder_node != null and not builder_node.visible, "disassembled ship did not hide the FutureShipBuilder display"):
		return false

	# --- WEAPON SLOT + TECH GATING + TIMED RESEARCH ---
	var tech_catalog: TechnologyCatalog = ship_manager.get_technology_catalog()
	if not ctx.check(weapon_part.required_tech_id == &"weapon_systems", "weapon part should require the weapon_systems tech"):
		return false
	if not ctx.check(not game_state.can_buy_ship_part(source.planet_id, weapon_part.id, catalog), "weapon part should be locked before weapon_systems research"):
		return false
	if not ctx.check(hull_t2 != null and not game_state.can_buy_ship_part(source.planet_id, hull_t2.id, catalog), "tier-2 hull should be locked before weapon_systems research"):
		return false
	if not ctx.check(not game_state.can_buy_ship_part(source.planet_id, scanner_t2.id, catalog) and not game_state.can_buy_ship_part(source.planet_id, reactor_module.id, catalog) and not game_state.can_buy_ship_part(source.planet_id, reinforced_module.id, catalog) and not game_state.can_buy_ship_part(source.planet_id, sensor_array_module.id, catalog), "new branch ship parts should remain gated before their exclusive technologies are researched"):
		return false
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_VOLATILE, 50)
	if not ctx.check(game_state.can_research_technology(GameState.FACTION_PLAYER, &"weapon_systems", tech_catalog), "weapon_systems should be researchable after shipyard construction"):
		return false
	if not ctx.check(game_state.research_technology(GameState.FACTION_PLAYER, &"weapon_systems", tech_catalog), "weapon_systems research should start"):
		return false
	if not ctx.check(game_state.call("research_in_progress", GameState.FACTION_PLAYER, &"weapon_systems"), "weapon_systems should run as a timed job"):
		return false
	if not ctx.check(not game_state.has_technology(GameState.FACTION_PLAYER, &"weapon_systems"), "weapon_systems should not complete instantly"):
		return false
	game_state.call("advance_research", 999.0)
	if not ctx.check(game_state.has_technology(GameState.FACTION_PLAYER, &"weapon_systems"), "weapon_systems did not complete after the research timer"):
		return false
	if not ctx.check(game_state.can_buy_ship_part(source.planet_id, weapon_part.id, catalog), "weapon part should be purchasable after weapon_systems research"):
		return false
	if not ctx.check(ship_manager.buy_part(source, weapon_part.id), "weapon part purchase should succeed"):
		return false
	var military_ship_id: StringName = ship_manager.assemble_ship(source, hull_part.id, scanner_part.id, [], weapon_part.id, drive_part.id, shield_part.id)
	if not ctx.check(not String(military_ship_id).is_empty() and game_state.call("ship_build_in_progress", source.planet_id, military_ship_id), "armed ship build did not start"):
		return false
	game_state.call("advance_builds", 999.0)
	var military_assembly: ShipAssembly = game_state.get_ship_assembly(source.planet_id, military_ship_id)
	if not ctx.check(military_assembly != null and military_assembly.weapon_id == weapon_part.id, "armed ship did not record its weapon"):
		return false
	if not ctx.check(
		military_assembly != null
		and not String(military_assembly.drive_variant_id).is_empty()
		and not String(military_assembly.weapon_variant_id).is_empty(),
		"assembled ship did not persist selected drive and weapon variants"):
		return false
	if not ctx.check(
		ship_manager.disassemble_ship(source, military_ship_id)
		and game_state.get_ship_part_count(source.planet_id, weapon_part.id) >= 1
		and game_state.get_ship_part_count(source.planet_id, drive_part.id) >= 1
		and game_state.get_ship_part_count(source.planet_id, shield_part.id) >= 1,
		"armed ship disassembly did not refund the weapon, drive, and shield"):
		return false

	return true
