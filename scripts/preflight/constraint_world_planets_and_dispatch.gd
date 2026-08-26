class_name PreflightConstraintWorldPlanetsAndDispatch
extends RefCounted

## Navigation graph, planet sizes/ownership, worker spawn, economy tick, UI panel,
## dispatch preview and full transit/arrival/capture semantics.

func constraint_name() -> String:
	return "world_planets_and_dispatch"

func requires_scene() -> bool:
	return true


func run(ctx: PreflightContext) -> bool:
	var background: Node = ctx.background
	var field: Node = ctx.field
	var network: Node = ctx.network
	var game_state: Node = ctx.game_state
	var world_config: WorldConfig = ctx.world_config
	var planet_catalog: PlanetCatalog = ctx.planet_catalog
	var manager: Node = ctx.manager
	var navigation: NavigationField = field.get_node("NavigationField") as NavigationField
	var ui: PlanetNetworkUI = network.get_ui()
	var economy_manager: Node = field.get_node_or_null("EconomyManager")
	var cpu_ai: Node = field.get_node_or_null("CpuDispatchAI")
	if not ctx.check(economy_manager != null and cpu_ai != null, "runtime economy and CPU modules are missing"):
		return false
	var economy_config: EconomyConfig = economy_manager.get("economy_config") as EconomyConfig
	var cpu_dispatch_config: CpuDispatchConfig = cpu_ai.get("dispatch_config") as CpuDispatchConfig
	if not ctx.check(economy_config != null and economy_config.validate().is_empty(), "economy config validation failed"):
		return false
	if not ctx.check(cpu_dispatch_config != null and cpu_dispatch_config.validate().is_empty(), "CPU dispatch config validation failed"):
		return false
	if not ctx.check(not economy_manager.call("is_enabled"), "passive economy must be disabled before worker automation"):
		return false
	# Keep the persistent suite deterministic; both modules expose manual test hooks.
	economy_manager.call("set_enabled", false)
	economy_manager.call("set_gathering_enabled", false)
	cpu_ai.call("set_enabled", false)
	if not ctx.check(navigation != null, "navigation field is missing"):
		return false
	var navigation_config: NavigationConfig = navigation.get("navigation_config") as NavigationConfig
	if not ctx.check(navigation_config != null and navigation_config.validate().is_empty(), "navigation config validation failed"):
		return false
	if not ctx.check(navigation_config.waypoint_catalog != null and navigation_config.waypoint_catalog.definitions.size() >= 2, "navigation waypoint catalog is missing styles"):
		return false
	var first_waypoint_definition: NavigationWaypointDefinition = navigation_config.waypoint_for_edge(0)
	var second_waypoint_definition: NavigationWaypointDefinition = navigation_config.waypoint_for_edge(1)
	if not ctx.check(first_waypoint_definition != null and second_waypoint_definition != null and first_waypoint_definition.waypoint_type == "comet" and second_waypoint_definition.waypoint_type == "moon", "default waypoint catalog cadence is wrong"):
		return false
	var expected_waypoint_count: int = 0
	for navigation_planet in field.get_children():
		if navigation_planet is Planet:
			expected_waypoint_count += network.get_neighbors(navigation_planet).size()
	expected_waypoint_count = int(float(expected_waypoint_count) / 2.0)
	if not ctx.check(navigation.get_waypoint_count() == expected_waypoint_count and expected_waypoint_count > 0, "navigation waypoint count is wrong"):
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
			if not ctx.check((waypoint_node as NavigationWaypoint).waypoint_type == &"moon" or (waypoint_node as NavigationWaypoint).waypoint_type == &"comet", "navigation waypoint type is invalid"):
				return false
			if not ctx.check(waypoint_sprite != null and waypoint_sprite.texture != null and waypoint_sprite.scale.x > 0.0, "navigation waypoint visual is missing"):
				return false
			if not ctx.check(waypoint_on_graph, "navigation waypoint is detached from its graph edge"):
				return false
	if not ctx.check(rendered_waypoint_count == expected_waypoint_count, "navigation waypoint visuals are incomplete"):
		return false
	var ui_theme_config: UIThemeConfig = network.get("ui_theme_config") as UIThemeConfig
	if not ctx.check(ui_theme_config != null and ui_theme_config.validate().is_empty(), "UI theme config validation failed"):
		return false
	if not ctx.check(ui_theme_config.route_line_width > 0.0 and ui_theme_config.route_line_alpha > 0.0 and ui_theme_config.route_line_alpha + ui_theme_config.route_line_pulse_alpha <= 1.0, "route visualization config is invalid"):
		return false
	var transit_config: TransitConfig = manager.get("transit_config") as TransitConfig
	if not ctx.check(transit_config != null, "transit config is missing"):
		return false
	if not ctx.check(network.transit_config_identity_valid(), "PlanetNetwork and WorkerManager use different TransitConfig resources"):
		return false
	var transit_errors := transit_config.validate()
	if not ctx.check(transit_errors.is_empty(), "transit config validation failed"):
		return false
	var default_detail_profile: PlanetDetailProfile = preload("res://resources/config/planet_details/default.tres")
	var toxic_detail_profile: PlanetDetailProfile = preload("res://resources/config/planet_details/toxic.tres")
	if not ctx.check(default_detail_profile.validate().is_empty() and toxic_detail_profile.validate().is_empty(), "planet detail profiles are invalid"):
		return false
	var satellite_definition: PlanetDetailDefinition = preload("res://resources/config/planet_details/satellite.tres")
	var asteroid_definition: PlanetDetailDefinition = preload("res://resources/config/planet_details/asteroid_belt.tres")
	if not ctx.check(satellite_definition.validate().is_empty() and satellite_definition.fidelity != null and satellite_definition.fidelity.orbit_motion_mode == PlanetDetailFidelity.MOTION_FULL and satellite_definition.angular_speed_range.y > satellite_definition.angular_speed_range.x, "satellite detail fidelity config is invalid"):
		return false
	if not ctx.check(asteroid_definition.validate().is_empty() and asteroid_definition.fidelity != null and asteroid_definition.fidelity.orbit_motion_mode == PlanetDetailFidelity.MOTION_THROTTLED and asteroid_definition.fidelity.orbit_update_interval > 0.0, "asteroid detail fidelity config is invalid"):
		return false
	var source: Planet = ctx.find_planet_by_id(field, game_state.homeworld_for(GameState.FACTION_PLAYER)) if world_config.is_infinite_world() else ctx.find_planet_with_size(field, &"xl") as Planet
	var large_planet: Node = ctx.find_planet_with_size(field, &"l")
	var variable_planet: Node = ctx.find_planet_with_size(field, &"variable")
	if not ctx.check(source != null and large_planet != null and variable_planet != null, "generated planet sizes are missing"):
		return false
	var source_starting_workers: int = source.worker_count
	var source_faction: StringName = source.get_faction()
	if not ctx.check(source_faction == game_state.faction_of(source.planet_id) and source.is_in_group("faction_" + String(source_faction)), "planet faction does not follow the GameState source of truth"):
		return false
	game_state.set_faction(source.planet_id, GameState.FACTION_CPU)
	await ctx.await_frame()
	if not ctx.check(source.get_faction() == GameState.FACTION_CPU and game_state.faction_of(source.planet_id) == GameState.FACTION_CPU and source.is_in_group("faction_" + String(GameState.FACTION_CPU)) and not source.is_in_group("faction_" + String(source_faction)), "GameState faction change did not propagate to the planet"):
		return false
	game_state.set_faction(source.planet_id, source_faction)
	await ctx.await_frame()
	if not ctx.check(source.get_faction() == source_faction and game_state.faction_of(source.planet_id) == source_faction, "GameState faction revert was not applied"):
		return false
	var expected_xl: int = 2 if world_config.is_infinite_world() else 2
	var expected_l: int = 1 if world_config.is_infinite_world() else 1
	if world_config.is_infinite_world():
		if not ctx.check(ctx.count_planets_with_size(field, &"xl") >= expected_xl and ctx.count_planets_with_size(field, &"l") >= expected_l, "generated planet size distribution is wrong"):
			return false
	else:
		if not ctx.check(ctx.count_planets_with_size(field, &"xl") == expected_xl and ctx.count_planets_with_size(field, &"l") == expected_l, "generated planet size distribution is wrong"):
			return false
	if not ctx.check(source.get_build_slot_count() == 3 and (large_planet as Planet).get_build_slot_count() == 2 and (variable_planet as Planet).get_build_slot_count() == 1, "planet size profiles do not control build space"):
		return false
	var source_timer: Timer = ctx.find_timer(source)
	var large_timer: Timer = ctx.find_timer(large_planet)
	var variable_timer: Timer = ctx.find_timer(variable_planet)

	if world_config.is_infinite_world():
		if not ctx.check(planet_catalog.planets.size() == 1, "infinite-world catalog should contain one chunk template"):
			return false
		if not ctx.check(ctx.nodes_in_group("planets").size() >= 2, "infinite-world planet group is empty"):
			return false
	else:
		if not ctx.check(planet_catalog.planets.size() == 10, "default planet catalog size is wrong"):
			return false
		if not ctx.check(ctx.nodes_in_group("planets").size() == planet_catalog.planets.size(), "planet group count is wrong"):
			return false
	if not ctx.check(source_timer.wait_time == 5.0 and large_timer.wait_time == 7.0 and variable_timer.wait_time == 10.0, "spawn intervals are wrong"):
		return false
	if not ctx.check(not source.is_worker_spawn_enabled() and not large_planet.is_worker_spawn_enabled() and not variable_planet.is_worker_spawn_enabled(), "worker spawning must be disabled before the first worker factory"):
		return false

	var player_vault_before_spawn: Dictionary = game_state.get_faction_vault_snapshot(GameState.FACTION_PLAYER)
	var cpu_vault_before_spawn: Dictionary = game_state.get_faction_vault_snapshot(GameState.FACTION_CPU)
	ctx.observed_planet = source
	source.set_worker_spawn_enabled(true)
	large_planet.set_worker_spawn_enabled(true)
	variable_planet.set_worker_spawn_enabled(true)
	source.workers_spawn_requested.connect(ctx.capture_spawn)
	source.call("_on_spawn_timer")
	large_planet.call("_on_spawn_timer")
	variable_planet.call("_on_spawn_timer")
	await ctx.await_frame()
	if not ctx.check(ctx.observed_state == 1 and ctx.observed_amount == 3 and int(source.worker_state) == 0, "planet state transition is wrong"):
		return false
	if not ctx.check(source.worker_count == source_starting_workers + 3 and large_planet.worker_count == game_state.starting_workers_of((large_planet as Planet).planet_id) + 2 and variable_planet.worker_count == game_state.starting_workers_of((variable_planet as Planet).planet_id) + 1, "planet worker counts are wrong"):
		return false
	var source_strength_label: Label = source.get_node_or_null("StrengthLabel") as Label
	if not ctx.check(source_strength_label != null and source_strength_label.text == str(source.worker_count), "planet strength indicator does not match worker count"):
		return false
	if not ctx.check(player_vault_before_spawn == game_state.get_faction_vault_snapshot(GameState.FACTION_PLAYER) and cpu_vault_before_spawn == game_state.get_faction_vault_snapshot(GameState.FACTION_CPU), "worker spawn timer still changes passive economy"):
		return false
	source.set_worker_spawn_enabled(false)
	large_planet.set_worker_spawn_enabled(false)
	variable_planet.set_worker_spawn_enabled(false)
	var economy_planet: Planet = ctx.find_planet_by_id(field, game_state.homeworld_for(GameState.FACTION_PLAYER))
	if not ctx.check(economy_planet != null, "player homeworld for economy test is missing"):
		return false
	var economy_resource_id: StringName = game_state.resource_of(economy_planet.planet_id)
	var economy_before: int = game_state.get_faction_resource(GameState.FACTION_PLAYER, economy_resource_id)
	var economy_generated: int = economy_manager.call("tick_now")
	var economy_after: int = game_state.get_faction_resource(GameState.FACTION_PLAYER, economy_resource_id)
	if not ctx.check(economy_generated > 0 and economy_after >= economy_before + economy_planet.get_size_profile().resource_base, "independent economy tick did not generate resources"):
		return false

	var cluster_script: Script = preload("res://scripts/objects/workers/worker_cluster.gd")
	if not ctx.check(manager.get_child_count() == 0, "idle units should remain count-only"):
		return false
	var source_count_label: Label = ui.get_count_label(source)
	if not ctx.check(source_count_label.text == "%s: %d" % [UIBaseUtils.planet_display_name(source), source.worker_count], "planet tab count is not live"):
		return false

	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	source.call("_on_click_area_input_event", null, event, 0)
	await ctx.await_frame()
	var panel: PanelContainer = ui.get_panel()
	var destination_option: OptionButton = ui.get_destination_option()
	var neighbors: Array[Node2D] = network.get_neighbors(source)
	var route_destinations: Array[Node2D] = network.get_route_destinations(source)
	if not ctx.check(world_config.route_mode == WorldConfig.ROUTE_MODE_ALL_PLANETS, "default route mode is not all_planets"):
		return false
	var original_route_mode := world_config.route_mode
	world_config.route_mode = WorldConfig.ROUTE_MODE_NEIGHBORS_ONLY
	if not ctx.check(network.get_route_destinations(source).size() == neighbors.size(), "neighbors_only route mode is not enforced"):
		return false
	world_config.route_mode = original_route_mode
	var expected_route_destinations: bool = route_destinations.size() == 9 if not world_config.is_infinite_world() else route_destinations.size() >= neighbors.size() and route_destinations.size() > 0
	if not ctx.check(panel.visible and destination_option.item_count == route_destinations.size() and expected_route_destinations and not neighbors.is_empty(), "planet tab or neighbors are missing"):
		return false
	await ctx.await_frame()
	var tab_button: Button = ui.get_node("PlanetTabUI/PlanetTab") as Button
	var heading_label: Label = ui.get_node("PlanetTabUI/PlanetPanel/MarginContainer/PanelLayout/PanelScroll/Content/HeadingLabel") as Label
	var selected_count_label: Label = ui.get_node("PlanetTabUI/PlanetPanel/MarginContainer/PanelLayout/PanelScroll/Content/SelectedCountLabel") as Label
	if not ctx.check(tab_button.get_theme_font_size("font_size") == ui_theme_config.tab_font_size and heading_label.get_theme_font_size("font_size") == ui_theme_config.heading_font_size and selected_count_label.get_theme_font_size("font_size") == ui_theme_config.selected_count_font_size, "UI theme font sizes are not applied from the config"):
		return false
	var panel_width: float = panel.size.x
	if not ctx.check(panel_width >= ui_theme_config.panel_min_width - 0.1 and panel_width <= ui_theme_config.panel_max_width + 0.1, "responsive UI panel width is outside the configured range (got %f)" % panel_width):
		return false
	var vault_bar: PanelContainer = ui.get_node("PlanetTabUI/VaultBar") as PanelContainer
	var rate_label: RichTextLabel = vault_bar.get_node_or_null("VaultMargin/VaultContent/IncomeRateLabel") as RichTextLabel if vault_bar != null else null
	var panel_scroll: ScrollContainer = panel.get_node("MarginContainer/PanelLayout/PanelScroll") as ScrollContainer
	if not ctx.check(vault_bar != null and vault_bar.global_position.x + vault_bar.size.x <= panel.global_position.x + 0.1, "resource HUD overlaps the planet panel"):
		return false
	if not ctx.check(rate_label != null and rate_label.text.contains("Einkommen"), "vault bar income-rate label is missing"):
		return false
	var rate_state: Node = ctx.get_root().get_node_or_null("GameState")
	rate_state.resource_generated.emit(economy_planet.planet_id, GameState.RES_ENERGY, 3)
	await ctx.await_frame()
	if not ctx.check(rate_label.text.contains("+0.3/s") and rate_label.text.contains("resource_energy"), "vault bar did not display the latest economy income rate", {"actual_text": rate_label.text}):
		return false
	if not ctx.check(panel_scroll != null and panel_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO, "planet panel does not provide a scrollable menu"):
		return false
	var amount_slider: HSlider = ui.get_amount_slider()
	var preview_label: Label = ui.get_preview_label()
	if not ctx.check(is_instance_valid(amount_slider) and is_instance_valid(preview_label), "dispatch slider or preview is missing"):
		return false
	if not ctx.check(amount_slider.min_value == 1 and amount_slider.max_value == source.worker_count and amount_slider.step == 1, "dispatch slider bounds are wrong"):
		return false
	var preview_destination: Node2D = network.get_destination(source)
	var preview_path: Array[Vector2] = network.get_route_path(source, preview_destination)
	var preview_route_distance: float = ctx.path_distance(preview_path)
	var non_neighbor_destination: Node2D = null
	for candidate in route_destinations:
		if not neighbors.has(candidate):
			non_neighbor_destination = candidate
			break
	if not ctx.check(non_neighbor_destination != null, "all_planets has no non-neighbor destination for multi-hop validation"):
		return false
	var multi_hop_path: Array[Vector2] = network.get_route_path(source, non_neighbor_destination)
	if not ctx.check(multi_hop_path.size() >= 5 and ctx.path_contains_planet(multi_hop_path, field, source, non_neighbor_destination), "all_planets non-neighbor route does not traverse the navigation graph"):
		return false
	var direct_distance: float = source.global_position.distance_to(preview_destination.global_position)
	var expected_preview_seconds: float = FlightTime.seconds_for(preview_route_distance, ui.selected_amount(), transit_config)
	if not ctx.check(preview_path.size() >= 3 and preview_route_distance >= direct_distance, "dispatch preview does not use the navigation path"):
		return false
	if not ctx.check(absf(ctx.flight_seconds(preview_label.text) - expected_preview_seconds) <= 0.11, "dispatch preview does not use real route distance"):
		return false
	var preview_seconds_before: float = ctx.flight_seconds(preview_label.text)
	var alternate: Node2D = preview_destination
	for candidate in neighbors:
		if candidate == preview_destination:
			continue
		var candidate_path: Array[Vector2] = network.get_route_path(source, candidate)
		var candidate_distance: float = ctx.path_distance(candidate_path)
		if absf(candidate_distance - preview_route_distance) > 0.1:
			alternate = candidate
			break
	if not ctx.check(alternate != preview_destination, "no alternate destination with different distance"):
		return false
	var alternate_index := ui.index_of_destination(alternate.name)
	if not ctx.check(alternate_index >= 0, "alternate destination is missing from planet tab"):
		return false
	network.call("_on_destination_selected", alternate_index)
	await ctx.await_frame()
	var alternate_path: Array[Vector2] = network.get_route_path(source, alternate)
	var alternate_distance: float = ctx.path_distance(alternate_path)
	var expected_alternate_seconds: float = FlightTime.seconds_for(alternate_distance, ui.selected_amount(), transit_config)
	if not ctx.check(absf(ctx.flight_seconds(preview_label.text) - expected_alternate_seconds) <= 0.11, "destination change did not update the preview route distance"):
		return false
	if not ctx.check(ctx.flight_seconds(preview_label.text) != preview_seconds_before, "destination change did not alter the preview distance"):
		return false
	var preview_at_one := preview_label.text
	amount_slider.value = 2
	await ctx.await_frame()
	if not ctx.check(preview_label.text != preview_at_one and ctx.flight_seconds(preview_label.text) > ctx.flight_seconds(preview_at_one), "dispatch preview does not update live"):
		return false
	var panel_tab: Button = ui.get_node("PlanetTabUI/PlanetTab") as Button
	if not ctx.check(panel_tab != null and panel_tab.text == "‹  SCHLIESSEN", "open panel tab state is wrong"):
		return false
	ui.toggle_panel()
	if not ctx.check(not panel.visible and panel_tab.text == "PLANETEN  ›", "planet tab did not close"):
		return false
	var escape_event := InputEventKey.new()
	escape_event.keycode = KEY_ESCAPE
	escape_event.pressed = true
	ui.call("_unhandled_input", escape_event)
	if not ctx.check(not panel.visible, "escape should keep the closed panel closed"):
		return false
	ui.toggle_panel()
	if not ctx.check(panel.visible and panel_tab.text == "‹  SCHLIESSEN", "planet tab did not reopen"):
		return false
	var line_phase: float = network.get_line_phase()
	await ctx.await_frame()
	if not ctx.check(network.get_line_phase() != line_phase, "neighbor line animation is inactive"):
		return false
	var destination: Planet = neighbors[0] as Planet
	var destination_index := ui.index_of_destination(destination.name)
	if not ctx.check(destination_index >= 0, "destination is missing from planet tab"):
		return false
	network.call("_on_destination_selected", destination_index)
	if not ctx.check(network.get_destination(source) == destination and panel.visible, "destination route was not stored"):
		return false
	manager.call("_spawn_clusters", source, 1)
	await ctx.await_frame()
	if not ctx.check(source.worker_count == source_starting_workers + 4 and manager.get_child_count() == 0, "idle spawn should only update the planet counter"):
		return false
	var send_button: Button = ui.get_send_button()
	if not ctx.check(is_instance_valid(send_button) and not send_button.disabled, "send button is missing or disabled"):
		return false
	amount_slider.value = 3
	await ctx.await_frame()
	var original_source_faction: StringName = source.get_faction()
	var original_destination_faction: StringName = destination.get_faction()
	var attack_faction: StringName = GameState.FACTION_PLAYER
	game_state.set_faction(source.planet_id, attack_faction)
	game_state.set_faction(destination.planet_id, GameState.FACTION_NEUTRAL)
	destination.unregister_workers(destination.worker_count)
	ctx.observed_faction_planet = &""
	ctx.observed_old_faction = &""
	ctx.observed_new_faction = &""
	var destination_count_before: int = destination.worker_count
	network.call("_on_send_pressed")
	if not ctx.check(int(source.get("worker_count")) == source_starting_workers + 1, "send did not deduct the source count"):
		return false
	var transit_clusters: Array[Node] = []
	for child in manager.get_children():
		if child.get_script() == cluster_script and child.get("destination_planet") == destination:
			transit_clusters.append(child)
	if not ctx.check(transit_clusters.size() == 3, "send did not launch all packed cluster groups"):
		return false
	for transit in transit_clusters:
		if not ctx.check(transit.get_unit_count() == 1 and transit.get("source_faction") == attack_faction, "cluster group sizes or source faction are wrong"):
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
		if not ctx.check(actual_offset.distance_to(expected_offsets[index]) <= 0.05, "transit cluster formation offset is wrong"):
			return false
	if not ctx.check(ctx.offsets_have_safe_spacing(actual_offsets, formation_spacing), "formation clusters overlap beyond the budget"):
		return false
	var transit_distance_before: float = (transit_clusters[0] as Node2D).global_position.distance_to(destination.global_position)
	await ctx.await_frame()
	var transit_distance_after: float = (transit_clusters[0] as Node2D).global_position.distance_to(destination.global_position)
	if not ctx.check(transit_distance_after < transit_distance_before, "transit cluster does not move toward the destination"):
		return false
	var destination_offsets: Array[Vector2] = []
	for transit in transit_clusters:
		destination_offsets.append((transit as Node2D).global_position - destination.global_position)
	if not ctx.check(ctx.offsets_have_safe_spacing(destination_offsets, formation_spacing), "formation collapsed during transit"):
		return false
	if not ctx.check(ctx.offsets_match_shape(destination_offsets, expected_offsets, 0.05), "destination formation offset drifted"):
		return false
	var arrival_results: Array[StringName] = []
	for transit in transit_clusters:
		var arrival_result: StringName = manager.call("_arrive_cluster", transit)
		arrival_results.append(arrival_result)
	await ctx.await_frame()
	if not ctx.check(arrival_results.size() == 3 and arrival_results[0] == Planet.ARRIVAL_CAPTURED and arrival_results[1] == Planet.ARRIVAL_FRIENDLY and arrival_results[2] == Planet.ARRIVAL_FRIENDLY, "arrival conflict results are wrong"):
		return false
	if not ctx.check(int(destination.get("worker_count")) == destination_count_before + 3 and destination.get_faction() == attack_faction and game_state.faction_of(destination.planet_id) == attack_faction, "capture did not transfer ownership and survivors"):
		return false
	if not ctx.check(ctx.observed_faction_planet == destination.planet_id and ctx.observed_old_faction == GameState.FACTION_NEUTRAL and ctx.observed_new_faction == attack_faction, "capture did not emit faction_changed"):
		return false
	var friendly_before: int = destination.worker_count
	var friendly_result: StringName = destination.resolve_arrival(attack_faction, 2)
	if not ctx.check(friendly_result == Planet.ARRIVAL_FRIENDLY and destination.worker_count == friendly_before + 2, "friendly arrival did not reinforce the destination"):
		return false
	var repel_target: Planet = null
	for candidate in field.get_children():
		if candidate is Planet and candidate != source and candidate != destination and (candidate as Planet).worker_count >= 2:
			repel_target = candidate as Planet
			break
	if not ctx.check(repel_target != null, "no defended planet available for repel test"):
		return false
	game_state.set_faction(repel_target.planet_id, GameState.FACTION_NEUTRAL)
	var repel_before: int = repel_target.worker_count
	var repel_result: StringName = repel_target.resolve_arrival(attack_faction, 1)
	if not ctx.check(repel_result == Planet.ARRIVAL_REPELLED and repel_target.worker_count == repel_before - 1 and repel_target.get_faction() == GameState.FACTION_NEUTRAL, "defended arrival was not repelled"):
		return false
	game_state.set_faction(source.planet_id, original_source_faction)
	game_state.set_faction(destination.planet_id, original_destination_faction)
	await ctx.await_frame()
	if not ctx.check(manager.get_child_count() == 0, "arrived units should no longer render"):
		return false

	# ── FleetOverview existence + wiring ────────────────────────────
	var fleet_overview: FleetOverview = network.get_fleet_overview() if network.has_method("get_fleet_overview") else null
	if not ctx.check(fleet_overview != null, "fleet overview is not attached to PlanetNetwork"):
		return false
	if not ctx.check(fleet_overview.has_signal("ship_drop_requested") and fleet_overview.has_signal("focus_requested"), "fleet overview is missing its drag-drop or focus signals"):
		return false

	# ── EconomyWindow module existence + toggle ─────────────────────
	var economy_window: EconomyWindow = network.get("_economy_window") as EconomyWindow
	if not ctx.check(economy_window != null and is_instance_valid(economy_window), "economy window module is not attached to PlanetNetwork"):
		return false
	if not ctx.check(economy_window.has_method("toggle") and economy_window.has_method("open") and economy_window.has_method("close"), "economy window is missing toggle/open/close methods"):
		return false
	if not ctx.check(not economy_window.is_open(), "economy window should start closed"):
		return false
	economy_window.open()
	await ctx.await_frame()
	if not ctx.check(economy_window.is_open(), "economy window did not open"):
		return false
	economy_window.close()
	await ctx.await_frame()
	if not ctx.check(not economy_window.is_open(), "economy window did not close"):
		return false

	return true
