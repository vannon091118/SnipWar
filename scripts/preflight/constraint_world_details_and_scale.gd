class_name PreflightConstraintWorldDetailsAndScale
extends RefCounted

## Meteor movement/respawn, planet detail fidelity, and the scaled-layout/scenario
## cases that validate the world generator at multiple design sizes.

func constraint_name() -> String:
	return "world_details_and_scale"


func run(ctx: PreflightContext) -> bool:
	var background: Node = ctx.background
	var field: Node = ctx.field
	var planet_catalog: PlanetCatalog = ctx.planet_catalog
	var scenario_catalog: ScenarioCatalog = ctx.scenario_catalog
	var original_seed: int = ctx.original_seed

	var meteor_field: Node = background.get_node("MeteorField")
	var meteor_positions: Array[Vector2] = []
	for meteor in meteor_field.get_children():
		meteor_positions.append(meteor.position)
		var pixels: float = meteor.texture.get_width() * meteor.scale.x
		if not ctx.check(pixels >= 4.0 and pixels <= 10.0, "%s pixel size is invalid" % meteor.name):
			return false
	await ctx.await_frame()
	if not ctx.check(meteor_field.get_child(0).position != meteor_positions[0], "meteor movement is inactive"):
		return false
	var respawn_meteor: Sprite2D = meteor_field.get_child(0)
	respawn_meteor.position = Vector2(-100.0, 270.0)
	await ctx.await_frame()
	if not ctx.check(respawn_meteor.position != Vector2(-100.0, 270.0), "meteor respawn is inactive"):
		return false

	var detail_planet: Planet = null
	for planet_child in field.get_children():
		if planet_child is Planet:
			detail_planet = planet_child as Planet
			break
	if not ctx.check(detail_planet != null, "no planet available for detail fidelity test"):
		return false
	var details_node: PlanetDetails = detail_planet.get_node("PlanetDetails") as PlanetDetails
	if not ctx.check(details_node.get_detail_types().size() <= 3, "planet details exceed the max detail cap"):
		return false
	details_node.set_seed(777)
	var seeded_types := details_node.get_detail_types()
	details_node.set_seed(777)
	if not ctx.check(seeded_types == details_node.get_detail_types() and seeded_types.size() >= 2 and seeded_types.has(&"satellite") and seeded_types.has(&"asteroid_belt"), "planet details are not seed-stable"):
		return false
	var orbit: PlanetDetailOrbit = details_node.get_node("AsteroidOrbit_0") as PlanetDetailOrbit
	var satellite_orbit: PlanetDetailOrbit = details_node.get_node_or_null("Satellite") as PlanetDetailOrbit
	if not ctx.check(satellite_orbit != null and satellite_orbit.orbit_motion_mode == PlanetDetailFidelity.MOTION_FULL and orbit.orbit_motion_mode == PlanetDetailFidelity.MOTION_THROTTLED and orbit.orbit_update_interval > 0.0, "detail motion fidelity was not applied"):
		return false
	var orbit_angle: float = orbit.rotation
	var satellite_angle: float = satellite_orbit.rotation
	var orbit_moved := false
	var satellite_moved := false
	# Throttled fidelity intentionally updates on its configured cadence, which
	# can span several fast headless frames. Wait on the observable condition,
	# not on one arbitrary frame.
	for _frame in 8:
		await ctx.await_frame()
		orbit_moved = orbit_moved or absf(orbit.rotation - orbit_angle) > 0.001
		satellite_moved = satellite_moved or absf(satellite_orbit.rotation - satellite_angle) > 0.001
		if orbit_moved and satellite_moved:
			break
	if not ctx.check(orbit_moved and satellite_moved, "Toxic detail orbit is inactive"):
		return false
	for child in field.get_children():
		if child is Planet:
			var details: PlanetDetails = child.get_node("PlanetDetails") as PlanetDetails
			if not ctx.check(details.get_detail_types().size() <= 3, "%s has too many planet details" % child.name):
				return false

	var scene: PackedScene = preload("res://scenes/backgrounds/starfield_background.tscn")
	if not await _run_layout_scale_case(ctx, field, planet_catalog, Vector2(960.0, 540.0), 6, 3, original_seed + 101):
		ctx.check(false, "960x540 scaled layout case failed")
		return false
	if not await _run_layout_scale_case(ctx, field, planet_catalog, Vector2(1920.0, 1080.0), 14, 7, original_seed + 202):
		ctx.check(false, "1920x1080 scaled layout case failed")
		return false
	if not await _run_layout_scale_case(ctx, field, planet_catalog, Vector2(1600.0, 900.0), 120, 0, original_seed + 404):
		ctx.check(false, "auto-column scaled layout case failed")
		return false
	if not await _run_scenario_case(ctx, scene, scenario_catalog, &"wide"):
		ctx.check(false, "wide scenario selection case failed")
		return false
	return true


