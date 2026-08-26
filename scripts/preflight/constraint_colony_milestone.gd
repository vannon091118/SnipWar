class_name PreflightConstraintColonyMilestone
extends RefCounted

## Colony ship dispatch, planet settling and the idempotent first_colony milestone.

func constraint_name() -> String:
	return "colony_milestone"

func requires_scene() -> bool:
	return true


func run(ctx: PreflightContext) -> bool:
	var field: Node = ctx.field
	var game_state: Node = ctx.game_state

	if not ctx.check(ctx.fixture.prepare_ship_builder(), "ship-builder fixture could not prepare the shipyard prerequisite"):
		return false
	await ctx.await_frame()
	var source: Planet = ctx.find_planet_by_id(field, game_state.homeworld_for(GameState.FACTION_PLAYER) as StringName)
	if not ctx.check(source != null and game_state.has_planet_upgrade(source.planet_id, ShipManager.SHIPYARD_UPGRADE_ID), "player homeworld should carry a shipyard before the colony ship test"):
		return false
	var ship_manager: ShipManager = field.get_node_or_null("ShipManager") as ShipManager
	if not ctx.check(ship_manager != null, "ShipManager runtime module is missing"):
		return false
	var conflict_manager: Node = field.get_node_or_null("ConflictManager")
	if not ctx.check(conflict_manager != null and conflict_manager.has_method("active_ship_count"), "ConflictManager runtime module is missing"):
		return false
	var catalog: ShipPartCatalog = ship_manager.get_part_catalog()
	var hull_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_HULL)[0]
	var scanner_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_SCANNER)[0]
	var drive_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_DRIVE)[0]
	var shield_part: ShipPartDefinition = catalog.for_slot(ShipPartDefinition.SLOT_SHIELD)[0]

	# The first successful builder ship is a colony ship and creates a milestone.
	var colony_destination: Planet = null
	for neighbor_value in ctx.network.get_neighbors(source):
		var neighbor_planet: Planet = neighbor_value as Planet
		if neighbor_planet != null and neighbor_planet.get_faction() == GameState.FACTION_NEUTRAL and game_state.has_scanned_planet(GameState.FACTION_PLAYER, neighbor_planet.planet_id):
			colony_destination = neighbor_planet
			break
	if not ctx.check(colony_destination != null, "no scanned neutral neighbor available for the first colony milestone"):
		return false
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_MATERIAL, 100)
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY, 100)
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_VOLATILE, 100)
	for colony_part in [hull_part, scanner_part, drive_part, shield_part]:
		if not ctx.check(ship_manager.buy_part(source, colony_part.id), "colony ship part purchase failed for %s" % colony_part.id):
			return false
	var colony_ship_id: StringName = ship_manager.assemble_ship(source, hull_part.id, scanner_part.id, [], &"", drive_part.id, shield_part.id, &"", -1, &"colony")
	if not ctx.check(not String(colony_ship_id).is_empty(), "colony ship build did not start"):
		return false
	game_state.call("advance_builds", 999.0)
	var colony_ship: ShipBase = ship_manager.dispatch_ship(source, colony_destination, colony_ship_id, &"colony")
	if not ctx.check(colony_ship != null and conflict_manager.call("active_ship_count") == 1, "colony ship was not routed through ConflictManager"):
		return false
	colony_ship.call("_arrive")
	await ctx.await_frame()
	if not ctx.check(colony_destination.get_faction() == GameState.FACTION_PLAYER and game_state.has_milestone(GameState.FACTION_PLAYER, &"first_colony"), "successful colony ship did not settle the planet or create first_colony milestone"):
		return false
	if not ctx.check(not game_state.mark_milestone(GameState.FACTION_PLAYER, &"first_colony"), "first_colony milestone must be idempotent"):
		return false
	return true
