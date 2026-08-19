extends SceneTree

const _FlightTime := preload("res://scripts/flight_time.gd")
const _Dispatch := preload("res://scripts/dispatch.gd")

var _observed_planet: Node2D
var _observed_state := -1
var _observed_amount := -1
var _observed_faction_planet: StringName = &""
var _observed_old_faction: StringName = &""
var _observed_new_faction: StringName = &""

# Shared references captured once during scene boot and reused by the constraints.
var _background: Node
var _field: Node
var _network: Node
var _manager: Node
var _game_state: Node
var _world_config: WorldConfig
var _planet_catalog: PlanetCatalog
var _scenario_catalog: ScenarioCatalog
var _upgrade_catalog: PlanetUpgradeCatalog
var _original_seed := 0

func _init() -> void:
	if not _constraint_flight_and_dispatch():
		return
	if not await _constraint_scene_boot():
		return
	if not await _constraint_resources_and_seed():
		return
	if not await _constraint_world_planets_and_dispatch():
		return
	if not await _constraint_world_details_and_scale():
		return
	if not await _constraint_upgrades_missions_and_ai():
		return
	if not await _constraint_scout_and_discovery():
		return
	if not await _constraint_event_log():
		return
	print("PASS: SnipWar preflight")
	quit()

func _constraint_flight_and_dispatch() -> bool:
	if not _check(is_equal_approx(_FlightTime.seconds_for(100.0, 1), 8.0), "flight time baseline is wrong"):
		return false
	if not _check(is_equal_approx(_FlightTime.seconds_for(100.0, 2), 8.4), "flight time unit load is wrong"):
		return false
	if not _check(is_equal_approx(_FlightTime.seconds_for(200.0, 5), 17.6), "flight time medium load is wrong"):
		return false
	if not _check(_FlightTime.seconds_for(100.0, 6) > _FlightTime.seconds_for(100.0, 5), "flight time unit scaling is wrong"):
		return false
	if not _check(_Dispatch.cluster_groups(1) == [1] and _Dispatch.cluster_groups(4) == [1, 1, 1, 1] and _Dispatch.cluster_groups(5) == [5] and _Dispatch.cluster_groups(7) == [5, 1, 1] and _Dispatch.cluster_groups(100) == [100], "cluster packing thresholds are wrong"):
		return false
	if not _check(_Dispatch.cluster_tier(4) == &"k" and _Dispatch.cluster_tier(5) == &"m" and _Dispatch.cluster_tier(99) == &"m" and _Dispatch.cluster_tier(100) == &"l", "cluster tier boundaries are wrong"):
		return false
	if not _check(_Dispatch.cluster_tier(1, null, 1) == &"m" and _Dispatch.cluster_tier(5, null, 1) == &"l" and _Dispatch.cluster_tier(100, null, 1) == &"l", "cluster tier bonus does not unlock heavier visible tiers"):
		return false
	if not _check(_Dispatch.cluster_tier(1, null, -1) == &"k", "negative cluster tier bonus should not lower a tier"):
		return false
	if not _check(_Dispatch.amount_range(3) == Vector2i(1, 3), "dispatch range for three units is wrong"):
		return false
	if not _check(_Dispatch.amount_range(1) == Vector2i(1, 1), "dispatch range for one unit is wrong"):
		return false
	if not _check(_Dispatch.amount_range(0) == Vector2i.ZERO, "dispatch range for empty planet is wrong"):
		return false
	if not _check(_Dispatch.amount_range(-1) == Vector2i.ZERO, "dispatch range for negative count is wrong"):
		return false
	if not _check(_Dispatch.launch_amount(3, 2) == 2, "launch amount should match request"):
		return false
	if not _check(_Dispatch.launch_amount(2, 5) == 2, "launch amount should clamp to available"):
		return false
	if not _check(_Dispatch.launch_amount(0, 3) == 0, "launch amount from empty planet should be zero"):
		return false
	if not _check(_Dispatch.launch_amount(3, 0) == 0, "launch amount with zero requested should be zero"):
		return false
	return true

func _constraint_scene_boot() -> bool:
	var scene: PackedScene = preload("res://scenes/backgrounds/starfield_background.tscn")
	_background = scene.instantiate()
	root.add_child(_background)
	await process_frame
	await process_frame

	var background: Node = _background
	var background_node: Node2D = background as Node2D
	var field: Node = background.get_node("PlanetField")
	var planet_field_node: Node2D = field as Node2D
	var meteor_field_node: Node2D = background.get_node("MeteorField") as Node2D
	if not _check(background_node.global_position.distance_to(Vector2.ZERO) <= 0.01, "Background has an unexpected scene offset"):
		return false
	if not _check(planet_field_node.position.distance_to(Vector2.ZERO) <= 0.01 and planet_field_node.global_position.distance_to(background_node.global_position) <= 0.01, "PlanetField has an unexpected scene offset"):
		return false
	if not _check(meteor_field_node.position.distance_to(Vector2.ZERO) <= 0.01 and meteor_field_node.global_position.distance_to(background_node.global_position) <= 0.01, "MeteorField has an unexpected scene offset"):
		return false
	var world_config: WorldConfig = field.get("world_config") as WorldConfig
	if not _check(world_config != null, "world config is missing"):
		return false
	var viewport_size: Vector2 = get_root().get_viewport().get_visible_rect().size
	if not _check(viewport_size.distance_to(world_config.design_size) <= 0.01, "world design size differs from the Godot viewport"):
		return false
	var game_state: Node = get_root().get_node_or_null("GameState")
	if not _check(game_state != null, "GameState autoload is missing"):
		return false
	if not game_state.faction_changed.is_connected(_capture_faction_changed):
		game_state.faction_changed.connect(_capture_faction_changed)
	if not _check(game_state.validate().is_empty(), "GameState ownership validation failed"):
		return false
	var scenario_catalog: ScenarioCatalog = background.get("scenario_catalog") as ScenarioCatalog
	if not _check(scenario_catalog != null and scenario_catalog.validate().is_empty(), "scenario catalog validation failed"):
		return false
	var active_scenario: ScenarioDefinition = background.get("active_scenario") as ScenarioDefinition
	if not _check(active_scenario != null and active_scenario.id == &"default", "default scenario was not selected"):
		return false
	if not _check(active_scenario.route_mode == ScenarioDefinition.ROUTE_MODE_ALL_PLANETS and active_scenario.route_mode == world_config.route_mode, "default scenario route rule was not applied"):
		return false
	if not _check(active_scenario.map_definition != null and active_scenario.map_definition.world_config == world_config, "active scenario map was not applied"):
		return false
	var background_config: BackgroundConfig = background.get("background_config") as BackgroundConfig
	if not _check(background_config != null and background_config.validate().is_empty(), "background config validation failed"):
		return false
	var background_render_stats: Dictionary = background.call("get_render_batch_stats")
	var background_batch_count: int = int(background_render_stats.get("batch_count", 0))
	var background_batched_elements: int = int(background_render_stats.get("batched_elements", 0))
	var background_source_elements: int = int(background_render_stats.get("source_elements", 0))
	var background_fold_alpha_draw_calls: int = int(background_render_stats.get("fold_alpha_draw_calls", 0))
	var background_grain_alpha_draw_calls: int = int(background_render_stats.get("grain_alpha_draw_calls", 0))
	var background_draw_calls: int = int(background_render_stats.get("estimated_draw_calls", 0))
	if not _check(background_batch_count >= 2 and background_batch_count <= 3, "background render batches are missing"):
		return false
	if not _check(background_batched_elements == background_config.star_count + background_config.dust_count, "background batched element count is wrong"):
		return false
	if not _check(background_config.fold_alpha_bucket_count >= 2 and background_config.grain_alpha_bucket_count >= 2, "background alpha fidelity is still averaged"):
		return false
	if not _check(background_fold_alpha_draw_calls >= 2 and background_fold_alpha_draw_calls <= background_config.fold_alpha_bucket_count and background_grain_alpha_draw_calls >= 2 and background_grain_alpha_draw_calls <= background_config.grain_alpha_bucket_count, "background alpha fidelity buckets are incomplete"):
		return false
	if not _check(background_source_elements > background_draw_calls * 4 and background_draw_calls <= 24, "background draw-call budget is not compressed"):
		return false
	var meteor_config: MeteorConfig = background.get_node("MeteorField").get("meteor_config") as MeteorConfig
	if not _check(meteor_config != null and meteor_config.validate().is_empty(), "meteor config validation failed"):
		return false
	var planet_catalog: PlanetCatalog = field.get("planet_catalog") as PlanetCatalog
	if not _check(planet_catalog != null, "planet catalog is missing"):
		return false
	var catalog_errors := planet_catalog.validate()
	if not _check(catalog_errors.is_empty(), "planet catalog validation failed"):
		return false
	if not _check(game_state.validate_starting_setup().is_empty(), "GameState starting setup validation failed"):
		return false
	if not _check(game_state.get_ownership_count(GameState.FACTION_NEUTRAL) == 8 and game_state.get_ownership_count(GameState.FACTION_PLAYER) == 1 and game_state.get_ownership_count(GameState.FACTION_CPU) == 1, "GameState ownership seed does not match the default catalog"):
		return false
	if not _check(game_state.homeworld_for(GameState.FACTION_PLAYER) == &"ocean" and game_state.homeworld_for(GameState.FACTION_CPU) == &"paper", "GameState homeworld assignment is wrong"):
		return false

	_field = field
	_network = field.get_node("PlanetNetwork")
	_manager = field.get_node("WorkerManager")
	_game_state = game_state
	_world_config = world_config
	_planet_catalog = planet_catalog
	_scenario_catalog = scenario_catalog
	_upgrade_catalog = preload("res://resources/config/planet_upgrade_catalog_default.tres")
	return true

