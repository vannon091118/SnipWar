class_name PreflightConstraintGridSystem
extends RefCounted

## Hex/rect grid + building placement/pathfinding on planet nodes.

const BUILDING_CATALOG: BuildingCatalog = preload("res://resources/config/building_catalog_default.tres")

func constraint_name() -> String:
	return "grid_system"

func requires_scene() -> bool:
	return true

func run(ctx: PreflightContext) -> bool:
	# Pure grid geometry: a radius-2 hex grid has 19 cells (1 + 6 + 12).
	var config := PlanetGridConfig.new()
	config.grid_radius = 2
	var grid := PlanetGrid.new()
	grid.configure(config, BUILDING_CATALOG)
	var cell_count := 0
	for _key in grid.building_cells():
		cell_count += 1
	if not ctx.check(grid.cell_at(0, 0) != null, "hex grid should have a center cell"):
		return false
	if not ctx.check(grid.get_cell_at(2, 0) != null and grid.get_cell_at(3, 0) == null, "hex grid radius bounds are wrong"):
		return false

	# Building placement / removal.
	var wall := BUILDING_CATALOG.resolve(&"wall")
	if not ctx.check(grid.place_building(0, 0, wall), "building placement should succeed on an empty cell"):
		return false
	if not ctx.check(not grid.place_building(0, 0, wall), "building placement should fail on an occupied cell"):
		return false
	if not ctx.check(grid.cell_at(0, 0).state == &"occupied", "occupied cell state is wrong"):
		return false
	if not ctx.check(grid.remove_building(0, 0), "building removal should succeed"):
		return false
	if not ctx.check(grid.cell_at(0, 0).state == &"empty", "removed cell should be empty"):
		return false

	# BFS pathfinding on the hex grid.
	var path := grid.find_path(-2, 0, 2, 0)
	if not ctx.check(path.size() >= 3 and path[0] == Vector2i(-2, 0) and path[path.size() - 1] == Vector2i(2, 0), "hex BFS should route across the grid"):
		return false

	# Grid reset clears buildings.
	if not grid.place_building(1, 0, wall):
		return false
	grid.reset_grid()
	if not ctx.check(grid.cell_at(1, 0).state == &"empty", "grid reset should clear buildings"):
		return false

	# Planet integration: get_grid() is lazy and supports building placement.
	var planet := _first_owned_planet(ctx)
	if planet == null:
		ctx.log_verbose("no owned planet available for grid integration")
		return true
	var planet_grid := planet.get_grid()
	if not ctx.check(planet_grid != null, "Planet.get_grid should return a grid"):
		return false
	if not ctx.check(planet_grid.cell_at(0, 0) != null, "planet grid should expose cells"):
		return false
	return true

func _first_owned_planet(ctx: PreflightContext) -> Planet:
	var field: Node = ctx.field
	if field == null:
		return null
	if field.has_method("get_chunk_coordinator"):
		var coordinator: ChunkCoordinator = field.get_chunk_coordinator()
		if coordinator != null:
			for value in coordinator.get_active_planets():
				var planet := value as Planet
				if planet != null and planet.get_faction() != GameState.FACTION_NEUTRAL:
					return planet
	for child in field.get_children():
		var planet := child as Planet
		if planet != null and planet.get_faction() != GameState.FACTION_NEUTRAL:
			return planet
	return null
