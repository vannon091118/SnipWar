class_name PreflightConstraintResearchShip
extends RefCounted

## Persistent research ship, task queue, scan completion, and idle rehydration.

func constraint_name() -> String:
	return "research_ship"

func requires_scene() -> bool:
	return true

func run(ctx: PreflightContext) -> bool:
	var field: Node = ctx.field
	var state: Node = ctx.game_state
	var ship_manager: ShipManager = field.get_node_or_null("ShipManager") as ShipManager
	if not ctx.check(ship_manager != null, "ShipManager runtime module is missing"):
		return false
	if not ctx.check(state.has_method("get_research_ship_records"), "GameState research ship facade is missing"):
		return false

	var records: Array[Dictionary] = state.get_research_ship_records(GameState.FACTION_PLAYER)
	if not ctx.check(records.size() == 1, "a fresh run should contain exactly one persistent ResearchShip"):
		return false
	var starter: Dictionary = records[0]
	var homeworld_id: StringName = state.homeworld_for(GameState.FACTION_PLAYER)
	if not ctx.check(starter.get("status", &"") == &"idle" and starter.get("current_planet_id", &"") == homeworld_id, "starter ResearchShip should be idle at the player homeworld"):
		return false

	var source: Planet = ctx.find_planet_by_id(field, homeworld_id)
	if not ctx.check(source != null and ship_manager.can_launch_research_ship(source), "starter ResearchShip should be launchable without a starter token"):
		return false
	var destination: Planet = null
	for candidate in ship_manager.get_scan_destinations(source):
		if candidate != null and candidate.get_faction() == GameState.FACTION_NEUTRAL:
			destination = candidate
			break
	if not ctx.check(destination != null, "no unknown neutral ResearchShip target is available"):
		return false

	var ship: ShipBase = ship_manager.launch_research_ship(source, destination)
	if not ctx.check(ship != null and ship.mission_role == &"research", "ResearchShip dispatch did not create a ShipBase"):
		return false
	if not ctx.check(state.get_research_ship_records(GameState.FACTION_PLAYER)[0].get("status", &"") == &"in_transit", "ResearchShip dispatch did not persist in-flight state"):
		return false
	ship.call("_arrive")
	await ctx.await_frame()
	if not ctx.check(is_instance_valid(ship), "ResearchShip was freed at arrival"):
		return false
	var arrived_records: Array[Dictionary] = state.get_research_ship_records(GameState.FACTION_PLAYER)
	if not ctx.check(arrived_records[0].get("status", &"") == &"idle" and arrived_records[0].get("current_planet_id", &"") == destination.planet_id, "ResearchShip did not become idle at its destination"):
		return false

	var mission_id: StringName = state.queue_research_mission(GameState.FACTION_PLAYER, destination.planet_id, &"scan", 0.1)
	if not ctx.check(not String(mission_id).is_empty(), "ResearchMission could not be queued"):
		return false
	state.call("advance_research_ship_tasks", 1.0)
	await ctx.await_frame()
	if not ctx.check(state.has_scanned_planet(GameState.FACTION_PLAYER, destination.planet_id), "completed ResearchMission did not store scan intel"):
		return false
	if not ctx.check(state.get_research_missions(GameState.FACTION_PLAYER).is_empty(), "completed ResearchMission was not retired"):
		return false
	if not ctx.check(state.get_research_ship_records(GameState.FACTION_PLAYER)[0].get("status", &"") == &"idle", "ResearchShip was not idle after task completion"):
		return false
	return true