func _constraint_resources_and_seed() -> bool:
	var field: Node = _field
	var game_state: Node = _game_state
	var world_config: WorldConfig = _world_config
	var planet_catalog: PlanetCatalog = _planet_catalog
	if not _check(game_state.faction_of(&"toxic") == GameState.FACTION_NEUTRAL and game_state.faction_of(&"volcanic") == GameState.FACTION_NEUTRAL and game_state.faction_of(&"ember") == GameState.FACTION_NEUTRAL, "GameState faction lookup is wrong"):
		return false
	var resource_pool: ResourcePool = preload("res://resources/config/resource_pool_default.tres")
	if not _check(resource_pool != null and resource_pool.validate().is_empty(), "resource pool validation failed"):
		return false
	if not _check(game_state.call("validate_resources", resource_pool).is_empty(), "GameState resource deal failed"):
		return false
	if not _check(not String(game_state.resource_of(&"ocean")).is_empty() and not String(game_state.resource_of(&"paper")).is_empty() and game_state.resource_of(&"ocean") != game_state.resource_of(&"paper"), "homeworld resources are not distinct"):
		return false
	var resource_seed: int = world_config.layout_seed
	var resource_snapshot_before: Dictionary = game_state.call("resource_snapshot")
	game_state.call("deal_resources", planet_catalog, resource_pool, resource_seed)
	var resource_snapshot_after: Dictionary = game_state.call("resource_snapshot")
	if not _check(resource_snapshot_before == resource_snapshot_after, "resource deal is not seed-deterministic"):
		return false
	var scale_resource_catalog: PlanetCatalog = _catalog_for_count(planet_catalog, 1500)
	game_state.call("deal_resources", scale_resource_catalog, resource_pool, 424242)
	if not _check(game_state.call("validate_resources", resource_pool).is_empty(), "1500-planet resource deal is unbalanced"):
		return false
	game_state.call("deal_resources", planet_catalog, resource_pool, resource_seed)
	var positions_before: Dictionary = _planet_positions(field)
	if not _check(positions_before.size() == planet_catalog.planets.size(), "generated planets do not match the catalog"):
		return false
	for initial_planet in field.get_children():
		if initial_planet is Planet:
			var expected_initial_workers: int = game_state.starting_workers_of((initial_planet as Planet).planet_id)
			if not _check((initial_planet as Planet).worker_count == expected_initial_workers, "%s initial worker distribution is wrong" % initial_planet.name):
				return false
	for planet_node in field.get_children():
		if planet_node is Planet:
			var global_planet_position: Vector2 = (planet_node as Planet).global_position
			if not _check(global_planet_position.x >= -0.01 and global_planet_position.x <= world_config.design_size.x + 0.01 and global_planet_position.y >= -0.01 and global_planet_position.y <= world_config.design_size.y + 0.01, "planet global position is outside world bounds"):
				return false
	var world_errors := world_config.validate_for_planet_count(positions_before.size())
	if not _check(world_errors.is_empty(), "world config validation failed"):
		return false
	var configured_profiles: Array[PlanetSizeProfile] = []
	for profile_value in field.get("size_profiles"):
		var profile: PlanetSizeProfile = profile_value as PlanetSizeProfile
		if profile != null:
			configured_profiles.append(profile)
	var profile_errors := world_config.validate_profiles(configured_profiles)
	if not _check(profile_errors.is_empty(), "planet size profile validation failed"):
		return false

	var original_seed: int = world_config.layout_seed
	field.call("set_layout_seed", original_seed + 1)
	await process_frame
	await process_frame
	var positions_changed := false
	for planet in positions_before:
		if positions_before[planet].distance_to((planet as Planet).position) > 1.0:
			positions_changed = true
			break
	if not _check(positions_changed, "changing the layout seed did not change planet positions"):
		return false
	field.call("set_layout_seed", original_seed)
	await process_frame
	await process_frame
	_original_seed = original_seed
	return true

