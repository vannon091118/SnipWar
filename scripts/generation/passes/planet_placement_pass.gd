@tool
class_name PlanetPlacementPass
extends GenerationPass

## Generation pass that places planets using the existing catalog + grid layout.
## Wraps the logic from SeededLayout.regenerate() and WorldGenerator into
## the pipeline interface. Produces Placement objects for each planet.

func _init() -> void:
	pass_name = "PlanetPlacement"
	order = 10

func generate(ctx: GenerationContext) -> Array[Placement]:
	var placements: Array[Placement] = []
	var config: WorldConfig = ctx.world_config
	if config == null:
		return placements
	var catalog: PlanetCatalog = ctx.expanded_catalog
	if catalog == null or catalog.planets.is_empty():
		return placements

	var planet_count := catalog.planets.size()
	var cell_positions: Array[Vector2] = WorldGenerator.grid_cell_positions(config, planet_count)
	var column_count := config.resolved_columns(planet_count)
	var row_count := ceili(float(planet_count) / float(column_count))
	var cell_size := Vector2(
		config.design_size.x / float(column_count),
		config.design_size.y / float(row_count)
	)

	# Shuffle slot assignment deterministically.
	var slots: Array[int] = []
	for slot in planet_count:
		slots.append(slot)
	_shuffle(slots, ctx.rng)

	# Resolve size-class counts.
	var size_counts := config.resolved_size_class_counts(planet_count)
	var profiles_by_id: Dictionary = {}
	for profile: PlanetSizeProfile in ctx.size_profiles:
		if profile != null:
			profiles_by_id[profile.id] = profile

	var default_profile_id := config.default_profile_id
	var large_profile_id := config.large_profile_id
	var xl_profile_id := config.extra_large_profile_id

	# Build assignment list.
	var assigned_profiles: Array[PlanetSizeProfile] = []
	for _i in size_counts.x:
		assigned_profiles.append(_resolve_or_default(profiles_by_id, xl_profile_id, default_profile_id))
	for _i in size_counts.y:
		assigned_profiles.append(_resolve_or_default(profiles_by_id, large_profile_id, default_profile_id))
	while assigned_profiles.size() < planet_count:
		assigned_profiles.append(_resolve_or_default(profiles_by_id, default_profile_id, default_profile_id))

	# Shuffle profile assignment.
	_shuffle(assigned_profiles, ctx.rng)

	for index in planet_count:
		var definition: PlanetDefinition = catalog.planets[index]
		if definition == null:
			continue

		var slot: int = slots[index]
		var cell_center: Vector2 = cell_positions[slot]
		var profile: PlanetSizeProfile = assigned_profiles[index]
		var jitter_factor: float = profile.jitter_factor if profile != null else 1.0
		var offset := Vector2(
			ctx.rng.randf_range(-cell_size.x * config.jitter * jitter_factor, cell_size.x * config.jitter * jitter_factor),
			ctx.rng.randf_range(-cell_size.y * config.jitter * jitter_factor, cell_size.y * config.jitter * jitter_factor)
		)
		var item_position := cell_center + offset
		item_position.x = clampf(item_position.x, config.padding, config.design_size.x - config.padding)
		item_position.y = clampf(item_position.y, config.padding, config.design_size.y - config.padding)

		var scale := 1.0
		if profile != null:
			scale = ctx.rng.randf_range(profile.scale_range.x, profile.scale_range.y)

		var placement := Placement.new()
		placement.placement_id = definition.planet_id
		placement.position = item_position
		placement.placement_type = &"planet"
		placement.asset_id = definition.planet_id
		placement.radius = 120.0 * scale  # approximate visual radius
		placement.priority = 100  # planets draw above decorations
		placement.metadata = {
			"planet_id": definition.planet_id,
			"slot": slot,
			"scale": scale,
			"profile": profile,
			"detail_seed": ctx.rng.randi(),
			"faction": definition.faction,
			"planet_role": definition.planet_role,
			"starting_workers": profile.starting_workers if profile != null else 0,
		}
		placements.append(placement)

	# Store planet placements for downstream passes.
	ctx.set_shared(&"planet_placements", placements)
	ctx.set_shared(&"planet_count", planet_count)
	return placements


func _resolve_or_default(profiles_by_id: Dictionary, profile_id: StringName, fallback_id: StringName) -> PlanetSizeProfile:
	var profile: PlanetSizeProfile = profiles_by_id.get(profile_id) as PlanetSizeProfile
	if profile != null:
		return profile
	profile = profiles_by_id.get(fallback_id) as PlanetSizeProfile
	if profile != null:
		return profile
	return preload("res://resources/config/planet_sizes/variable.tres")


func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = value
