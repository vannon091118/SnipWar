class_name PreflightConstraintShipBuilder
extends RefCounted

## Ship part catalog branches, tech-gated purchases, timed assembly/disassembly and
## the weapon slot (first armed ship = military).

func constraint_name() -> String:
	return "ship_builder"


func run(ctx: PreflightContext) -> bool:
	var field: Node = ctx.field
	var game_state: Node = ctx.game_state
	var ship_manager: ShipManager = field.get_node_or_null("ShipManager") as ShipManager
	if not ctx.check(ship_manager != null, "ShipManager runtime module is missing"):
		return false
	var catalog: ShipPartCatalog = ship_manager.get_part_catalog()
	if not ctx.check(catalog != null and catalog.validate().is_empty(), "ship part catalog validation failed"):
		return false
	if not ctx.check(not catalog.for_slot(ShipPartDefinition.SLOT_HULL).is_empty() and not catalog.for_slot(ShipPartDefinition.SLOT_SCANNER).is_empty() and not catalog.for_slot(ShipPartDefinition.SLOT_MODULE).is_empty() and not catalog.for_slot(ShipPartDefinition.SLOT_WEAPON).is_empty(), "ship part catalog is missing a hull, scanner, module, or weapon branch"):
		return false
	var source: Planet = ctx.find_planet_by_id(field, game_state.homeworld_for(GameState.FACTION_PLAYER) as StringName)
	if not ctx.check(source != null and game_state.has_planet_upgrade(source.planet_id, ShipManager.SHIPYARD_UPGRADE_ID), "player homeworld should carry a shipyard before the ship builder runs"):
		return false
	var hull_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_HULL)[0]
	var scanner_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_SCANNER)[0]
	var module_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_MODULE)[0]

	game_state.add_faction_resource(GameState.FACTION_PLAYER, &"material", 100)
	game_state.add_faction_resource(GameState.FACTION_PLAYER, &"energy", 100)
	game_state.add_faction_resource(GameState.FACTION_PLAYER, &"volatile", 100)

	if not ctx.check(ship_manager.can_buy_part(source, hull_part.id), "hull part should be purchasable"):
		return false
	if not ctx.check(ship_manager.buy_part(source, hull_part.id), "hull part purchase should succeed"):
		return false
	if not ctx.check(ship_manager.buy_part(source, scanner_part.id), "scanner part purchase should succeed"):
		return false
	if not ctx.check(ship_manager.buy_part(source, module_part.id), "module part purchase should succeed"):
		return false
	if not ctx.check(game_state.get_ship_part_count(source.planet_id, hull_part.id) == 1 and game_state.get_ship_part_count(source.planet_id, scanner_part.id) == 1 and game_state.get_ship_part_count(source.planet_id, module_part.id) == 1, "purchased parts were not recorded in the inventory"):
		return false

	if not ctx.check(not game_state.can_assemble_ship(source.planet_id, hull_part.id, scanner_part.id, [module_part.id, module_part.id], catalog), "assembling beyond module ownership should be rejected"):
		return false
	var ship_id: StringName = ship_manager.assemble_ship(source, hull_part.id, scanner_part.id, [module_part.id])
	if not ctx.check(not String(ship_id).is_empty(), "ship assembly did not start (ship_id=%s)" % ship_id):
		return false
	if not ctx.check(game_state.call("ship_build_in_progress", source.planet_id, ship_id), "timed ship build was not queued"):
		return false
	if not ctx.check(not game_state.has_ship_assembly(source.planet_id, ship_id), "ship build should not register before the timer completes"):
		return false
	game_state.call("advance_builds", 999.0)
	if not ctx.check(game_state.has_ship_assembly(source.planet_id, ship_id), "ship assembly did not register after the build timer (ship_id=%s)" % ship_id):
		return false
	if not ctx.check(game_state.get_ship_part_count(source.planet_id, hull_part.id) == 0 and game_state.get_ship_part_count(source.planet_id, scanner_part.id) == 0 and game_state.get_ship_part_count(source.planet_id, module_part.id) == 0, "ship assembly did not consume the parts"):
		return false
	var hangar: ShipyardHangar = source.get_node_or_null("PlanetDetails/UpgradeStructure_shipyard/Hangar") as ShipyardHangar
	var builder_node: Node2D = hangar.get_node_or_null("FutureShipBuilder") as Node2D if hangar != null else null
	if not ctx.check(builder_node != null and builder_node.visible, "assembled ship did not reveal the FutureShipBuilder display"):
		return false

	if not ctx.check(ship_manager.disassemble_ship(source, ship_id), "ship disassembly should succeed"):
		return false
	if not ctx.check(not game_state.has_ship_assembly(source.planet_id, ship_id), "disassembled ship should be removed"):
		return false
	if not ctx.check(game_state.get_ship_part_count(source.planet_id, hull_part.id) == 1 and game_state.get_ship_part_count(source.planet_id, scanner_part.id) == 1 and game_state.get_ship_part_count(source.planet_id, module_part.id) == 1, "disassembly did not refund the parts"):
		return false
	if not ctx.check(builder_node != null and not builder_node.visible, "disassembled ship did not hide the FutureShipBuilder display"):
		return false

	# --- WEAPON SLOT + TECH GATING + TIMED RESEARCH ---
	var tech_catalog: TechnologyCatalog = ship_manager.get_technology_catalog()
	var weapon_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_WEAPON)[0]
	if not ctx.check(weapon_part.required_tech_id == &"weapon_systems", "weapon part should require the weapon_systems tech"):
		return false
	if not ctx.check(not game_state.can_buy_ship_part(source.planet_id, weapon_part.id, catalog), "weapon part should be locked before weapon_systems research"):
		return false
	var hull_t2: ShipPartDefinition = catalog.resolve(&"hull_t2")
	if not ctx.check(hull_t2 != null and not game_state.can_buy_ship_part(source.planet_id, hull_t2.id, catalog), "tier-2 hull should be locked before weapon_systems research"):
		return false
	game_state.add_faction_resource(GameState.FACTION_PLAYER, &"volatile", 50)
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
	var military_ship_id: StringName = ship_manager.assemble_ship(source, hull_part.id, scanner_part.id, [], weapon_part.id)
	if not ctx.check(not String(military_ship_id).is_empty() and game_state.call("ship_build_in_progress", source.planet_id, military_ship_id), "armed ship build did not start"):
		return false
	game_state.call("advance_builds", 999.0)
	var military_assembly: Dictionary = game_state.get_ship_assembly(source.planet_id, military_ship_id)
	if not ctx.check(military_assembly.get("weapon", &"") == weapon_part.id, "armed ship did not record its weapon"):
		return false
	if not ctx.check(ship_manager.disassemble_ship(source, military_ship_id) and game_state.get_ship_part_count(source.planet_id, weapon_part.id) >= 1, "armed ship disassembly did not refund the weapon"):
		return false
	return true