func _constraint_world_planets_and_dispatch() -> bool:
	var background: Node = _background
	var field: Node = _field
	var network: Node = _network
	var game_state: Node = _game_state
	var world_config: WorldConfig = _world_config
	var planet_catalog: PlanetCatalog = _planet_catalog
	var manager: Node = _manager
	var navigation: NavigationField = field.get_node("NavigationField") as NavigationField
	var ui: PlanetNetworkUI = network.get_ui()
	var economy_manager: Node = field.get_node_or_null("EconomyManager")
	var cpu_ai: Node = field.get_node_or_null("CpuDispatchAI")
	if not _check(economy_manager != null and cpu_ai != null, "runtime economy and CPU modules are missing"):
		return false
	var economy_config: EconomyConfig = economy_manager.get("economy_config") as EconomyConfig
	var cpu_dispatch_config: CpuDispatchConfig = cpu_ai.get("dispatch_config") as CpuDispatchConfig
	if not _check(economy_config != null and economy_config.validate().is_empty(), "economy config validation failed"):
		return false
	if not _check(cpu_dispatch_config != null and cpu_dispatch_config.validate().is_empty(), "CPU dispatch config validation failed"):
		return false
	# Keep the persistent suite deterministic; both modules expose manual test hooks.
	economy_manager.call("set_enabled", false)
	cpu_ai.call("set_enabled", false)
	if not _check(navigation != null, "navigation field is missing"):
		return false
	var navigation_config: NavigationConfig = navigation.get("navigation_config") as NavigationConfig
	if not _check(navigation_config != null and navigation_config.validate().is_empty(), "navigation config validation failed"):
		return false
	if not _check(navigation_config.waypoint_catalog != null and navigation_config.waypoint_catalog.definitions.size() >= 2, "navigation waypoint catalog is missing styles"):
		return false
	var first_waypoint_definition: NavigationWaypointDefinition = navigation_config.waypoint_for_edge(0)
	var second_waypoint_definition: NavigationWaypointDefinition = navigation_config.waypoint_for_edge(1)
	if not _check(first_waypoint_definition != null and second_waypoint_definition != null and first_waypoint_definition.waypoint_type == "comet" and second_waypoint_definition.waypoint_type == "moon", "default waypoint catalog cadence is wrong"):
		return false
	var expected_waypoint_count: int = 0
	for navigation_planet in field.get_children():
		if navigation_planet is Planet:
			expected_waypoint_count += network.get_neighbors(navigation_planet).size()
	expected_waypoint_count = int(float(expected_waypoint_count) / 2.0)
	if not _check(navigation.get_waypoint_count() == expected_waypoint_count and expected_waypoint_count > 0, "navigation waypoint count is wrong"):
		return false
	var graph_edges: Array[Array] = navigation.get_edges()
	var rendered_waypoint_count: int = 0
	for waypoint_node in navigation.get_children():
		if waypoint_node is NavigationWaypoint:
			rendered_waypoint_count += 1
			var waypoint_sprite: Sprite2D = waypoint_node.get_node_or_null("Sprite2D") as Sprite2D
			var waypoint_position: Vector2 = (waypoint_node as Node2D).global_position
			var waypoint_on_graph: bool = false
			for edge in graph_edges:
				if edge.size() == 2 and (waypoint_position.distance_to(edge[0]) <= 0.05 or waypoint_position.distance_to(edge[1]) <= 0.05):
					waypoint_on_graph = true
					break
			if not _check((waypoint_node as NavigationWaypoint).waypoint_type == &"moon" or (waypoint_node as NavigationWaypoint).waypoint_type == &"comet", "navigation waypoint type is invalid"):
				return false
			if not _check(waypoint_sprite != null and waypoint_sprite.texture != null and waypoint_sprite.scale.x > 0.0, "navigation waypoint visual is missing"):
				return false
			if not _check(waypoint_on_graph, "navigation waypoint is detached from its graph edge"):
				return false
	if not _check(rendered_waypoint_count == expected_waypoint_count, "navigation waypoint visuals are incomplete"):
		return false
	var ui_theme_config: UIThemeConfig = network.get("ui_theme_config") as UIThemeConfig
	if not _check(ui_theme_config != null and ui_theme_config.validate().is_empty(), "UI theme config validation failed"):
		return false
	if not _check(ui_theme_config.route_line_width > 0.0 and ui_theme_config.route_line_alpha > 0.0 and ui_theme_config.route_line_alpha + ui_theme_config.route_line_pulse_alpha <= 1.0, "route visualization config is invalid"):
		return false
	var transit_config: TransitConfig = manager.get("transit_config") as TransitConfig
	if not _check(transit_config != null, "transit config is missing"):
		return false
	if not _check(network.transit_config_identity_valid(), "PlanetNetwork and WorkerManager use different TransitConfig resources"):
		return false
	var transit_errors := transit_config.validate()
	if not _check(transit_errors.is_empty(), "transit config validation failed"):
		return false
	var default_detail_profile: PlanetDetailProfile = preload("res://resources/config/planet_details/default.tres")
	var toxic_detail_profile: PlanetDetailProfile = preload("res://resources/config/planet_details/toxic.tres")
	if not _check(default_detail_profile.validate().is_empty() and toxic_detail_profile.validate().is_empty(), "planet detail profiles are invalid"):
		return false
	var satellite_definition: PlanetDetailDefinition = preload("res://resources/config/planet_details/satellite.tres")
	var asteroid_definition: PlanetDetailDefinition = preload("res://resources/config/planet_details/asteroid_belt.tres")
	if not _check(satellite_definition.validate().is_empty() and satellite_definition.fidelity != null and satellite_definition.fidelity.orbit_motion_mode == PlanetDetailFidelity.MOTION_FULL and satellite_definition.angular_speed_range.y > satellite_definition.angular_speed_range.x, "satellite detail fidelity config is invalid"):
		return false
	if not _check(asteroid_definition.validate().is_empty() and asteroid_definition.fidelity != null and asteroid_definition.fidelity.orbit_motion_mode == PlanetDetailFidelity.MOTION_THROTTLED and asteroid_definition.fidelity.orbit_update_interval > 0.0, "asteroid detail fidelity config is invalid"):
		return false
	var source: Planet = _find_planet_with_size(field, &"xl") as Planet
	var large_planet: Node = _find_planet_with_size(field, &"l")
	var variable_planet: Node = _find_planet_with_size(field, &"variable")
	if not _check(source != null and large_planet != null and variable_planet != null, "generated planet sizes are missing"):
		return false
	var source_starting_workers: int = source.worker_count
	var source_faction: StringName = source.get_faction()
	if not _check(source_faction == game_state.faction_of(source.planet_id) and source.is_in_group("faction_" + String(source_faction)), "planet faction does not follow the GameState source of truth"):
		return false
	game_state.set_faction(source.planet_id, GameState.FACTION_CPU)
	await process_frame
	if not _check(source.get_faction() == GameState.FACTION_CPU and game_state.faction_of(source.planet_id) == GameState.FACTION_CPU and source.is_in_group("faction_" + String(GameState.FACTION_CPU)) and not source.is_in_group("faction_" + String(source_faction)), "GameState faction change did not propagate to the planet"):
		return false
	game_state.set_faction(source.planet_id, source_faction)
	await process_frame
	if not _check(source.get_faction() == source_faction and game_state.faction_of(source.planet_id) == source_faction, "GameState faction revert was not applied"):
		return false
	if not _check(_count_planets_with_size(field, &"xl") == 2 and _count_planets_with_size(field, &"l") == 1, "generated planet size distribution is wrong"):
		return false
	var source_timer: Timer = _find_timer(source)
	var large_timer: Timer = _find_timer(large_planet)
	var variable_timer: Timer = _find_timer(variable_planet)

	if not _check(planet_catalog.planets.size() == 10, "default planet catalog size is wrong"):
		return false
	if not _check(get_nodes_in_group("planets").size() == planet_catalog.planets.size(), "planet group count is wrong"):
		return false
	if not _check(source_timer.wait_time == 5.0 and large_timer.wait_time == 7.0 and variable_timer.wait_time == 10.0, "spawn intervals are wrong"):
		return false

	var player_vault_before_spawn: Dictionary = game_state.get_faction_vault_snapshot(GameState.FACTION_PLAYER)
	var cpu_vault_before_spawn: Dictionary = game_state.get_faction_vault_snapshot(GameState.FACTION_CPU)
	_observed_planet = source
	source.workers_spawn_requested.connect(_capture_spawn)
	source.call("_on_spawn_timer")
	large_planet.call("_on_spawn_timer")
	variable_planet.call("_on_spawn_timer")
	await process_frame
	if not _check(_observed_state == 1 and _observed_amount == 3 and int(source.worker_state) == 0, "planet state transition is wrong"):
		return false
	if not _check(source.worker_count == source_starting_workers + 3 and large_planet.worker_count == game_state.starting_workers_of((large_planet as Planet).planet_id) + 2 and variable_planet.worker_count == game_state.starting_workers_of((variable_planet as Planet).planet_id) + 1, "planet worker counts are wrong"):
		return false
	var source_strength_label: Label = source.get_node_or_null("StrengthLabel") as Label
	if not _check(source_strength_label != null and source_strength_label.text == str(source.worker_count), "planet strength indicator does not match worker count"):
		return false
	if not _check(player_vault_before_spawn == game_state.get_faction_vault_snapshot(GameState.FACTION_PLAYER) and cpu_vault_before_spawn == game_state.get_faction_vault_snapshot(GameState.FACTION_CPU), "worker spawn timer still changes passive economy"):
		return false
	var economy_planet: Planet = _find_planet_by_id(field, game_state.homeworld_for(GameState.FACTION_PLAYER))
	if not _check(economy_planet != null, "player homeworld for economy test is missing"):
		return false
	var economy_resource_id: StringName = game_state.resource_of(economy_planet.planet_id)
	var economy_before: int = game_state.get_faction_resource(GameState.FACTION_PLAYER, economy_resource_id)
	var economy_generated: int = economy_manager.call("tick_now")
	var economy_after: int = game_state.get_faction_resource(GameState.FACTION_PLAYER, economy_resource_id)
	if not _check(economy_generated > 0 and economy_after >= economy_before + economy_planet.get_size_profile().resource_base, "independent economy tick did not generate resources"):
		return false

	var cluster_script: Script = preload("res://scripts/objects/workers/worker_cluster.gd")
	if not _check(manager.get_child_count() == 0, "idle units should remain count-only"):
		return false
	var source_count_label: Label = ui.get_count_label(source)
	if not _check(source_count_label.text == "%s: %d" % [source.name, source.worker_count], "planet tab count is not live"):
		return false

	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	source.call("_on_click_area_input_event", null, event, 0)
	await process_frame
	var panel: PanelContainer = ui.get_panel()
	var destination_option: OptionButton = ui.get_destination_option()
	var neighbors: Array[Node2D] = network.get_neighbors(source)
	var route_destinations: Array[Node2D] = network.get_route_destinations(source)
	if not _check(world_config.route_mode == WorldConfig.ROUTE_MODE_ALL_PLANETS, "default route mode is not all_planets"):
		return false
	var original_route_mode := world_config.route_mode
	world_config.route_mode = WorldConfig.ROUTE_MODE_NEIGHBORS_ONLY
	if not _check(network.get_route_destinations(source).size() == neighbors.size(), "neighbors_only route mode is not enforced"):
		return false
	world_config.route_mode = original_route_mode
	if not _check(panel.visible and destination_option.item_count == route_destinations.size() and route_destinations.size() == 9 and not neighbors.is_empty(), "planet tab or neighbors are missing"):
		return false
	await process_frame
	var tab_button: Button = ui.get_node("PlanetTabUI/PlanetTab") as Button
	var heading_label: Label = ui.get_node("PlanetTabUI/PlanetPanel/MarginContainer/PanelScroll/Content/HeadingLabel") as Label
	var selected_count_label: Label = ui.get_node("PlanetTabUI/PlanetPanel/MarginContainer/PanelScroll/Content/SelectedCountLabel") as Label
	if not _check(tab_button.get_theme_font_size("font_size") == ui_theme_config.tab_font_size and heading_label.get_theme_font_size("font_size") == ui_theme_config.heading_font_size and selected_count_label.get_theme_font_size("font_size") == ui_theme_config.selected_count_font_size, "UI theme font sizes are not applied from the config"):
		return false
	var panel_width: float = panel.size.x
	if not _check(panel_width >= ui_theme_config.panel_min_width - 0.1 and panel_width <= ui_theme_config.panel_max_width + 0.1, "responsive UI panel width is outside the configured range (got %f)" % panel_width):
		return false
	var vault_bar: PanelContainer = ui.get_node("PlanetTabUI/VaultBar") as PanelContainer
	var panel_scroll: ScrollContainer = panel.get_node("MarginContainer/PanelScroll") as ScrollContainer
	if not _check(vault_bar != null and vault_bar.global_position.x + vault_bar.size.x <= panel.global_position.x + 0.1, "resource HUD overlaps the planet panel"):
		return false
	if not _check(panel_scroll != null and panel_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO, "planet panel does not provide a scrollable menu"):
		return false
	var amount_slider: HSlider = ui.get_amount_slider()
	var preview_label: Label = ui.get_preview_label()
	if not _check(is_instance_valid(amount_slider) and is_instance_valid(preview_label), "dispatch slider or preview is missing"):
		return false
	if not _check(amount_slider.min_value == 1 and amount_slider.max_value == source.worker_count and amount_slider.step == 1, "dispatch slider bounds are wrong"):
		return false
	var preview_destination: Node2D = network.get_destination(source)
	var preview_path: Array[Vector2] = network.get_route_path(source, preview_destination)
	var preview_route_distance: float = _path_distance(preview_path)
	var non_neighbor_destination: Node2D = null
	for candidate in route_destinations:
		if not neighbors.has(candidate):
			non_neighbor_destination = candidate
			break
	if not _check(non_neighbor_destination != null, "all_planets has no non-neighbor destination for multi-hop validation"):
		return false
	var multi_hop_path: Array[Vector2] = network.get_route_path(source, non_neighbor_destination)
	if not _check(multi_hop_path.size() >= 5 and _path_contains_planet(multi_hop_path, field, source, non_neighbor_destination), "all_planets non-neighbor route does not traverse the navigation graph"):
		return false
	var direct_distance: float = source.global_position.distance_to(preview_destination.global_position)
	var expected_preview_seconds: float = _FlightTime.seconds_for(preview_route_distance, ui.selected_amount(), transit_config)
	if not _check(preview_path.size() >= 3 and preview_route_distance >= direct_distance, "dispatch preview does not use the navigation path"):
		return false
	if not _check(absf(_flight_seconds(preview_label.text) - expected_preview_seconds) <= 0.11, "dispatch preview does not use real route distance"):
		return false
	var preview_seconds_before: float = _flight_seconds(preview_label.text)
	var alternate: Node2D = preview_destination
	for candidate in neighbors:
		if candidate == preview_destination:
			continue
		var candidate_path: Array[Vector2] = network.get_route_path(source, candidate)
		var candidate_distance: float = _path_distance(candidate_path)
		if absf(candidate_distance - preview_route_distance) > 0.1:
			alternate = candidate
			break
	if not _check(alternate != preview_destination, "no alternate destination with different distance"):
		return false
	var alternate_index := ui.index_of_destination(alternate.name)
	if not _check(alternate_index >= 0, "alternate destination is missing from planet tab"):
		return false
	network.call("_on_destination_selected", alternate_index)
	await process_frame
	var alternate_path: Array[Vector2] = network.get_route_path(source, alternate)
	var alternate_distance: float = _path_distance(alternate_path)
	var expected_alternate_seconds: float = _FlightTime.seconds_for(alternate_distance, ui.selected_amount(), transit_config)
	if not _check(absf(_flight_seconds(preview_label.text) - expected_alternate_seconds) <= 0.11, "destination change did not update the preview route distance"):
		return false
	if not _check(_flight_seconds(preview_label.text) != preview_seconds_before, "destination change did not alter the preview distance"):
		return false
	var preview_at_one := preview_label.text
	amount_slider.value = 2
	await process_frame
	if not _check(preview_label.text != preview_at_one and _flight_seconds(preview_label.text) > _flight_seconds(preview_at_one), "dispatch preview does not update live"):
		return false
	var panel_tab: Button = ui.get_node("PlanetTabUI/PlanetTab") as Button
	if not _check(panel_tab != null and panel_tab.text == "‹  SCHLIESSEN", "open panel tab state is wrong"):
		return false
	ui.toggle_panel()
	if not _check(not panel.visible and panel_tab.text == "PLANETEN  ›", "planet tab did not close"):
		return false
	var escape_event := InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	escape_event.pressed = true
	ui.call("_unhandled_input", escape_event)
	if not _check(not panel.visible, "escape should keep the closed panel closed"):
		return false
	ui.toggle_panel()
	if not _check(panel.visible and panel_tab.text == "‹  SCHLIESSEN", "planet tab did not reopen"):
		return false
	var line_phase: float = network.get_line_phase()
	await create_timer(0.2).timeout
	if not _check(network.get_line_phase() != line_phase, "neighbor line animation is inactive"):
		return false
	var destination: Planet = neighbors[0] as Planet
	var destination_index := ui.index_of_destination(destination.name)
	if not _check(destination_index >= 0, "destination is missing from planet tab"):
		return false
	network.call("_on_destination_selected", destination_index)
	if not _check(network.get_destination(source) == destination and panel.visible, "destination route was not stored"):
		return false
	manager.call("_spawn_clusters", source, 1)
	await process_frame
	if not _check(source.worker_count == source_starting_workers + 4 and manager.get_child_count() == 0, "idle spawn should only update the planet counter"):
		return false
	var send_button: Button = ui.get_send_button()
	if not _check(is_instance_valid(send_button) and not send_button.disabled, "send button is missing or disabled"):
		return false
	amount_slider.value = 3
	await process_frame
	var original_source_faction: StringName = source.get_faction()
	var original_destination_faction: StringName = destination.get_faction()
	var attack_faction: StringName = GameState.FACTION_PLAYER
	game_state.set_faction(source.planet_id, attack_faction)
	game_state.set_faction(destination.planet_id, GameState.FACTION_NEUTRAL)
	destination.unregister_workers(destination.worker_count)
	_observed_faction_planet = &""
	_observed_old_faction = &""
	_observed_new_faction = &""
	var destination_count_before: int = destination.worker_count
	network.call("_on_send_pressed")
	if not _check(int(source.get("worker_count")) == source_starting_workers + 1, "send did not deduct the source count"):
		return false
	var transit_clusters: Array[Node] = []
	for child in manager.get_children():
		if child.get_script() == cluster_script and child.get("destination_planet") == destination:
			transit_clusters.append(child)
	if not _check(transit_clusters.size() == 3, "send did not launch all packed cluster groups"):
		return false
	for transit in transit_clusters:
		if not _check(transit.get_unit_count() == 1 and transit.get("source_faction") == attack_faction, "cluster group sizes or source faction are wrong"):
			return false
	var route_direction: Vector2 = (destination.global_position - source.global_position).normalized()
	var route_perpendicular: Vector2 = Vector2(-route_direction.y, route_direction.x)
	var formation_groups: Array[int] = [1, 1, 1]
	var formation_spacing: float = manager.call("_formation_spacing", formation_groups)
	var expected_offsets: Array[Vector2] = manager.call("_formation_offsets", 3, route_direction, route_perpendicular, formation_spacing)
	var actual_offsets: Array[Vector2] = []
	for index in transit_clusters.size():
		var actual_offset: Vector2 = (transit_clusters[index] as Node2D).global_position - source.global_position
		actual_offsets.append(actual_offset)
		if not _check(actual_offset.distance_to(expected_offsets[index]) <= 0.05, "transit cluster formation offset is wrong"):
			return false
	if not _check(_offsets_have_safe_spacing(actual_offsets, formation_spacing), "formation clusters overlap beyond the budget"):
		return false
	var transit_distance_before: float = (transit_clusters[0] as Node2D).global_position.distance_to(destination.global_position)
	await create_timer(0.5).timeout
	var transit_distance_after: float = (transit_clusters[0] as Node2D).global_position.distance_to(destination.global_position)
	if not _check(transit_distance_after < transit_distance_before, "transit cluster does not move toward the destination"):
		return false
	var destination_offsets: Array[Vector2] = []
	for transit in transit_clusters:
		destination_offsets.append((transit as Node2D).global_position - destination.global_position)
	if not _check(_offsets_have_safe_spacing(destination_offsets, formation_spacing), "formation collapsed during transit"):
		return false
	if not _check(_offsets_match_shape(destination_offsets, expected_offsets, 0.05), "destination formation offset drifted"):
		return false
	var arrival_results: Array[StringName] = []
	for transit in transit_clusters:
		var arrival_result: StringName = manager.call("_arrive_cluster", transit)
		arrival_results.append(arrival_result)
	await process_frame
	if not _check(arrival_results.size() == 3 and arrival_results[0] == Planet.ARRIVAL_CAPTURED and arrival_results[1] == Planet.ARRIVAL_FRIENDLY and arrival_results[2] == Planet.ARRIVAL_FRIENDLY, "arrival conflict results are wrong"):
		return false
	if not _check(int(destination.get("worker_count")) == destination_count_before + 3 and destination.get_faction() == attack_faction and game_state.faction_of(destination.planet_id) == attack_faction, "capture did not transfer ownership and survivors"):
		return false
	if not _check(_observed_faction_planet == destination.planet_id and _observed_old_faction == GameState.FACTION_NEUTRAL and _observed_new_faction == attack_faction, "capture did not emit faction_changed"):
		return false
	var friendly_before: int = destination.worker_count
	var friendly_result: StringName = destination.resolve_arrival(attack_faction, 2)
	if not _check(friendly_result == Planet.ARRIVAL_FRIENDLY and destination.worker_count == friendly_before + 2, "friendly arrival did not reinforce the destination"):
		return false
	var repel_target: Planet = null
	for candidate in field.get_children():
		if candidate is Planet and candidate != source and candidate != destination and (candidate as Planet).worker_count >= 2:
			repel_target = candidate as Planet
			break
	if not _check(repel_target != null, "no defended planet available for repel test"):
		return false
	game_state.set_faction(repel_target.planet_id, GameState.FACTION_NEUTRAL)
	var repel_before: int = repel_target.worker_count
	var repel_result: StringName = repel_target.resolve_arrival(attack_faction, 1)
	if not _check(repel_result == Planet.ARRIVAL_REPELLED and repel_target.worker_count == repel_before - 1 and repel_target.get_faction() == GameState.FACTION_NEUTRAL, "defended arrival was not repelled"):
		return false
	game_state.set_faction(source.planet_id, original_source_faction)
	game_state.set_faction(destination.planet_id, original_destination_faction)
	await process_frame
	if not _check(manager.get_child_count() == 0, "arrived units should no longer render"):
		return false
	return true

