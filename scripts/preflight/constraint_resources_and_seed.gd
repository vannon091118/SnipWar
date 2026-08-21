class_name PreflightConstraintResourcesAndSeed
extends RefCounted

## Resource dealing (seed determinism, signature preferences, 1500-planet balance)
## and layout-seed variation.

func constraint_name() -> String:
	return "resources_and_seed"


func run(ctx: PreflightContext) -> bool:
	var field: Node = ctx.field
	var game_state: Node = ctx.game_state
	var world_config: WorldConfig = ctx.world_config
	var planet_catalog: PlanetCatalog = ctx.planet_catalog
	var neutral_probe_ids: Array[StringName] = []
	for index in range(2, mini(5, planet_catalog.planets.size())):
		neutral_probe_ids.append(planet_catalog.planets[index].planet_id)
	if not ctx.check(neutral_probe_ids.size() >= 3 and game_state.faction_of(neutral_probe_ids[0]) == GameState.FACTION_NEUTRAL and game_state.faction_of(neutral_probe_ids[1]) == GameState.FACTION_NEUTRAL and game_state.faction_of(neutral_probe_ids[2]) == GameState.FACTION_NEUTRAL, "GameState faction lookup is wrong"):
		return false
	var resource_pool: ResourcePool = preload("res://resources/config/resource_pool_default.tres")
	if not ctx.check(resource_pool != null and resource_pool.validate().is_empty(), "resource pool validation failed"):
		return false

	# Resource canonical-ID contract: every vault key, refinery input, upgrade cost
	# and tech cost flows through GameState.RES_*. A typo like &"energi" instead of
	# RES_ENERGY must fail loudly here -- not at play-test time.
	if not ctx.check(game_state.get("RES_ENERGY") == &"energy" and game_state.get("RES_BIOMASS") == &"biomass" and game_state.get("RES_RARE") == &"rare" and game_state.get("RES_MATERIAL") == &"material" and game_state.get("RES_VOLATILE") == &"volatile", "resource canonical IDs drifted from energy/biomass/rare/material/volatile"):
		return false
	if not ctx.check((game_state.get("ALL_RESOURCES") as Array).size() == 5, "ALL_RESOURCES must list every canonical ID once"):
		return false
	if not ctx.check(game_state.call("is_valid_resource", game_state.get("RES_ENERGY")), "is_valid_resource must accept RES_ENERGY"):
		return false

	if not ctx.check(game_state.call("validate_resources", resource_pool).is_empty(), "GameState resource deal failed"):
		return false
	var player_homeworld_id: StringName = game_state.homeworld_for(GameState.FACTION_PLAYER)
	var cpu_homeworld_id: StringName = game_state.homeworld_for(GameState.FACTION_CPU)
	if not ctx.check(not String(game_state.resource_of(player_homeworld_id)).is_empty() and not String(game_state.resource_of(cpu_homeworld_id)).is_empty() and game_state.resource_of(player_homeworld_id) != game_state.resource_of(cpu_homeworld_id), "homeworld resources are not distinct"):
		return false
	var resource_seed: int = world_config.layout_seed
	var resource_snapshot_before: Dictionary = game_state.call("resource_snapshot")
	game_state.call("deal_resources", planet_catalog, resource_pool, resource_seed)
	var resource_snapshot_after: Dictionary = game_state.call("resource_snapshot")
	if not ctx.check(resource_snapshot_before == resource_snapshot_after, "resource deal is not seed-deterministic"):
		return false
	var scale_resource_catalog: PlanetCatalog = ctx.catalog_for_count(planet_catalog, 1500)
	game_state.call("deal_resources", scale_resource_catalog, resource_pool, 424242)
	if not ctx.check(game_state.call("validate_resources", resource_pool).is_empty(), "1500-planet resource deal is unbalanced"):
		return false

	# Test PlanetDefinition signature fields and validation
	var test_planet_def := PlanetDefinition.new()
	test_planet_def.planet_id = &"test_planet"
	test_planet_def.display_name = "Test Planet"
	test_planet_def.planet_texture = preload("res://assets/objects/planets/planet_01_ember.svg")
	test_planet_def.detail_profile = preload("res://resources/config/planet_details/default.tres")
	test_planet_def.signature_resource = GameState.RES_ENERGY
	test_planet_def.signature_probability = 1.0
	if not ctx.check(test_planet_def.validate().is_empty(), "valid planet definition with signature should pass validation"):
		return false
	test_planet_def.signature_probability = 1.5
	if not ctx.check(not test_planet_def.validate().is_empty(), "invalid signature probability should fail validation"):
		return false
	test_planet_def.signature_probability = 1.0

	# Test deal_resources with explicit signature preference
	var sig_catalog := PlanetCatalog.new()
	var hw1: PlanetDefinition = test_planet_def.duplicate(true) as PlanetDefinition
	hw1.planet_id = &"hw1"
	hw1.display_name = "HW1"
	hw1.planet_role = &"homeworld"
	hw1.signature_resource = GameState.RES_BIOMASS
	hw1.signature_probability = 1.0
	var hw2: PlanetDefinition = test_planet_def.duplicate(true) as PlanetDefinition
	hw2.planet_id = &"hw2"
	hw2.display_name = "HW2"
	hw2.planet_role = &"homeworld"
	hw2.signature_resource = GameState.RES_RARE
	hw2.signature_probability = 1.0
	var p3: PlanetDefinition = test_planet_def.duplicate(true) as PlanetDefinition
	p3.planet_id = &"p3"
	p3.display_name = "P3"
	p3.planet_role = &"planet"
	p3.signature_resource = GameState.RES_ENERGY
	p3.signature_probability = 1.0
	sig_catalog.planets = [hw1, hw2, p3]
	game_state.call("deal_resources", sig_catalog, resource_pool, 12345)
	if not ctx.check(game_state.resource_of(&"hw1") == GameState.RES_BIOMASS and game_state.resource_of(&"hw2") == GameState.RES_RARE and game_state.resource_of(&"p3") == GameState.RES_ENERGY, "signature resources should be respected when probability is 1.0"):
		return false

	game_state.call("deal_resources", planet_catalog, resource_pool, resource_seed)
	var positions_before: Dictionary = ctx.planet_positions(field)
	if not ctx.check(positions_before.size() == planet_catalog.planets.size(), "generated planets do not match the catalog"):
		return false
	for initial_planet in field.get_children():
		if initial_planet is Planet:
			var expected_initial_workers: int = game_state.starting_workers_of((initial_planet as Planet).planet_id)
			if not ctx.check((initial_planet as Planet).worker_count == expected_initial_workers, "%s initial worker distribution is wrong" % initial_planet.name):
				return false
	for planet_node in field.get_children():
		if planet_node is Planet:
			var global_planet_position: Vector2 = (planet_node as Planet).global_position
			if not ctx.check(global_planet_position.x >= -0.01 and global_planet_position.x <= world_config.design_size.x + 0.01 and global_planet_position.y >= -0.01 and global_planet_position.y <= world_config.design_size.y + 0.01, "planet global position is outside world bounds"):
				return false
	var world_errors := world_config.validate_for_planet_count(positions_before.size())
	if not ctx.check(world_errors.is_empty(), "world config validation failed"):
		return false
	var configured_profiles: Array[PlanetSizeProfile] = []
	for profile_value in field.get("size_profiles"):
		var profile: PlanetSizeProfile = profile_value as PlanetSizeProfile
		if profile != null:
			configured_profiles.append(profile)
	var profile_errors := world_config.validate_profiles(configured_profiles)
	if not ctx.check(profile_errors.is_empty(), "planet size profile validation failed"):
		return false

	var original_seed: int = world_config.layout_seed
	field.call("set_layout_seed", original_seed + 1)
	await ctx.await_frame()
	await ctx.await_frame()
	var positions_changed := false
	for planet in positions_before:
		if positions_before[planet].distance_to((planet as Planet).position) > 1.0:
			positions_changed = true
			break
	if not ctx.check(positions_changed, "changing the layout seed did not change planet positions"):
		return false
	field.call("set_layout_seed", original_seed)
	await ctx.await_frame()
	await ctx.await_frame()
	ctx.original_seed = original_seed
	return true
