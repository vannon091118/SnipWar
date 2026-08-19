extends SceneTree

const _FlightTime := preload("res://scripts/flight_time.gd")
const _Dispatch := preload("res://scripts/dispatch.gd")

var _observed_planet: Node2D
var _observed_state := -1
var _observed_amount := -1

func _init() -> void:
	if not _check(is_equal_approx(_FlightTime.seconds_for(100.0, 1), 8.0), "flight time baseline is wrong"):
		return
	if not _check(is_equal_approx(_FlightTime.seconds_for(100.0, 2), 8.4), "flight time unit load is wrong"):
		return
	if not _check(is_equal_approx(_FlightTime.seconds_for(200.0, 5), 17.6), "flight time medium load is wrong"):
		return
	if not _check(_FlightTime.seconds_for(100.0, 6) > _FlightTime.seconds_for(100.0, 5), "flight time unit scaling is wrong"):
		return
	if not _check(_Dispatch.cluster_groups(1) == [1] and _Dispatch.cluster_groups(4) == [1, 1, 1, 1] and _Dispatch.cluster_groups(5) == [5] and _Dispatch.cluster_groups(7) == [5, 1, 1] and _Dispatch.cluster_groups(100) == [100], "cluster packing thresholds are wrong"):
		return
	if not _check(_Dispatch.cluster_tier(4) == &"k" and _Dispatch.cluster_tier(5) == &"m" and _Dispatch.cluster_tier(99) == &"m" and _Dispatch.cluster_tier(100) == &"l", "cluster tier boundaries are wrong"):
		return
	if not _check(_Dispatch.amount_range(3) == Vector2i(1, 3), "dispatch range for three units is wrong"):
		return
	if not _check(_Dispatch.amount_range(1) == Vector2i(1, 1), "dispatch range for one unit is wrong"):
		return
	if not _check(_Dispatch.amount_range(0) == Vector2i.ZERO, "dispatch range for empty planet is wrong"):
		return
	if not _check(_Dispatch.amount_range(-1) == Vector2i.ZERO, "dispatch range for negative count is wrong"):
		return
	if not _check(_Dispatch.launch_amount(3, 2) == 2, "launch amount should match request"):
		return
	if not _check(_Dispatch.launch_amount(2, 5) == 2, "launch amount should clamp to available"):
		return
	if not _check(_Dispatch.launch_amount(0, 3) == 0, "launch amount from empty planet should be zero"):
		return
	if not _check(_Dispatch.launch_amount(3, 0) == 0, "launch amount with zero requested should be zero"):
		return

	var scene: PackedScene = preload("res://scenes/backgrounds/starfield_background.tscn")
	var background: Node = scene.instantiate()
	root.add_child(background)
	await process_frame
	await process_frame

	var field: Node = background.get_node("PlanetField")
	var planet_field_node: Node2D = field as Node2D
	var meteor_field_node: Node2D = background.get_node("MeteorField") as Node2D
	if not _check(planet_field_node.position.distance_to(Vector2.ZERO) <= 0.01, "PlanetField has an unexpected scene offset"):
		return
	if not _check(meteor_field_node.position.distance_to(Vector2.ZERO) <= 0.01, "MeteorField has an unexpected scene offset"):
		return
	var world_config: WorldConfig = field.get("world_config") as WorldConfig
	if not _check(world_config != null, "world config is missing"):
		return
	var viewport_size: Vector2 = get_root().get_viewport().get_visible_rect().size
	if not _check(viewport_size.distance_to(world_config.design_size) <= 0.01, "world design size differs from the Godot viewport"):
		return
	var scenario_catalog: ScenarioCatalog = background.get("scenario_catalog") as ScenarioCatalog
	if not _check(scenario_catalog != null and scenario_catalog.validate().is_empty(), "scenario catalog validation failed"):
		return
	var active_scenario: ScenarioDefinition = background.get("active_scenario") as ScenarioDefinition
	if not _check(active_scenario != null and active_scenario.id == &"default", "default scenario was not selected"):
		return
	if not _check(active_scenario.route_mode == ScenarioDefinition.ROUTE_MODE_ALL_PLANETS and active_scenario.route_mode == world_config.route_mode, "default scenario route rule was not applied"):
		return
	if not _check(active_scenario.map_definition != null and active_scenario.map_definition.world_config == world_config, "active scenario map was not applied"):
		return
	var background_config: BackgroundConfig = background.get("background_config") as BackgroundConfig
	if not _check(background_config != null and background_config.validate().is_empty(), "background config validation failed"):
		return
	var background_render_stats: Dictionary = background.call("get_render_batch_stats")
	var background_batch_count: int = int(background_render_stats.get("batch_count", 0))
	var background_batched_elements: int = int(background_render_stats.get("batched_elements", 0))
	var background_source_elements: int = int(background_render_stats.get("source_elements", 0))
	var background_draw_calls: int = int(background_render_stats.get("estimated_draw_calls", 0))
	if not _check(background_batch_count >= 2 and background_batch_count <= 3, "background render batches are missing"):
		return
	if not _check(background_batched_elements == background_config.star_count + background_config.dust_count, "background batched element count is wrong"):
		return
	if not _check(background_source_elements > background_draw_calls * 4 and background_draw_calls <= 24, "background draw-call budget is not compressed"):
		return
	var meteor_config: MeteorConfig = background.get_node("MeteorField").get("meteor_config") as MeteorConfig
	if not _check(meteor_config != null and meteor_config.validate().is_empty(), "meteor config validation failed"):
		return
	var planet_catalog: PlanetCatalog = field.get("planet_catalog") as PlanetCatalog
	if not _check(planet_catalog != null, "planet catalog is missing"):
		return
	var catalog_errors := planet_catalog.validate()
	if not _check(catalog_errors.is_empty(), "planet catalog validation failed"):
		return
	var positions_before: Dictionary = _planet_positions(field)
	if not _check(positions_before.size() == planet_catalog.planets.size(), "generated planets do not match the catalog"):
		return
	for planet_node in field.get_children():
		if planet_node is Planet:
			var global_planet_position: Vector2 = (planet_node as Planet).global_position
			if not _check(global_planet_position.x >= -0.01 and global_planet_position.x <= world_config.design_size.x + 0.01 and global_planet_position.y >= -0.01 and global_planet_position.y <= world_config.design_size.y + 0.01, "planet global position is outside world bounds"):
				return
	var world_errors := world_config.validate_for_planet_count(positions_before.size())
	if not _check(world_errors.is_empty(), "world config validation failed"):
		return
	var configured_profiles: Array[PlanetSizeProfile] = []
	for profile_value in field.get("size_profiles"):
		var profile: PlanetSizeProfile = profile_value as PlanetSizeProfile
		if profile != null:
			configured_profiles.append(profile)
	var profile_errors := world_config.validate_profiles(configured_profiles)
	if not _check(profile_errors.is_empty(), "planet size profile validation failed"):
		return

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
		return
	field.call("set_layout_seed", original_seed)
	await process_frame
	await process_frame

	var network: Node = field.get_node("PlanetNetwork")
	var navigation: NavigationField = field.get_node("NavigationField") as NavigationField
	var ui: PlanetNetworkUI = network.get_ui()
	var manager: Node = field.get_node("WorkerManager")
	if not _check(navigation != null, "navigation field is missing"):
		return
	var navigation_config: NavigationConfig = navigation.get("navigation_config") as NavigationConfig
	if not _check(navigation_config != null and navigation_config.validate().is_empty(), "navigation config validation failed"):
		return
	if not _check(navigation_config.waypoint_catalog != null and navigation_config.waypoint_catalog.definitions.size() >= 2, "navigation waypoint catalog is missing styles"):
		return
	var first_waypoint_definition: NavigationWaypointDefinition = navigation_config.waypoint_for_edge(0)
	var second_waypoint_definition: NavigationWaypointDefinition = navigation_config.waypoint_for_edge(1)
	if not _check(first_waypoint_definition != null and second_waypoint_definition != null and first_waypoint_definition.waypoint_type == "comet" and second_waypoint_definition.waypoint_type == "moon", "default waypoint catalog cadence is wrong"):
		return
	var expected_waypoint_count: int = 0
	for navigation_planet in field.get_children():
		if navigation_planet is Planet:
			expected_waypoint_count += network.get_neighbors(navigation_planet).size()
	expected_waypoint_count = int(float(expected_waypoint_count) / 2.0)
	if not _check(navigation.get_waypoint_count() == expected_waypoint_count and expected_waypoint_count > 0, "navigation waypoint count is wrong"):
		return
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
				return
			if not _check(waypoint_sprite != null and waypoint_sprite.texture != null and waypoint_sprite.scale.x > 0.0, "navigation waypoint visual is missing"):
				return
			if not _check(waypoint_on_graph, "navigation waypoint is detached from its graph edge"):
				return
	if not _check(rendered_waypoint_count == expected_waypoint_count, "navigation waypoint visuals are incomplete"):
		return
	var ui_theme_config: UIThemeConfig = network.get("ui_theme_config") as UIThemeConfig
	if not _check(ui_theme_config != null and ui_theme_config.validate().is_empty(), "UI theme config validation failed"):
		return
	var transit_config: TransitConfig = manager.get("transit_config") as TransitConfig
	if not _check(transit_config != null, "transit config is missing"):
		return
	var transit_errors := transit_config.validate()
	if not _check(transit_errors.is_empty(), "transit config validation failed"):
		return
	var source: Planet = _find_planet_with_size(field, &"xl") as Planet
	var large_planet: Node = _find_planet_with_size(field, &"l")
	var variable_planet: Node = _find_planet_with_size(field, &"variable")
	if not _check(source != null and large_planet != null and variable_planet != null, "generated planet sizes are missing"):
		return
	if not _check(_count_planets_with_size(field, &"xl") == 2 and _count_planets_with_size(field, &"l") == 1, "generated planet size distribution is wrong"):
		return
	var source_timer: Timer = _find_timer(source)
	var large_timer: Timer = _find_timer(large_planet)
	var variable_timer: Timer = _find_timer(variable_planet)

	if not _check(planet_catalog.planets.size() == 10, "default planet catalog size is wrong"):
		return
	if not _check(get_nodes_in_group("planets").size() == planet_catalog.planets.size(), "planet group count is wrong"):
		return
	if not _check(source_timer.wait_time == 5.0 and large_timer.wait_time == 7.0 and variable_timer.wait_time == 10.0, "spawn intervals are wrong"):
		return

	_observed_planet = source
	source.workers_spawn_requested.connect(_capture_spawn)
	source.call("_on_spawn_timer")
	large_planet.call("_on_spawn_timer")
	variable_planet.call("_on_spawn_timer")
	await process_frame
	if not _check(_observed_state == 1 and _observed_amount == 3 and int(source.worker_state) == 0, "planet state transition is wrong"):
		return
	if not _check(source.worker_count == 3 and large_planet.worker_count == 2 and variable_planet.worker_count == 1, "planet worker counts are wrong"):
		return

	var cluster_script: Script = preload("res://scripts/objects/workers/worker_cluster.gd")
	if not _check(manager.get_child_count() == 0, "idle units should remain count-only"):
		return
	var source_count_label: Label = ui.get_count_label(source)
	if not _check(source_count_label.text == "%s: 3" % source.name, "planet tab count is not live"):
		return

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
		return
	var original_route_mode := world_config.route_mode
	world_config.route_mode = WorldConfig.ROUTE_MODE_NEIGHBORS_ONLY
	if not _check(network.get_route_destinations(source).size() == neighbors.size(), "neighbors_only route mode is not enforced"):
		return
	world_config.route_mode = original_route_mode
	if not _check(panel.visible and destination_option.item_count == route_destinations.size() and route_destinations.size() == 9 and not neighbors.is_empty(), "planet tab or neighbors are missing"):
		return
	var panel_width: float = panel.size.x
	if not _check(panel_width >= ui_theme_config.panel_min_width - 0.1 and panel_width <= ui_theme_config.panel_max_width + 0.1, "responsive UI panel width is outside the configured range"):
		return
	var amount_slider: HSlider = ui.get_amount_slider()
	var preview_label: Label = ui.get_preview_label()
	if not _check(is_instance_valid(amount_slider) and is_instance_valid(preview_label), "dispatch slider or preview is missing"):
		return
	if not _check(amount_slider.min_value == 1 and amount_slider.max_value == 3 and amount_slider.step == 1, "dispatch slider bounds are wrong"):
		return
	var preview_destination: Node2D = network.get_destination(source)
	var preview_path: Array[Vector2] = network.get_route_path(source, preview_destination)
	var preview_route_distance: float = _path_distance(preview_path)
	var direct_distance: float = source.global_position.distance_to(preview_destination.global_position)
	var expected_preview_seconds: float = _FlightTime.seconds_for(preview_route_distance, ui.selected_amount(), transit_config)
	if not _check(preview_path.size() >= 3 and preview_route_distance >= direct_distance, "dispatch preview does not use the navigation path"):
		return
	if not _check(absf(_flight_seconds(preview_label.text) - expected_preview_seconds) <= 0.11, "dispatch preview does not use real route distance"):
		return
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
		return
	var alternate_index := ui.index_of_destination(alternate.name)
	if not _check(alternate_index >= 0, "alternate destination is missing from planet tab"):
		return
	network.call("_on_destination_selected", alternate_index)
	await process_frame
	var alternate_path: Array[Vector2] = network.get_route_path(source, alternate)
	var alternate_distance: float = _path_distance(alternate_path)
	var expected_alternate_seconds: float = _FlightTime.seconds_for(alternate_distance, ui.selected_amount(), transit_config)
	if not _check(absf(_flight_seconds(preview_label.text) - expected_alternate_seconds) <= 0.11, "destination change did not update the preview route distance"):
		return
	if not _check(_flight_seconds(preview_label.text) != preview_seconds_before, "destination change did not alter the preview distance"):
		return
	var preview_at_one := preview_label.text
	amount_slider.value = 2
	await process_frame
	if not _check(preview_label.text != preview_at_one and _flight_seconds(preview_label.text) > _flight_seconds(preview_at_one), "dispatch preview does not update live"):
		return
	ui.toggle_panel()
	if not _check(not panel.visible, "planet tab did not close"):
		return
	ui.toggle_panel()
	if not _check(panel.visible, "planet tab did not reopen"):
		return
	var line_phase: float = network.get_line_phase()
	await create_timer(0.2).timeout
	if not _check(network.get_line_phase() != line_phase, "neighbor line animation is inactive"):
		return
	var destination: Node2D = neighbors[0]
	var destination_index := ui.index_of_destination(destination.name)
	if not _check(destination_index >= 0, "destination is missing from planet tab"):
		return
	network.call("_on_destination_selected", destination_index)
	if not _check(network.get_destination(source) == destination and panel.visible, "destination route was not stored"):
		return
	manager.call("_spawn_clusters", source, 1)
	await process_frame
	if not _check(source.worker_count == 4 and manager.get_child_count() == 0, "idle spawn should only update the planet counter"):
		return
	var send_button: Button = ui.get_send_button()
	if not _check(is_instance_valid(send_button) and not send_button.disabled, "send button is missing or disabled"):
		return
	amount_slider.value = 3
	await process_frame
	var destination_count_before := int(destination.get("worker_count"))
	network.call("_on_send_pressed")
	if not _check(int(source.get("worker_count")) == 1, "send did not deduct the source count"):
		return
	var transit_clusters: Array[Node] = []
	for child in manager.get_children():
		if child.get_script() == cluster_script and child.get("destination_planet") == destination:
			transit_clusters.append(child)
	if not _check(transit_clusters.size() == 3, "send did not launch all packed cluster groups"):
		return
	for transit in transit_clusters:
		if not _check(transit.get_unit_count() == 1, "cluster group sizes are wrong"):
			return
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
			return
	if not _check(_offsets_have_safe_spacing(actual_offsets, formation_spacing), "formation clusters overlap beyond the budget"):
		return
	var transit_distance_before: float = (transit_clusters[0] as Node2D).global_position.distance_to(destination.global_position)
	await create_timer(0.5).timeout
	var transit_distance_after: float = (transit_clusters[0] as Node2D).global_position.distance_to(destination.global_position)
	if not _check(transit_distance_after < transit_distance_before, "transit cluster does not move toward the destination"):
		return
	var destination_offsets: Array[Vector2] = []
	for transit in transit_clusters:
		destination_offsets.append((transit as Node2D).global_position - destination.global_position)
	if not _check(_offsets_have_safe_spacing(destination_offsets, formation_spacing), "formation collapsed during transit"):
		return
	if not _check(_offsets_match_shape(destination_offsets, expected_offsets, 0.05), "destination formation offset drifted"):
		return
	for transit in transit_clusters:
		manager.call("_arrive_cluster", transit)
	await process_frame
	if not _check(int(destination.get("worker_count")) == destination_count_before + 3, "arrival did not add the destination count"):
		return
	await process_frame
	if not _check(manager.get_child_count() == 0, "arrived units should no longer render"):
		return

	var meteor_field: Node = background.get_node("MeteorField")
	var meteor_positions: Array[Vector2] = []
	for meteor in meteor_field.get_children():
		meteor_positions.append(meteor.position)
		var pixels: float = meteor.texture.get_width() * meteor.scale.x
		if not _check(pixels >= 4.0 and pixels <= 10.0, "%s pixel size is invalid" % meteor.name):
			return
	await create_timer(0.2).timeout
	if not _check(meteor_field.get_child(0).position != meteor_positions[0], "meteor movement is inactive"):
		return
	var respawn_meteor: Sprite2D = meteor_field.get_child(0)
	respawn_meteor.position = Vector2(-100.0, 270.0)
	await create_timer(0.05).timeout
	if not _check(respawn_meteor.position != Vector2(-100.0, 270.0), "meteor respawn is inactive"):
		return

	var toxic_details: PlanetDetails = field.get_node("Toxic/PlanetDetails") as PlanetDetails
	var toxic_types := toxic_details.get_detail_types()
	if not _check(toxic_types.size() >= 2 and toxic_types.size() <= 3 and toxic_types.has(&"satellite") and toxic_types.has(&"asteroid_belt"), "Toxic details are incomplete"):
		return
	var stable_types := toxic_types.duplicate()
	toxic_details.set_seed(777)
	var seeded_types := toxic_details.get_detail_types()
	toxic_details.set_seed(777)
	if not _check(seeded_types == toxic_details.get_detail_types() and stable_types.size() <= 3, "planet details are not seed-stable"):
		return
	var orbit: PlanetDetailOrbit = toxic_details.get_node("AsteroidOrbit_0") as PlanetDetailOrbit
	var orbit_angle := orbit.rotation
	await create_timer(0.2).timeout
	if not _check(absf(orbit.rotation - orbit_angle) > 0.001, "Toxic detail orbit is inactive"):
		return
	for child in field.get_children():
		if child is Planet:
			var details: PlanetDetails = child.get_node("PlanetDetails") as PlanetDetails
			if not _check(details.get_detail_types().size() <= 3, "%s has too many planet details" % child.name):
				return

	if not await _run_layout_scale_case(field, planet_catalog, Vector2(960.0, 540.0), 6, 3, original_seed + 101):
		_check(false, "960x540 scaled layout case failed")
		return
	if not await _run_layout_scale_case(field, planet_catalog, Vector2(1920.0, 1080.0), 14, 7, original_seed + 202):
		_check(false, "1920x1080 scaled layout case failed")
		return
	if not await _run_scenario_case(scene, scenario_catalog, &"wide"):
		_check(false, "wide scenario selection case failed")
		return

	print("PASS: SnipWar preflight")
	quit()

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

func _find_timer(planet: Node) -> Timer:
	for child in planet.get_children():
		if child is Timer:
			return child
	return null

func _path_distance(path: Array[Vector2]) -> float:
	var distance: float = 0.0
	for index in range(path.size() - 1):
		distance += path[index].distance_to(path[index + 1])
	return distance

func _flight_seconds(text: String) -> float:
	return float(text.trim_prefix("Flugzeit: ").trim_suffix(" s"))

func _check(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("FAIL: " + message)
	quit(1)
	return false