func _constraint_world_details_and_scale() -> bool:
	var background: Node = _background
	var field: Node = _field
	var planet_catalog: PlanetCatalog = _planet_catalog
	var scenario_catalog: ScenarioCatalog = _scenario_catalog
	var original_seed: int = _original_seed

	var meteor_field: Node = background.get_node("MeteorField")
	var meteor_positions: Array[Vector2] = []
	for meteor in meteor_field.get_children():
		meteor_positions.append(meteor.position)
		var pixels: float = meteor.texture.get_width() * meteor.scale.x
		if not _check(pixels >= 4.0 and pixels <= 10.0, "%s pixel size is invalid" % meteor.name):
			return false
	await create_timer(0.2).timeout
	if not _check(meteor_field.get_child(0).position != meteor_positions[0], "meteor movement is inactive"):
		return false
	var respawn_meteor: Sprite2D = meteor_field.get_child(0)
	respawn_meteor.position = Vector2(-100.0, 270.0)
	await create_timer(0.05).timeout
	if not _check(respawn_meteor.position != Vector2(-100.0, 270.0), "meteor respawn is inactive"):
		return false

	var toxic_details: PlanetDetails = field.get_node("Toxic/PlanetDetails") as PlanetDetails
	var toxic_types := toxic_details.get_detail_types()
	if not _check(toxic_types.size() >= 2 and toxic_types.size() <= 3 and toxic_types.has(&"satellite") and toxic_types.has(&"asteroid_belt"), "Toxic details are incomplete"):
		return false
	var stable_types := toxic_types.duplicate()
	toxic_details.set_seed(777)
	var seeded_types := toxic_details.get_detail_types()
	toxic_details.set_seed(777)
	if not _check(seeded_types == toxic_details.get_detail_types() and stable_types.size() <= 3, "planet details are not seed-stable"):
		return false
	var orbit: PlanetDetailOrbit = toxic_details.get_node("AsteroidOrbit_0") as PlanetDetailOrbit
	var satellite_orbit: PlanetDetailOrbit = toxic_details.get_node_or_null("Satellite") as PlanetDetailOrbit
	if not _check(satellite_orbit != null and satellite_orbit.orbit_motion_mode == PlanetDetailFidelity.MOTION_FULL and orbit.orbit_motion_mode == PlanetDetailFidelity.MOTION_THROTTLED and orbit.orbit_update_interval > 0.0, "Toxic detail motion fidelity was not applied"):
		return false
	var orbit_angle: float = orbit.rotation
	var satellite_angle: float = satellite_orbit.rotation
	await create_timer(0.2).timeout
	if not _check(absf(orbit.rotation - orbit_angle) > 0.001 and absf(satellite_orbit.rotation - satellite_angle) > 0.001, "Toxic detail orbit is inactive"):
		return false
	for child in field.get_children():
		if child is Planet:
			var details: PlanetDetails = child.get_node("PlanetDetails") as PlanetDetails
			if not _check(details.get_detail_types().size() <= 3, "%s has too many planet details" % child.name):
				return false

	var scene: PackedScene = preload("res://scenes/backgrounds/starfield_background.tscn")
	if not await _run_layout_scale_case(field, planet_catalog, Vector2(960.0, 540.0), 6, 3, original_seed + 101):
		_check(false, "960x540 scaled layout case failed")
		return false
	if not await _run_layout_scale_case(field, planet_catalog, Vector2(1920.0, 1080.0), 14, 7, original_seed + 202):
		_check(false, "1920x1080 scaled layout case failed")
		return false
	if not await _run_layout_scale_case(field, planet_catalog, Vector2(9600.0, 5400.0), 1500, 50, original_seed + 303):
		_check(false, "1500-planet scaled layout case failed")
		return false
	if not await _run_scenario_case(scene, scenario_catalog, &"wide"):
		_check(false, "wide scenario selection case failed")
		return false
	return true