func _run_layout_scale_case(ctx: PreflightContext, source_field: Node, base_catalog: PlanetCatalog, design_size: Vector2, planet_count: int, columns: int, seed: int) -> bool:
	var scene: PackedScene = preload("res://scenes/objects/planets/planet_field.tscn")
	var custom_field: Node = scene.instantiate()
	var custom_config: WorldConfig = (source_field.get("world_config") as WorldConfig).duplicate(true) as WorldConfig
	custom_config.design_size = design_size
	custom_config.columns = columns
	custom_config.layout_seed = seed
	custom_config.extra_large_count = mini(custom_config.extra_large_count, planet_count)
	custom_config.large_count = mini(custom_config.large_count, maxi(0, planet_count - custom_config.extra_large_count))
	custom_field.set("world_config", custom_config)
	custom_field.set("planet_catalog", ctx.catalog_for_count(base_catalog, planet_count))
	custom_field.set("position", Vector2(37.0, -29.0))
	custom_field.set("size_profiles", source_field.get("size_profiles"))
	ctx.root().add_child(custom_field)
	await ctx.await_frame()

	var planets: Array[Planet] = []
	var slots: Dictionary = {}
	for child in custom_field.get_children():
		if child is Planet:
			planets.append(child)
			var slot: int = int(child.get_meta("layout_slot", -1))
			if slot < 0 or slot >= planet_count or slots.has(slot):
				custom_field.queue_free()
				await ctx.await_frame()
				return false
			slots[slot] = true
			if child.position.x < custom_config.padding or child.position.x > design_size.x - custom_config.padding:
				custom_field.queue_free()
				await ctx.await_frame()
				return false
			if child.position.y < custom_config.padding or child.position.y > design_size.y - custom_config.padding:
				custom_field.queue_free()
				await ctx.await_frame()
				return false
	var network: Node = custom_field.get_node("PlanetNetwork")
	var navigation: NavigationField = custom_field.get_node("NavigationField") as NavigationField
	var route_count: int = 0
	if not planets.is_empty():
		route_count = network.get_route_destinations(planets[0]).size()
	var expected_route_count: int = planet_count - 1
	var expected_waypoint_count: int = 0
	for planet in planets:
		expected_waypoint_count += network.get_neighbors(planet).size()
	expected_waypoint_count = int(float(expected_waypoint_count) / 2.0)
	var route_path: Array[Vector2] = []
	if planets.size() >= 2:
		route_path = network.get_route_path(planets[0], planets[1])
	var navigation_valid: bool = navigation != null and navigation.get_waypoint_count() == expected_waypoint_count and (planets.size() < 2 or route_path.size() >= 3)
	var passed: bool = planets.size() == planet_count and slots.size() == planet_count and route_count == expected_route_count and navigation_valid
	custom_field.queue_free()
	await ctx.await_frame()
	return passed


func _run_scenario_case(ctx: PreflightContext, scene: PackedScene, catalog: ScenarioCatalog, scenario_id: StringName) -> bool:
	var scenario_background: Node = scene.instantiate()
	scenario_background.set("scenario_catalog", catalog)
	scenario_background.set("active_scenario_id", scenario_id)
	ctx.root().add_child(scenario_background)
	await ctx.await_frame()

	var active_scenario: ScenarioDefinition = scenario_background.get("active_scenario") as ScenarioDefinition
	var map: MapDefinition = null
	if active_scenario != null:
		map = active_scenario.map_definition
	var field: Node = scenario_background.get_node("PlanetField")
	var scenario_world: WorldConfig = field.get("world_config") as WorldConfig
	var scenario_navigation: NavigationField = field.get_node("NavigationField") as NavigationField
	var scenario_network: Node = field.get_node("PlanetNetwork")
	var planets: Array[Planet] = []
	for child in field.get_children():
		if child is Planet:
			planets.append(child)
	var route_count: int = 0
	var neighbor_count: int = 0
	if not planets.is_empty():
		route_count = scenario_network.get_route_destinations(planets[0]).size()
		neighbor_count = scenario_network.get_neighbors(planets[0]).size()
	var fixed_seed_applied: bool = map != null and scenario_world != null and scenario_world.layout_seed == map.world_config.layout_seed
	var scenario_waypoint_catalog: NavigationWaypointCatalog = null
	if map != null and map.navigation_config != null:
		scenario_waypoint_catalog = map.navigation_config.waypoint_catalog
	var wide_waypoint_cadence_valid: bool = scenario_waypoint_catalog != null and scenario_waypoint_catalog.definition_for_edge(0).id == &"comet_sparse" and scenario_waypoint_catalog.definition_for_edge(1).id == &"moon" and scenario_waypoint_catalog.definition_for_edge(3).id == &"comet_sparse"
	var field_catalog: PlanetCatalog = field.get("planet_catalog") as PlanetCatalog
	var passed: bool = active_scenario != null and active_scenario.id == scenario_id and active_scenario.route_mode == ScenarioDefinition.ROUTE_MODE_NEIGHBORS_ONLY and not active_scenario.randomize_layout_seed and map != null and scenario_world != null and scenario_world.design_size.distance_to(Vector2(1920.0, 1080.0)) <= 0.01 and scenario_world.route_mode == active_scenario.route_mode and scenario_world.route_mode == WorldConfig.ROUTE_MODE_NEIGHBORS_ONLY and field_catalog != null and field_catalog.planets.size() == planets.size() and scenario_navigation.get("navigation_config") == map.navigation_config and scenario_waypoint_catalog != null and scenario_waypoint_catalog.definitions.size() >= 2 and scenario_waypoint_catalog != (preload("res://resources/config/navigation_default.tres") as NavigationConfig).waypoint_catalog and wide_waypoint_cadence_valid and planets.size() == map.world_config.target_planet_count and route_count == neighbor_count and fixed_seed_applied
	scenario_background.queue_free()
	await ctx.await_frame()
	return passed
