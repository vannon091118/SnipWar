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

## Returns a runtime duplicate of `base_config` with the WorldConfig growth
## contract fully applied: design_size scales by sqrt(growth_factor) so total
## area grows linearly with growth_factor, target_planet_count scales linearly
## when no explicit override was authored, and columns falls back to auto
## resolution. The authored .tres stays untouched — only this duplicate carries
## the live values for the active scene.
static func resolve_runtime_world(base_config: WorldConfig, base_catalog: PlanetCatalog) -> WorldConfig:
	if base_config == null:
		return null
	var resolved: WorldConfig = base_config.duplicate(true) as WorldConfig
	if resolved == null:
		return null
	var growth: float = resolved.growth_factor
	if growth > 1.0001:
		var scale := sqrt(growth)
		resolved.design_size = Vector2(resolved.design_size.x * scale, resolved.design_size.y * scale)
		resolved.columns = 0
		if resolved.target_planet_count <= 0 and base_catalog != null and base_catalog.planets.size() > 0:
			resolved.target_planet_count = resolved.resolved_target_planet_count(base_catalog.planets.size())
	return resolved

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
	var resolved_size := config.resolved_design_size()
	var column_count := config.resolved_columns(planet_count)
	var row_count := ceili(float(planet_count) / float(column_count))
	var cell_size := Vector2(
		resolved_size.x / float(column_count),
		resolved_size.y / float(row_count)
	)
	for slot in planet_count:
		var column := slot % column_count
		var row := floori(float(slot) / float(column_count))
		positions.append(Vector2(
			(float(column) + 0.5) * cell_size.x,
			(float(row) + 0.5) * cell_size.y
		))
	return positions

## Deterministic K-nearest edge builder for layered navigation graphs.
## Returns an array of [first_planet, second_planet] pairs (planet refs, not
## indices), with symmetric deduplication, ordered by source planet index then
## neighbour distance then neighbour identity. Each source contributes at most
## `ceil((planet_count - 1) * ratio)` neighbours; the global cap is enforced
## entirely by ratio * planet_count * (planet_count - 1) unless max_extra_edges
## is provided, in which case the cap wins as soon as the running total exceeds
## it.
static func build_knn_edges(planets: Array, ratio: float, max_edges: int = 0, grid_edges: Array = []) -> Array:
	var result: Array = []
	if planets.size() < 2 or ratio <= 0.0:
		return result
	var k_per_source: int = clampi(int(ceil(float(planets.size() - 1) * clampf(ratio, 0.0, 1.0))), 0, planets.size() - 1)
	if k_per_source <= 0:
		return result
	# Deterministic symmetric edge set: keyed by min/max planet id so a pair is
	# recorded once even when both directions would request it.
	var edge_set: Dictionary = {}
	if not grid_edges.is_empty():
		for edge in grid_edges:
			if edge is Array and edge.size() == 2:
				edge_set[_edge_key(edge[0], edge[1])] = true
	var running_cap: int = max_edges if max_edges > 0 else 0
	for source_index in planets.size():
		var source: Node2D = planets[source_index] as Node2D
		if source == null:
			continue
		var ranked: Array = []
		for other_index in planets.size():
			if other_index == source_index:
				continue
			var other: Node2D = planets[other_index] as Node2D
			if other == null:
				continue
			ranked.append({
				"index": other_index,
				"planet": other,
				"distance": source.global_position.distance_to(other.global_position),
			})
		ranked.sort_custom(func(a, b):
			if a["distance"] != b["distance"]:
				return a["distance"] < b["distance"]
			return int(a["index"]) < int(b["index"])
		)
		ranked = ranked.slice(0, k_per_source)
		# Sort chosen neighbours by identity so the resulting edge order is
		# stable across rebuilds even when distances tie.
		ranked.sort_custom(func(a, b):
			var ai := int(a["index"])
			var bi := int(b["index"])
			if ai == bi:
				return false
			return ai < bi
		)
		for entry in ranked:
			var target: Node2D = entry["planet"] as Node2D
			var key := _edge_key(source, target)
			if edge_set.has(key):
				continue
			edge_set[key] = true
			result.append([source, target])
			if running_cap > 0 and result.size() >= running_cap:
				return result
	return result

static func _edge_key(first: Node2D, second: Node2D) -> String:
	# Use node identity values as the deterministic tie-breaker so two Node2Ds
	# hash to a stable key without round-tripping through Resource refs.
	var first_id := first.get_instance_id()
	var second_id := second.get_instance_id()
	if first_id <= second_id:
		return "%d-%d" % [first_id, second_id]
	return "%d-%d" % [second_id, first_id]