func _constraint_upgrades_missions_and_ai() -> bool:
	var field: Node = _field
	var network: Node = _network
	var manager: Node = _manager
	var game_state: Node = _game_state
	var world_config: WorldConfig = _world_config
	var planet_catalog: PlanetCatalog = _planet_catalog
	var upgrade_catalog: PlanetUpgradeCatalog = _upgrade_catalog
	var ui: PlanetNetworkUI = network.get_ui()
	var transit_config: TransitConfig = manager.get("transit_config") as TransitConfig

	# --- UPGRADE SYSTEM TESTS ---
	if not _check(upgrade_catalog != null and upgrade_catalog.validate().is_empty(), "upgrade catalog validation failed"):
		return false
	if not _check(upgrade_catalog.upgrades.size() == 13, "upgrade catalog should have 13 upgrades"):
		return false

	# Verify 4 branches exist
	var branches: Dictionary = {}
	for up in upgrade_catalog.upgrades:
		if up != null:
			branches[up.branch] = true
	if not _check(branches.has(&"economy") and branches.has(&"military") and branches.has(&"tech") and branches.has(&"infrastructure"), "all 4 upgrade branches must exist"):
		return false

	# Verify tier structure
	var economy_upgrades := upgrade_catalog.get_upgrades_for_branch(&"economy")
	var military_upgrades := upgrade_catalog.get_upgrades_for_branch(&"military")
	var tech_upgrades := upgrade_catalog.get_upgrades_for_branch(&"tech")
	var infra_upgrades := upgrade_catalog.get_upgrades_for_branch(&"infrastructure")

	if not _check(economy_upgrades.size() >= 3 and military_upgrades.size() >= 4 and tech_upgrades.size() >= 3 and infra_upgrades.size() >= 3, "each branch should have multiple tiers"):
		return false

	# Test upgrade prerequisite chain: extractor -> refinery/trade_post
	var extractor := upgrade_catalog.resolve(&"extractor")
	var refinery := upgrade_catalog.resolve(&"refinery")
	var trade_post := upgrade_catalog.resolve(&"trade_post")
	if not _check(extractor != null and refinery != null and trade_post != null, "core economy upgrades missing"):
		return false
	if not _check(refinery.parent_upgrade_id == &"extractor" and trade_post.parent_upgrade_id == &"extractor", "economy tier 2 should require extractor"):
		return false
	if not _check(refinery.exclusive_with == &"trade_post" and trade_post.exclusive_with == &"refinery", "refinery and trade_post should be mutually exclusive"):
		return false

	# Test military branch: shipyard -> colony_shipyard/war_shipyard
	var shipyard := upgrade_catalog.resolve(&"shipyard")
	var colony_shipyard := upgrade_catalog.resolve(&"colony_shipyard")
	var war_shipyard := upgrade_catalog.resolve(&"war_shipyard")
	if not _check(shipyard != null and colony_shipyard != null and war_shipyard != null, "military upgrades missing"):
		return false
	if not _check(colony_shipyard.parent_upgrade_id == &"shipyard" and war_shipyard.parent_upgrade_id == &"shipyard", "military tier 2 should require shipyard"):
		return false
	if not _check(colony_shipyard.exclusive_with == &"war_shipyard" and war_shipyard.exclusive_with == &"colony_shipyard", "colony_shipyard and war_shipyard should be mutually exclusive"):
		return false
	if not _check(war_shipyard.trait_definition != null and war_shipyard.trait_definition.cluster_tier_bonus == 1, "war_shipyard should unlock one heavier cluster tier"):
		return false

	# Test tech branch: tech_center -> weapon_lab/armor_lab
	var tech_center := upgrade_catalog.resolve(&"tech_center")
	var weapon_lab := upgrade_catalog.resolve(&"weapon_lab")
	var armor_lab := upgrade_catalog.resolve(&"armor_lab")
	if not _check(tech_center != null and weapon_lab != null and armor_lab != null, "tech upgrades missing"):
		return false
	if not _check(weapon_lab.parent_upgrade_id == &"tech_center" and armor_lab.parent_upgrade_id == &"tech_center", "tech tier 2 should require tech_center"):
		return false
	if not _check(weapon_lab.exclusive_with == &"armor_lab" and armor_lab.exclusive_with == &"weapon_lab", "weapon_lab and armor_lab should be mutually exclusive"):
		return false
	if not _check(weapon_lab.trait_definition != null and weapon_lab.trait_definition.cluster_tier_bonus == 1, "weapon_lab should unlock one heavier cluster tier"):
		return false

	# Test infrastructure branch: orbital_station -> colony_hub -> trade_network
	var orbital_station := upgrade_catalog.resolve(&"orbital_station")
	var colony_hub := upgrade_catalog.resolve(&"colony_hub")
	var trade_network := upgrade_catalog.resolve(&"trade_network")
	if not _check(orbital_station != null and colony_hub != null and trade_network != null, "infrastructure upgrades missing"):
		return false
	if not _check(colony_hub.parent_upgrade_id == &"orbital_station" and trade_network.parent_upgrade_id == &"colony_hub", "infrastructure chain broken"):
		return false

	# Test can_purchase_upgrade logic
	var player_homeworld: StringName = game_state.homeworld_for(GameState.FACTION_PLAYER)
	if not _check(not String(player_homeworld).is_empty(), "player homeworld missing"):
		return false

	# Capture initial resources before purchases
	var initial_energy: int = game_state.get_faction_resource(GameState.FACTION_PLAYER, &"energy")
	var initial_material: int = game_state.get_faction_resource(GameState.FACTION_PLAYER, &"material")

	# Initially can buy extractor (tier 1, no parent)
	if not _check(game_state.can_purchase_upgrade(player_homeworld, &"extractor", upgrade_catalog), "should be able to buy extractor initially"):
		return false

	# Cannot buy refinery without extractor
	if not _check(not game_state.can_purchase_upgrade(player_homeworld, &"refinery", upgrade_catalog), "should not buy refinery without extractor"):
		return false

	# Buy extractor
	if not _check(game_state.purchase_upgrade(player_homeworld, &"extractor", upgrade_catalog), "purchase extractor should succeed"):
		return false

	# Now can buy refinery or trade_post
	if not _check(game_state.can_purchase_upgrade(player_homeworld, &"refinery", upgrade_catalog), "should be able to buy refinery after extractor"):
		return false
	if not _check(game_state.can_purchase_upgrade(player_homeworld, &"trade_post", upgrade_catalog), "should be able to buy trade_post after extractor"):
		return false

	# Buy refinery
	if not _check(game_state.purchase_upgrade(player_homeworld, &"refinery", upgrade_catalog), "purchase refinery should succeed"):
		return false

	# After buying refinery, cannot buy trade_post (exclusive)
	if not _check(not game_state.can_purchase_upgrade(player_homeworld, &"trade_post", upgrade_catalog), "should not buy trade_post after refinery (exclusive)"):
		return false

	# Verify resource deduction
	# Extractor costs 15 energy, refinery costs 25 material
	if not _check(game_state.get_faction_resource(GameState.FACTION_PLAYER, &"energy") == initial_energy - 15, "extractor should cost 15 energy"):
		return false
	if not _check(game_state.get_faction_resource(GameState.FACTION_PLAYER, &"material") == initial_material - 25, "refinery should cost 25 material"):
		return false

	# Verify upgrades recorded
	var hw_upgrades: Array[StringName] = game_state.get_planet_upgrades(player_homeworld)
	if not _check(hw_upgrades.size() == 2 and hw_upgrades.has(&"extractor") and hw_upgrades.has(&"refinery"), "upgrades should be recorded on planet"):
		return false

	# Test trait effects on resource generation
	# Extractor gives +50% production_boost, refinery gives +100% but -2 energy maintenance.
	game_state.call("deal_resources", planet_catalog, preload("res://resources/config/resource_pool_default.tres"), world_config.layout_seed)
	var energy_before_generation: int = game_state.get_faction_resource(GameState.FACTION_PLAYER, &"energy")
	var generated_resource: StringName = game_state.resource_of(player_homeworld)
	var generated: int = game_state.generate_resources_for_planet(player_homeworld, upgrade_catalog)
	# Base 1 * (1 + 0.5 + 1.0) = 2.5 -> 2; the generated resource may itself be energy.
	if not _check(generated >= 2, "resource generation with traits should apply production boost"):
		return false

	# Verify maintenance cost was deducted without assuming the homeworld's dealt resource.
	var energy_after_gen: int = game_state.get_faction_resource(GameState.FACTION_PLAYER, &"energy")
	var expected_energy_after_generation: int = energy_before_generation - 2
	if generated_resource == &"energy":
		expected_energy_after_generation += generated
	if not _check(energy_after_gen == expected_energy_after_generation, "maintenance cost should be deducted during generation"):
		return false

	# Test defense traits on arrival resolution
	var defense_grid := upgrade_catalog.resolve(&"defense_grid")
	if not _check(defense_grid != null and defense_grid.trait_definition != null and defense_grid.trait_definition.defense_rating == 5, "defense_grid should have defense_rating 5"):
		return false
	var armor_lab_upg := upgrade_catalog.resolve(&"armor_lab")
	if not _check(armor_lab_upg != null and armor_lab_upg.trait_definition != null and armor_lab_upg.trait_definition.defense_rating == 6, "armor_lab should have defense_rating 6"):
		return false

	# Test mission type constants
	if not _check(GameState.MISSION_MILITARY == &"military" and GameState.MISSION_CARGO == &"cargo" and GameState.MISSION_COLONY == &"colony", "mission type constants defined"):
		return false

	# Faction indicators must be visually distinct per faction.
	var faction_transformer_config: TransformerConfig = preload("res://resources/config/transformer_default.tres")
	if not _check(faction_transformer_config.faction_player_tint != faction_transformer_config.faction_cpu_tint and faction_transformer_config.faction_player_tint != faction_transformer_config.faction_neutral_tint and faction_transformer_config.faction_cpu_tint != faction_transformer_config.faction_neutral_tint, "faction indicator colors are not distinguishable"):
		return false

	# Test transformer tint modes
	if not _check(extractor.transformer_tint_mode == &"resource", "extractor should use resource tint"):
		return false
	if not _check(refinery.transformer_tint_mode == &"resource", "refinery should use resource tint"):
		return false
	if not _check(trade_post.transformer_tint_mode == &"faction", "trade_post should use faction tint"):
		return false
	if not _check(defense_grid.transformer_tint_mode == &"faction", "defense_grid should use faction tint"):
		return false
	if not _check(tech_center.transformer_tint_mode == &"faction", "tech_center should use faction tint"):
		return false
	if not _check(orbital_station.transformer_tint_mode == &"faction", "orbital_station should use faction tint"):
		return false

	# Test visual assets exist for upgrades
	for up in upgrade_catalog.upgrades:
		if up != null and up.visual_asset == null:
			_check(false, "upgrade %s missing visual_asset" % up.id)
			return false

	# --- MISSION SEMANTICS ---
	var mission_source: Planet = null
	var mission_cpu: Planet = null
	var mission_neutral: Planet = null
	for planet_child in field.get_children():
		if planet_child is Planet:
			match (planet_child as Planet).planet_id:
				&"ocean":
					mission_source = planet_child as Planet
				&"paper":
					mission_cpu = planet_child as Planet
				&"toxic":
					mission_neutral = planet_child as Planet
	if not _check(mission_source != null and mission_cpu != null and mission_neutral != null, "mission test planets missing"):
		return false

	# Colony settles a neutral planet peacefully
	game_state.set_faction(mission_neutral.planet_id, GameState.FACTION_NEUTRAL)
	mission_neutral.unregister_workers(mission_neutral.worker_count)
	var colony_result: StringName = mission_neutral.resolve_mission(GameState.FACTION_PLAYER, 2, GameState.MISSION_COLONY)
	if not _check(colony_result == Planet.ARRIVAL_SETTLED and mission_neutral.get_faction() == GameState.FACTION_PLAYER and mission_neutral.worker_count == 2, "colony mission did not settle a neutral planet"):
		return false

	# Colony on an already owned planet is rejected
	var colony_owned_result: StringName = mission_neutral.resolve_mission(GameState.FACTION_CPU, 1, GameState.MISSION_COLONY)
	if not _check(colony_owned_result == Planet.ARRIVAL_REJECTED and mission_neutral.get_faction() == GameState.FACTION_PLAYER, "colony mission must be rejected on an owned planet"):
		return false

	# Cargo reinforces an own planet (resource transfer)
	game_state.set_faction(mission_source.planet_id, GameState.FACTION_PLAYER)
	var cargo_before: int = mission_source.worker_count
	var cargo_result: StringName = mission_source.resolve_mission(GameState.FACTION_PLAYER, 3, GameState.MISSION_CARGO)
	if not _check(cargo_result == Planet.ARRIVAL_FRIENDLY and mission_source.worker_count == cargo_before + 3, "cargo mission did not reinforce an own planet"):
		return false

	# Cargo against an enemy planet is rejected
	var cargo_enemy_result: StringName = mission_cpu.resolve_mission(GameState.FACTION_PLAYER, 3, GameState.MISSION_CARGO)
	if not _check(cargo_enemy_result == Planet.ARRIVAL_REJECTED and mission_cpu.get_faction() == GameState.FACTION_CPU, "cargo mission must be rejected against an enemy planet"):
		return false

	# Military missions keep attack semantics via resolve_arrival
	var military_result: StringName = mission_neutral.resolve_mission(GameState.FACTION_CPU, 4, GameState.MISSION_MILITARY)
	if not _check(military_result == Planet.ARRIVAL_CAPTURED and mission_neutral.get_faction() == GameState.FACTION_CPU, "military mission should capture an undefended planet"):
		return false

	# --- CPU DISPATCH ---
	var cpu_homeworld: Planet = _find_planet_by_id(field, game_state.homeworld_for(GameState.FACTION_CPU))
	if not _check(cpu_homeworld != null, "CPU homeworld for dispatch test is missing"):
		return false
	var cpu_ai: Node = field.get_node_or_null("CpuDispatchAI")
	var cpu_dispatch_config: CpuDispatchConfig = cpu_ai.get("dispatch_config") as CpuDispatchConfig
	var cpu_workers_before: int = cpu_homeworld.worker_count
	if cpu_workers_before < cpu_dispatch_config.minimum_source_workers:
		cpu_homeworld.register_workers(cpu_dispatch_config.minimum_source_workers - cpu_workers_before)
	cpu_workers_before = cpu_homeworld.worker_count
	var manager_children_before_cpu: int = manager.get_child_count()
	var cpu_dispatched: bool = cpu_ai.call("dispatch_once", true)
	if not _check(cpu_dispatched and manager.get_child_count() > manager_children_before_cpu, "CPU dispatch AI did not launch a mission"):
		return false
	var cpu_cluster: WorkerCluster = null
	for manager_child in manager.get_children():
		if manager_child is WorkerCluster:
			cpu_cluster = manager_child as WorkerCluster
			break
	if not _check(cpu_cluster != null and cpu_cluster.source_faction == GameState.FACTION_CPU and cpu_cluster.mission_type == GameState.MISSION_COLONY, "CPU dispatch AI did not choose a colony mission"):
		return false
	for manager_child in manager.get_children():
		if manager_child is WorkerCluster:
			(manager_child as WorkerCluster).queue_free()
	await process_frame
	if cpu_homeworld.worker_count < cpu_workers_before:
		cpu_homeworld.register_workers(cpu_workers_before - cpu_homeworld.worker_count)
	if not _check(cpu_homeworld.worker_count == cpu_workers_before, "CPU dispatch test did not restore source workers"):
		return false

	# --- WORKER COSTS ---
	var shipyard_upgrade: PlanetUpgradeDefinition = upgrade_catalog.resolve(&"shipyard")
	if not _check(shipyard_upgrade != null and shipyard_upgrade.cost_workers == 2, "shipyard should cost 2 workers"):
		return false
	if not _check(not game_state.can_purchase_upgrade(player_homeworld, &"shipyard", upgrade_catalog, 1), "shipyard must not be buyable with only 1 worker"):
		return false
	if not _check(game_state.can_purchase_upgrade(player_homeworld, &"shipyard", upgrade_catalog, 2), "shipyard must be buyable with 2 workers"):
		return false

	# Test source traits flowing into visible dispatch tiers
	var upgrade_planet: Planet = null
	for planet_child in field.get_children():
		if planet_child is Planet and (planet_child as Planet).planet_id == player_homeworld:
			upgrade_planet = planet_child as Planet
			break
	if not _check(upgrade_planet != null and upgrade_planet.get_cluster_tier_bonus() == 0, "planet cluster tier bonus should start at zero"):
		return false
	game_state.add_faction_resource(GameState.FACTION_PLAYER, &"biomass", 100)
	game_state.add_faction_resource(GameState.FACTION_PLAYER, &"material", 100)
	if not _check(game_state.purchase_upgrade(player_homeworld, &"shipyard", upgrade_catalog), "shipyard purchase for tier bonus test should succeed"):
		return false
	if not _check(game_state.purchase_upgrade(player_homeworld, &"war_shipyard", upgrade_catalog), "war_shipyard purchase for tier bonus test should succeed"):
		return false
	var source_tier_bonus: int = upgrade_planet.get_cluster_tier_bonus()
	if not _check(source_tier_bonus == 1, "war_shipyard bonus did not reach the source planet"):
		return false
	if not _check(_Dispatch.cluster_tier(5, transit_config, source_tier_bonus) == &"l", "source tier bonus did not reach visible dispatch tier"):
		return false
	var bonus_route: Array[Vector2] = [upgrade_planet.global_position, mission_cpu.global_position]
	manager.call("_dispatch_clusters", upgrade_planet, mission_cpu, 1, bonus_route, GameState.MISSION_MILITARY)
	var bonus_cluster: WorkerCluster = null
	for manager_child in manager.get_children():
		if manager_child is WorkerCluster:
			bonus_cluster = manager_child as WorkerCluster
			break
	if not _check(bonus_cluster != null and bonus_cluster.cluster_tier_bonus == source_tier_bonus, "worker manager did not pass the source tier bonus"):
		return false
	var bonus_sprite: Sprite2D = bonus_cluster.get_node_or_null("Sprite2D") as Sprite2D
	var expected_bonus_tier: ClusterTierDefinition = _Dispatch.cluster_definition(1, transit_config, source_tier_bonus)
	if not _check(bonus_sprite != null and expected_bonus_tier != null and bonus_sprite.texture == expected_bonus_tier.texture, "worker cluster did not render the bonus tier"):
		return false
	bonus_cluster.queue_free()
	await process_frame

	# --- RESOURCE BASE FROM SIZE PROFILE ---
	var profile_base: int = 1
	if mission_source != null and mission_source.planet_id == player_homeworld:
		profile_base = mission_source.get_size_profile().resource_base
	else:
		for planet_child in field.get_children():
			if planet_child is Planet and (planet_child as Planet).planet_id == player_homeworld:
				profile_base = (planet_child as Planet).get_size_profile().resource_base
				break
	if not _check(profile_base >= 1, "player homeworld size profile resource_base is invalid"):
		return false
	var base_generated: int = game_state.generate_resources_for_planet(player_homeworld, upgrade_catalog, profile_base)
	if not _check(base_generated >= profile_base, "resource generation should honor the size profile resource_base (base %d, got %d)" % [profile_base, base_generated]):
		return false

	# Resetting GameState must also remove visual upgrade structures from existing planets.
	var reset_visual_planet: Planet = null
	for planet_child in field.get_children():
		if planet_child is Planet and (planet_child as Planet).planet_id == player_homeworld:
			reset_visual_planet = planet_child as Planet
			break
	if not _check(reset_visual_planet != null, "planet for upgrade structure reset test is missing"):
		return false
	var reset_details: PlanetDetails = reset_visual_planet.get_node_or_null("PlanetDetails") as PlanetDetails
	if not _check(reset_details != null and reset_details.get_node_or_null("UpgradeStructure_extractor") != null, "upgrade structure was not created before reset"):
		return false
	game_state.reset_from_catalog(planet_catalog)
	if not _check(reset_details.get_node_or_null("UpgradeStructure_extractor") == null, "GameState reset left a stale upgrade structure"):
		return false
	if not _check(game_state.purchase_upgrade(player_homeworld, &"extractor", upgrade_catalog), "upgrade could not be repurchased after reset"):
		return false
	if not _check(reset_details.get_node_or_null("UpgradeStructure_extractor") != null, "upgrade structure was not recreated in the same frame"):
		return false
	return true

