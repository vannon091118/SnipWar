class_name PreflightConstraintConquestGridCombat
extends RefCounted

## Wave-based grid conquest simulation, base-HP accounting, capture decisions
## and the neutralization timer.

func constraint_name() -> String:
	return "conquest_grid_combat"

func requires_scene() -> bool:
	return true

func run(ctx: PreflightContext) -> bool:
	# Deterministic wave-based grid conquest.
	var defender_grid := {
		"base_hp": 100,
		"buildings": [
			{"q": 0, "r": 0, "building_id": &"laser_tower", "hp": 40},
			{"q": 1, "r": 0, "building_id": &"missile_tower", "hp": 35},
		],
	}
	var first := ConquestSimulator.simulate_grid_conquest(null, 3, defender_grid, null, 777)
	var second := ConquestSimulator.simulate_grid_conquest(null, 3, defender_grid, null, 777)
	if not ctx.check(first.captured == second.captured and first.surviving_attackers == second.surviving_attackers, "grid conquest must be deterministic"):
		return false
	if not ctx.check(not first.base_hp_history.is_empty(), "grid conquest should record base HP history"):
		return false
	if not ctx.check(first.grid_snapshots.size() > 0, "grid conquest should record per-wave snapshots"):
		return false
	if not ctx.check(first.wave_events.size() > 0, "grid conquest should emit wave events"):
		return false

	# A defended base produces tower_count.
	if not ctx.check(first.tower_count == 2, "grid conquest should count tower buildings"):
		return false

	# Capture decisions on a real planet (adopt / loot / neutralize).
	var field: Node = ctx.field
	if field == null:
		return true
	var planet := _find_planet(field, ctx)
	if planet == null:
		ctx.log_verbose("no planet available for capture-decision integration")
		return true
	PlanetArrivalResolver.commit_capture_decision(planet, &"loot", GameState.FACTION_PLAYER)
	PlanetArrivalResolver.commit_capture_decision(planet, &"neutralize", GameState.FACTION_PLAYER)
	if not ctx.check(planet.is_neutralized(), "neutralize decision should start the neutralization state"):
		return false
	if not ctx.check(ctx.find_timer(planet) != null, "neutralized planet should have a timer"):
		return false
	planet._on_neutralization_expired()
	if not ctx.check(not planet.is_neutralized(), "neutralization expiry should clear the state"):
		return false

	return true

func _find_planet(field: Node, ctx: PreflightContext) -> Planet:
	if field.has_method("get_chunk_coordinator"):
		var coordinator: ChunkCoordinator = field.get_chunk_coordinator()
		if coordinator != null:
			var active := coordinator.get_active_planets()
			if not active.is_empty():
				return active[0] as Planet
	for child in field.get_children():
		if child is Planet:
			return child as Planet
	return null
