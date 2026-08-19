@tool
class_name GenerationContext
extends RefCounted

## Shared context passed to every GenerationPass during pipeline execution.
## Provides deterministic RNG, world configuration, and spatial queries.

## The master RNG seeded from WorldConfig.layout_seed.
var rng: RandomNumberGenerator

## The active world configuration.
var world_config: WorldConfig

## The chunk grid accumulating placements across passes.
var chunk_grid: ChunkGrid

## The base catalog (before expansion), for reference by passes.
var base_catalog: PlanetCatalog

## The expanded catalog (after WorldGenerator.expand_catalog), for planet passes.
var expanded_catalog: PlanetCatalog

## All size profiles available for assignment (Array of PlanetSizeProfile).
var size_profiles: Array = []

## All placements produced so far (populated by pipeline after each pass).
var all_placements: Array = []

## Additional typed storage for cross-pass data sharing.
## Keys are StringName (e.g. &"planet_positions", &"decoration_rules").
var shared_data: Dictionary = {}

func _init() -> void:
	rng = RandomNumberGenerator.new()
	chunk_grid = ChunkGrid.new()

## Set the master seed (typically WorldConfig.layout_seed).
func set_seed(seed_value: int) -> void:
	rng.seed = seed_value

## Derive a deterministic sub-RNG for a specific chunk coordinate.
## Guarantees: same world_seed + same chunk_coord → same sub-seed, always.
func rng_for_chunk(chunk_coord: Vector2i) -> RandomNumberGenerator:
	var sub_rng := RandomNumberGenerator.new()
	# Fold chunk coords and world seed into a single deterministic seed.
	var world_seed := rng.seed
	sub_rng.seed = hash(world_seed ^ (chunk_coord.x * 73856093) ^ (chunk_coord.y * 19349663))
	return sub_rng

## Derive a deterministic sub-RNG for a specific string context.
func rng_for_context(context_name: StringName) -> RandomNumberGenerator:
	var sub_rng := RandomNumberGenerator.new()
	sub_rng.seed = hash(rng.seed ^ hash(context_name))
	return sub_rng

## Store typed data for cross-pass communication.
func set_shared(key: StringName, value: Variant) -> void:
	shared_data[key] = value

## Retrieve typed data from a prior pass.
func get_shared(key: StringName, default: Variant = null) -> Variant:
	return shared_data.get(key, default)

## Convenience: resolve size profiles by id.
func resolve_profile(profile_id: StringName) -> PlanetSizeProfile:
	for profile in size_profiles:
		if profile != null and profile.id == profile_id:
			return profile
	return null