func _constraint_scout_and_discovery() -> bool:
	var field: Node = _field
	var network: Node = _network
	var game_state: Node = _game_state
	var upgrade_catalog: PlanetUpgradeCatalog = _upgrade_catalog
	var ship_manager: ShipManager = field.get_node_or_null("ShipManager") as ShipManager
	if not _check(ship_manager != null, "ShipManager runtime module is missing"):
		return false
	var tech_catalog: TechnologyCatalog = ship_manager.get_technology_catalog()
	var ship_config: ShipConfig = ship_manager.get_ship_config()
	if not _check(tech_catalog != null and tech_catalog.validate().is_empty(), "technology catalog validation failed"):
		return false
	if not _check(ship_config != null and ship_config.validate().is_empty(), "ship config validation failed"):
		return false
	if not _check(tech_catalog.for_category(TechnologyDefinition.CATEGORY_SHIPS).size() >= 2 and not tech_catalog.for_category(TechnologyDefinition.CATEGORY_MECH).is_empty() and tech_catalog.for_category(TechnologyDefinition.CATEGORY_PLANET).size() >= 2, "technology catalog is missing a ships, mech, or planet branch"):
		return false

	# Discovery state: a faction starts knowing only its own planets.
	var player_known_before: Array[StringName] = game_state.known_planets_of(GameState.FACTION_PLAYER)
	if not _check(player_known_before.size() == 1 and player_known_before.has(game_state.homeworld_for(GameState.FACTION_PLAYER)), "player should initially know only their own planet"):
		return false

	# Technology research is gated by prerequisites and spends resources.
	if not _check(not game_state.has_technology(GameState.FACTION_PLAYER, &"scout_hull"), "scout_hull should not be researched initially"):
		return false
	if not _check(not game_state.can_research_technology(GameState.FACTION_PLAYER, &"scanner_drone", tech_catalog), "scanner_drone should require scout_hull first"):
		return false
	game_state.add_faction_resource(GameState.FACTION_PLAYER, &"material", 100)
	game_state.add_faction_resource(GameState.FACTION_PLAYER, &"energy", 100)
	if not _check(game_state.can_research_technology(GameState.FACTION_PLAYER, &"scout_hull", tech_catalog), "scout_hull should be researchable"):
		return false
	if not _check(game_state.research_technology(GameState.FACTION_PLAYER, &"scout_hull", tech_catalog), "scout_hull research should succeed"):
		return false
	if not _check(not game_state.can_research_technology(GameState.FACTION_PLAYER, &"scout_hull", tech_catalog), "scout_hull should not be researchable twice"):
		return false
	if not _check(game_state.research_technology(GameState.FACTION_PLAYER, &"scanner_drone", tech_catalog), "scanner_drone research should succeed after scout_hull"):
		return false
	if not _check(game_state.has_technology(GameState.FACTION_PLAYER, &"scout_hull") and game_state.has_technology(GameState.FACTION_PLAYER, &"scanner_drone"), "researched technologies were not recorded"):
		return false
	for technology in tech_catalog.resolve_all():
		if not _check(technology.visual_asset != null and not technology.mechanic_description.is_empty() and not String(technology.effect_id).is_empty(), "technology %s is missing a visible or mechanical effect" % technology.id):
			return false

	# Planet technologies are per-known-own-planet and have real production effects.
	var player_homeworld: StringName = game_state.homeworld_for(GameState.FACTION_PLAYER)
	var source: Planet = _find_planet_by_id(field, player_homeworld)
	if not _check(source != null, "player homeworld planet for technology test is missing"):
		return false
	if not _check(not game_state.can_research_planet_technology(GameState.FACTION_PLAYER, source.planet_id, &"planetary_extraction", tech_catalog), "planetary extraction should require planetary survey"):
		return false
	game_state.add_faction_resource(GameState.FACTION_PLAYER, &"rare", 100)
	game_state.add_faction_resource(GameState.FACTION_PLAYER, &"material", 100)
	if not _check(game_state.research_planet_technology(GameState.FACTION_PLAYER, source.planet_id, &"planetary_survey", tech_catalog), "planetary survey research should succeed for the own homeworld"):
		return false
	if not _check(game_state.has_planet_technology(source.planet_id, &"planetary_survey"), "planetary survey was not stored on the target planet"):
		return false
	if not _check(game_state.can_research_planet_technology(GameState.FACTION_PLAYER, source.planet_id, &"planetary_extraction", tech_catalog), "planetary extraction should unlock after survey"):
		return false

	# Scout build gate: shipyard + researched hull/scanner + build cost.
	if not _check(source != null, "player homeworld planet for scout test is missing"):
		return false
	if not _check(not ship_manager.can_build_scout(source), "scout build should be blocked without a shipyard"):
		return false
	game_state.add_faction_resource(GameState.FACTION_PLAYER, &"biomass", 100)
	if not _check(game_state.purchase_upgrade(player_homeworld, &"shipyard", upgrade_catalog), "shipyard purchase for scout test should succeed"):
		return false
	if not _check(ship_manager.can_build_scout(source), "scout build should succeed with shipyard + researched techs"):
		return false

	# Build a scout toward an unknown planet and verify arrival discovers it.
	var destination: Planet = _find_planet_by_id(field, &"toxic")
	if destination == null or game_state.is_known(destination.planet_id, GameState.FACTION_PLAYER):
		destination = null
		for child in field.get_children():
			if child is Planet and not game_state.is_known((child as Planet).planet_id, GameState.FACTION_PLAYER):
				destination = child as Planet
				break
	if not _check(destination != null and not game_state.is_known(destination.planet_id, GameState.FACTION_PLAYER), "no unknown planet available for scout discovery"):
		return false
	if not _check(not game_state.can_research_planet_technology(GameState.FACTION_PLAYER, destination.planet_id, &"planetary_survey", tech_catalog), "unknown planets must not accept planet research"):
		return false
	var scout: ScoutShip = ship_manager.build_scout(source, destination)
	if not _check(scout != null and ship_manager.scout_count() == 1, "scout build did not launch a scout"):
		return false
	var scout_hull: Sprite2D = scout.get_node_or_null("Hull") as Sprite2D
	var scout_scanner: Sprite2D = scout.get_node_or_null("Scanner") as Sprite2D
	if not _check(scout_hull != null and scout_hull.texture != null and scout_scanner != null and scout_scanner.texture != null, "scout hull or scanner drone visual is missing"):
		return false
	if not _check(not game_state.is_known(destination.planet_id, GameState.FACTION_PLAYER), "destination should still be unknown before arrival"):
		return false
	scout.call("_arrive")
	await process_frame
	if not _check(game_state.is_known(destination.planet_id, GameState.FACTION_PLAYER), "scout arrival did not discover the destination planet"):
		return false
	if not _check(game_state.known_planets_of(GameState.FACTION_PLAYER).has(destination.planet_id), "discovered planet is missing from the known list"):
		return false
	if not _check(ship_manager.scout_count() == 0, "scout was not freed after arrival"):
		return false
	if not _check(not game_state.discover_planet(GameState.FACTION_PLAYER, destination.planet_id), "discovering an already-known planet should be a no-op"):
		return false
	if not _check(ship_manager.build_scout(source, destination) == null, "scout build should reject an already-known destination"):
		return false

	# The technology menu must be reachable from the network host and render the planet branch.
	var technology_menu: TechnologyMenu = network.get_technology_menu()
	if not _check(technology_menu != null, "technology menu was not created by the network"):
		return false
	technology_menu.set("_category", TechnologyDefinition.CATEGORY_PLANET)
	technology_menu.call("_refresh")
	await process_frame
	var technology_list: VBoxContainer = technology_menu.get_node_or_null("TechTabUI/TechPanel/TechMargin/TechVBox/TechScroll/TechList") as VBoxContainer
	if not _check(technology_list != null and technology_list.get_child_count() >= 3, "planet technology tab did not render known-planet technology cards"):
		return false
	var rendered_technology_cards: int = 0
	for list_child in technology_list.get_children():
		if list_child is PanelContainer:
			rendered_technology_cards += 1
			var card_content: HBoxContainer = list_child.get_child(0) as HBoxContainer
			var icon: TextureRect = card_content.get_child(0) as TextureRect if card_content != null and card_content.get_child_count() > 0 else null
			if not _check(icon != null and icon.texture != null, "technology card is missing its visual asset"):
				return false
	if not _check(rendered_technology_cards >= 2, "known-planet technology cards have no visual entries"):
		return false
	return true

