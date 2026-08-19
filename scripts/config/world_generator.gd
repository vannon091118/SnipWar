@tool
class_name WorldGenerator
extends RefCounted

## How many planets the world should contain. A positive
## WorldConfig.target_planet_count wins, otherwise the catalog defines it.
static func target_planet_count(config: WorldConfig, base_catalog: PlanetCatalog) -> int:
	if config != null and config.target_planet_count > 0:
		return config.target_planet_count
	if base_catalog != null:
		return base_catalog.planets.size()
	return 0

## Rolls a deterministic catalog of `target_count` planets from the base assets.
## The first base_catalog.planets.size() entries keep their original identity so
## homeworld/faction seeding stays stable; every additional planet is a seeded
## duplicate of a base template with a unique id/display-name suffix.
static func expand_catalog(base_catalog: PlanetCatalog, target_count: int) -> PlanetCatalog:
	var catalog := PlanetCatalog.new()
	if base_catalog == null or base_catalog.planets.is_empty() or target_count <= 0:
		return catalog
	var definitions: Array[PlanetDefinition] = []
	var base_size := base_catalog.planets.size()
	for index in target_count:
		var source: PlanetDefinition = base_catalog.planets[index % base_size]
		if source == null:
			continue
		var definition: PlanetDefinition = source.duplicate(true) as PlanetDefinition
		if index >= base_size:
			definition.planet_id = StringName("%s_%d" % [definition.planet_id, index])
			definition.display_name = "%s %d" % [definition.display_name, index]
			# Rolled variants are ordinary neutral worlds, never extra homeworlds.
			definition.planet_role = &"planet"
			definition.faction = &"neutral"
		definitions.append(definition)
	catalog.planets = definitions
	return catalog

## Pure grid layout: one cell-center position per planet slot, ordered by slot.
## Jitter and padding clamping stay in SeededLayout so the math is easy to test.
static func grid_cell_positions(config: WorldConfig, planet_count: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if config == null or planet_count <= 0:
		return positions
	var column_count := config.resolved_columns(planet_count)
	var row_count := ceili(float(planet_count) / float(column_count))
	var cell_size := Vector2(
		config.design_size.x / float(column_count),
		config.design_size.y / float(row_count)
	)
	for slot in planet_count:
		var column := slot % column_count
		var row := floori(float(slot) / float(column_count))
		positions.append(Vector2(
			(float(column) + 0.5) * cell_size.x,
			(float(row) + 0.5) * cell_size.y
		))
	return positions
