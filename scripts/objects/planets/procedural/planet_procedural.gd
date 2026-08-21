class_name PlanetProcedural

## Procedural chunk-world helpers for Planet nodes: cache-based configuration,
## size-profile resolution and FoV radius. Kept out of planet.gd so the Planet
## node stays a finite-world node with small delegates instead of absorbing the
## growing infinite-world surface.

## Configures a procedural planet from cached chunk data (ChunkPlanetData, or
## any RefCounted exposing the same fields). Counterpart to apply_definition().
## Must run BEFORE add_child() so _ready() registers the real planet_id/faction
## and applies the cached detail/size profiles.
static func configure_from_cache(planet: Planet, data, size_profile: PlanetSizeProfile = null) -> void:
	if planet == null or data == null:
		return
	planet.planet_id = data.planet_id
	planet.display_name = data.display_name
	planet.faction = data.faction
	planet.composition_base_texture = data.composition_base_texture
	planet.composition_tint = data.composition_tint
	planet.composition_decal_textures = data.composition_decal_textures
	# detail_profile must be set for _apply_detail_seed() in _ready().
	planet.detail_profile = data.detail_profile if data.detail_profile != null else Planet.DEFAULT_DETAIL_PROFILE
	# set_size_profile() also derives layout_size for the spawn timer.
	planet.set_size_profile(size_profile)

## Maps a size class back to the WorldConfig size profile. Shared by
## ChunkCoordinator and Planet so both sides resolve identically (mirrors
## SeededLayout._assign_size_classes() profile selection).
static func resolve_size_profile(config: WorldConfig, size_profiles: Array, size_class: StringName) -> PlanetSizeProfile:
	var profiles_by_id: Dictionary = {}
	for profile in size_profiles:
		if profile != null:
			profiles_by_id[profile.id] = profile
	var default_profile: PlanetSizeProfile = profiles_by_id.get(config.default_profile_id, Planet.DEFAULT_SIZE_PROFILE) as PlanetSizeProfile
	var large_profile: PlanetSizeProfile = profiles_by_id.get(config.large_profile_id, default_profile) as PlanetSizeProfile
	var extra_large_profile: PlanetSizeProfile = profiles_by_id.get(config.extra_large_profile_id, default_profile) as PlanetSizeProfile
	match size_class:
		&"xl", &"extra_large":
			return extra_large_profile
		&"l", &"large":
			return large_profile
		_:
			return default_profile

## FoV radius (in chunk cells) a planet provides: base radius plus the summed
## fov_radius_bonus of its researched upgrades.
static func fov_radius(planet: Planet, config: WorldConfig, state: Node) -> int:
	if config == null or state == null:
		return 2
	var base: int = config.planet_fov_radius
	var bonus := 0
	for up_id in state.get_planet_upgrades(planet.planet_id):
		var def := Planet.DEFAULT_UPGRADE_CATALOG.resolve(up_id)
		if def != null and def.trait_definition != null:
			bonus += def.trait_definition.fov_radius_bonus
	return base + bonus