func _constraint_event_log() -> bool:
	var network: Node = _network
	var event_log: Node = get_root().get_node_or_null("EventLog")
	if not _check(event_log != null, "EventLog autoload is missing"):
		return false
	if not _check(event_log.has_signal("message_pushed"), "EventLog must expose a typed message_pushed signal"):
		return false
	if not _check(network.get_message_feed() != null, "message feed was not created by the network"):
		return false
	var before: int = event_log.get_entries().size()
	event_log.push(&"test", "Testnachricht")
	if not _check(event_log.get_entries().size() == before + 1, "EventLog.push did not record an entry"):
		return false
	var pushed_entry: Dictionary = event_log.get_entries().back()
	if not _check(bool(pushed_entry.get("visible", false)), "EventLog.push entry is not marked for the message feed"):
		return false
	event_log.log_silent(&"economy", "Stille Ressourcenmeldung")
	if not _check(event_log.get_entries().size() == before + 2, "EventLog.log did not record an entry"):
		return false
	var silent_entry: Dictionary = event_log.get_entries().back()
	if not _check(not bool(silent_entry.get("visible", true)), "silent EventLog entry should not create a toast"):
		return false
	var feed: MessageFeed = network.get_message_feed()
	var toast_list: VBoxContainer = feed.get_node_or_null("FeedRoot/ToastList") as VBoxContainer
	var theme_config: UIThemeConfig = network.get("ui_theme_config") as UIThemeConfig
	if not _check(toast_list != null and theme_config != null, "message feed toast list or theme config is missing"):
		return false
	for index in range(theme_config.message_max_visible_toasts + 2):
		event_log.push(&"test", "Toast %d" % index)
	if not _check(toast_list.get_child_count() <= theme_config.message_max_visible_toasts, "message feed exceeded its configured toast limit"):
		return false
	if not _check(event_log.export_to_player_log("user://preflight_player.log"), "EventLog export_to_player_log failed"):
		return false
	var file := FileAccess.open("user://preflight_player.log", FileAccess.READ)
	if not _check(file != null, "player.log export file is missing"):
		return false
	var content := file.get_as_text()
	file.close()
	if not _check(content.contains("Testnachricht") and content.contains("Stille Ressourcenmeldung"), "player.log export is missing recorded entries"):
		return false
	return true

