class_name StartRosterGenerator
extends RefCounted

## Produces valid future start candidates from the same deterministic world as
## the infinite chunk coordinator. This component does not assign ownership,
## mutate GameState, or select a homeworld.

const DEFAULT_WORLD_CONFIG: WorldConfig = preload("res://resources/config/world_default.tres")
const DEFAULT_PLANET_CATALOG: PlanetCatalog = preload("res://resources/config/planet_catalog.tres")

static func generate(
	layout_seed: int,
	count: int,
	world_config: WorldConfig = null,
	base_catalog: PlanetCatalog = null
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if count <= 0:
		return result
	var config: WorldConfig = world_config if world_config != null else DEFAULT_WORLD_CONFIG
	var catalog: PlanetCatalog = base_catalog if base_catalog != null else DEFAULT_PLANET_CATALOG
	if config == null or catalog == null or config.chunk_size <= 0:
		return result

	var chunk_size: int = config.chunk_size
	if chunk_size <= 0:
		return result
	# Walk a fixed, seed-independent spiral of chunk coordinates. This allows
	# the default 3x3 chunk to provide ten candidates without creating a second
	# world or depending on which chunks the player happened to visit first.
	var chunk_coords: Array[Vector2i] = [
		Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
	]
	for chunk_coord in chunk_coords:
		if result.size() >= count:
			break
		var chunk_seed_value: int = WorldGenerator.chunk_seed(layout_seed, chunk_coord.x, chunk_coord.y)
		var definitions: Array[PlanetDefinition] = WorldGenerator.generate_chunk_planets(
			catalog, chunk_coord.x, chunk_coord.y, chunk_seed_value, chunk_size, config, &"xl"
		)
		for slot in definitions.size():
			if result.size() >= count:
				break
			var definition: PlanetDefinition = definitions[slot]
			if definition == null:
				continue
			var local_col: int = slot % chunk_size
			var local_row: int = int(slot / float(chunk_size))
			var cell := Vector2i(chunk_coord.x * chunk_size + local_col, chunk_coord.y * chunk_size + local_row)
			var candidate_seed: int = WorldGenerator.slot_seed(chunk_seed_value, slot)
			var position := WorldGenerator.deterministic_chunk_position(config, layout_seed, chunk_coord.x, chunk_coord.y, slot, chunk_size)
			result.append({
				"planet_id": definition.planet_id,
				"cell": cell,
				"position": position,
				"candidate_seed": candidate_seed,
				"composition_base_texture": definition.composition_base_texture,
				"composition_tint": definition.composition_tint,
				"composition_decal_textures": definition.composition_decal_textures.duplicate(),
				"display_name": definition.display_name,
				"planet_role": definition.planet_role,				"size_class": &"xl" if slot < config.resolved_size_class_counts(chunk_size * chunk_size).x else (&"l" if slot < config.resolved_size_class_counts(chunk_size * chunk_size).x + config.resolved_size_class_counts(chunk_size * chunk_size).y else &"variable"),
			})
	return result