func _run_layout_scale_case(source_field: Node, base_catalog: PlanetCatalog, design_size: Vector2, planet_count: int, columns: int, seed: int) -> bool:
	var scene: PackedScene = preload("res://scenes/objects/planets/planet_field.tscn")
	var custom_field: Node = scene.instantiate()
	var custom_config: WorldConfig = (source_field.get("world_config") as WorldConfig).duplicate(true) as WorldConfig
	custom_config.design_size = design_size
	custom_config.columns = columns
	custom_config.layout_seed = seed
	custom_config.extra_large_count = mini(custom_config.extra_large_count, planet_count)
	custom_config.large_count = mini(custom_config.large_count, maxi(0, planet_count - custom_config.extra_large_count))
	custom_field.set("world_config", custom_config)
	custom_field.set("planet_catalog", _catalog_for_count(base_catalog, planet_count))
	custom_field.set("position", Vector2(37.0, -29.0))
	custom_field.set("size_profiles", source_field.get("size_profiles"))
	root.add_child(custom_field)
	await process_frame
	await process_frame

	var planets: Array[Planet] = []
	var slots: Dictionary = {}
	for child in custom_field.get_children():
		if child is Planet:
			planets.append(child)
			var slot: int = int(child.get_meta("layout_slot", -1))
			if slot < 0 or slot >= planet_count or slots.has(slot):
				custom_field.queue_free()
				await process_frame
				return false
			slots[slot] = true
			if child.position.x < custom_config.padding or child.position.x > design_size.x - custom_config.padding:
				custom_field.queue_free()
				await process_frame
				return false
			if child.position.y < custom_config.padding or child.position.y > design_size.y - custom_config.padding:
				custom_field.queue_free()
				await process_frame
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
	await process_frame
	return passed

func _run_scenario_case(scene: PackedScene, catalog: ScenarioCatalog, scenario_id: StringName) -> bool:
	var scenario_background: Node = scene.instantiate()
	scenario_background.set("scenario_catalog", catalog)
	scenario_background.set("active_scenario_id", scenario_id)
	root.add_child(scenario_background)
	await process_frame
	await process_frame

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
	var passed: bool = active_scenario != null and active_scenario.id == scenario_id and active_scenario.route_mode == ScenarioDefinition.ROUTE_MODE_NEIGHBORS_ONLY and not active_scenario.randomize_layout_seed and map != null and scenario_world != null and scenario_world.design_size.distance_to(Vector2(1920.0, 1080.0)) <= 0.01 and scenario_world.route_mode == active_scenario.route_mode and scenario_world.route_mode == WorldConfig.ROUTE_MODE_NEIGHBORS_ONLY and field.get("planet_catalog") == map.planet_catalog and scenario_navigation.get("navigation_config") == map.navigation_config and scenario_waypoint_catalog != null and scenario_waypoint_catalog.definitions.size() >= 2 and scenario_waypoint_catalog != (preload("res://resources/config/navigation_default.tres") as NavigationConfig).waypoint_catalog and wide_waypoint_cadence_valid and planets.size() == map.planet_catalog.planets.size() and route_count == neighbor_count and fixed_seed_applied
	scenario_background.queue_free()
	await process_frame
	return passed

func _catalog_for_count(base_catalog: PlanetCatalog, planet_count: int) -> PlanetCatalog:
	var catalog := PlanetCatalog.new()
	var definitions: Array[PlanetDefinition] = []
	for index in planet_count:
		var source: PlanetDefinition = base_catalog.planets[index % base_catalog.planets.size()]
		var definition: PlanetDefinition = source.duplicate(true) as PlanetDefinition
		if index >= base_catalog.planets.size():
			definition.planet_id = StringName("%s_%d" % [definition.planet_id, index])
			definition.display_name = "%s %d" % [definition.display_name, index]
		definitions.append(definition)
	catalog.planets = definitions
	return catalog

func _capture_spawn(planet: Node2D, amount: int) -> void:
	if planet == _observed_planet:
		_observed_state = int(planet.worker_state)
		_observed_amount = amount

func _capture_faction_changed(planet_id: StringName, old_faction: StringName, new_faction: StringName) -> void:
	_observed_faction_planet = planet_id
	_observed_old_faction = old_faction
	_observed_new_faction = new_faction

func _planet_positions(field: Node) -> Dictionary:
	var positions: Dictionary = {}
	for child in field.get_children():
		if child is Planet:
			positions[child] = (child as Planet).position
	return positions

func _offsets_match_shape(actual: Array[Vector2], expected: Array[Vector2], tolerance: float) -> bool:
	if actual.size() != expected.size() or actual.is_empty():
		return false
	var actual_center := Vector2.ZERO
	var expected_center := Vector2.ZERO
	for offset in actual:
		actual_center += offset
	for offset in expected:
		expected_center += offset
	actual_center /= float(actual.size())
	expected_center /= float(expected.size())
	for index in actual.size():
		if (actual[index] - actual_center).distance_to(expected[index] - expected_center) > tolerance:
			return false
	return true

func _offsets_have_safe_spacing(offsets: Array[Vector2], minimum: float) -> bool:
	for first_index in offsets.size():
		for second_index in range(first_index + 1, offsets.size()):
			if offsets[first_index].distance_to(offsets[second_index]) < minimum:
				return false
	return true

func _find_planet_with_size(field: Node, size_class: StringName) -> Node:
	for child in field.get_children():
		if child.get("layout_size") != null and StringName(child.get("layout_size")) == size_class:
			return child
	return null

func _count_planets_with_size(field: Node, size_class: StringName) -> int:
	var count := 0
	for child in field.get_children():
		if child.get("layout_size") != null and StringName(child.get("layout_size")) == size_class:
			count += 1
	return count

func _find_planet_by_id(field: Node, planet_id: StringName) -> Planet:
	for child in field.get_children():
		if child is Planet and (child as Planet).planet_id == planet_id:
			return child as Planet
	return null

func _find_timer(planet: Node) -> Timer:
	for child in planet.get_children():
		if child is Timer:
			return child
	return null

func _path_distance(path: Array[Vector2]) -> float:
	return PathUtils.distance(path)

func _path_contains_planet(path: Array[Vector2], field: Node, source: Planet, destination: Node2D) -> bool:
	for point_index in range(1, path.size() - 1):
		for child in field.get_children():
			if child is Planet and child != source and child != destination and (child as Planet).global_position.distance_to(path[point_index]) <= 0.05:
				return true
	return false

func _flight_seconds(text: String) -> float:
	return float(text.trim_prefix("Flugzeit: ").trim_suffix(" s"))

func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("FAIL: " + message)
	quit(1)
	return false
