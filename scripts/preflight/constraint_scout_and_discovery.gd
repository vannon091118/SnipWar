class_name PreflightConstraintScoutAndDiscovery
extends RefCounted

## Discovery state, timed technology research, scout build/scan gates, worker factory
## unlock, collect-mission gathering and the technology menu rendering.

func constraint_name() -> String:
	return "scout_and_discovery"


func run(ctx: PreflightContext) -> bool:
	var field: Node = ctx.field
	var network: Node = ctx.network
	var game_state: Node = ctx.game_state
	var manager: Node = ctx.manager
	var planet_catalog: PlanetCatalog = ctx.planet_catalog
	var upgrade_catalog: PlanetUpgradeCatalog = ctx.upgrade_catalog
	var ship_manager: ShipManager = field.get_node_or_null("ShipManager") as ShipManager
	if not ctx.check(ship_manager != null, "ShipManager runtime module is missing"):
		return false
	var tech_catalog: TechnologyCatalog = ship_manager.get_technology_catalog()
	var ship_config: ShipConfig = ship_manager.get_ship_config()
	game_state.deal_resources(planet_catalog, preload("res://resources/config/resource_pool_default.tres"), ctx.world_config.layout_seed)
	if not ctx.check(tech_catalog != null and tech_catalog.validate().is_empty(), "technology catalog validation failed"):
		return false
	if not ctx.check(ship_config != null and ship_config.validate().is_empty(), "ship config validation failed"):
		return false
	if not ctx.check(tech_catalog.for_category(TechnologyDefinition.CATEGORY_SHIPS).size() >= 2 and not tech_catalog.for_category(TechnologyDefinition.CATEGORY_MECH).is_empty() and tech_catalog.for_category(TechnologyDefinition.CATEGORY_PLANET).size() >= 2, "technology catalog is missing a ships, mech, or planet branch"):
		return false
	if not ctx.check(tech_catalog.resolve_all().size() == 14, "default technology catalog should contain the original tree plus six branch technologies"):
		return false

	# Three branch points must expose reciprocal exclusions and remain researchable
	# only after their shared parent is complete.
	var advanced_propulsion: TechnologyDefinition = tech_catalog.resolve(&"advanced_propulsion")
	var heavy_armor_plating: TechnologyDefinition = tech_catalog.resolve(&"heavy_armor_plating")
	var deep_scan: TechnologyDefinition = tech_catalog.resolve(&"deep_scan")
	var long_range_sensors: TechnologyDefinition = tech_catalog.resolve(&"long_range_sensors")
	var automated_refinery: TechnologyDefinition = tech_catalog.resolve(&"automated_refinery")
	var bulk_processing: TechnologyDefinition = tech_catalog.resolve(&"bulk_processing")
	if not ctx.check(advanced_propulsion != null and heavy_armor_plating != null and deep_scan != null and long_range_sensors != null and automated_refinery != null and bulk_processing != null, "one or more branching technologies are missing"):
		return false
	if not ctx.check(advanced_propulsion.prerequisite_tech_id == &"weapon_systems" and heavy_armor_plating.prerequisite_tech_id == &"weapon_systems" and advanced_propulsion.mutually_exclusive_with == heavy_armor_plating.id and heavy_armor_plating.mutually_exclusive_with == advanced_propulsion.id, "weapon branch prerequisites or exclusions are incorrect"):
		return false
	if not ctx.check(deep_scan.prerequisite_tech_id == &"scanner_drone" and long_range_sensors.prerequisite_tech_id == &"scanner_drone" and deep_scan.mutually_exclusive_with == long_range_sensors.id and long_range_sensors.mutually_exclusive_with == deep_scan.id, "scanner branch prerequisites or exclusions are incorrect"):
		return false
	if not ctx.check(automated_refinery.prerequisite_tech_id == &"worker_automation" and bulk_processing.prerequisite_tech_id == &"worker_automation" and automated_refinery.mutually_exclusive_with == bulk_processing.id and bulk_processing.mutually_exclusive_with == automated_refinery.id, "economy branch prerequisites or exclusions are incorrect"):
		return false
	if not ctx.check(advanced_propulsion.category == TechnologyDefinition.CATEGORY_SHIPS and advanced_propulsion.cost_resource == GameState.RES_VOLATILE and advanced_propulsion.cost_amount == 20 and heavy_armor_plating.category == TechnologyDefinition.CATEGORY_SHIPS and heavy_armor_plating.cost_resource == GameState.RES_MATERIAL and heavy_armor_plating.cost_amount == 20, "weapon branch research costs are incorrect"):
		return false
	if not ctx.check(deep_scan.category == TechnologyDefinition.CATEGORY_SHIPS and deep_scan.cost_resource == GameState.RES_ENERGY and deep_scan.cost_amount == 15 and long_range_sensors.category == TechnologyDefinition.CATEGORY_SHIPS and long_range_sensors.cost_resource == GameState.RES_RARE and long_range_sensors.cost_amount == 15, "scanner branch research costs are incorrect"):
		return false
	if not ctx.check(automated_refinery.category == TechnologyDefinition.CATEGORY_PLANET and automated_refinery.cost_resource == GameState.RES_RARE and automated_refinery.cost_amount == 25 and bulk_processing.category == TechnologyDefinition.CATEGORY_PLANET and bulk_processing.cost_resource == GameState.RES_BIOMASS and bulk_processing.cost_amount == 25, "economy branch research costs are incorrect"):
		return false
	if not ctx.check(tech_catalog.can_research([&"weapon_systems"], advanced_propulsion.id) and not tech_catalog.can_research([&"weapon_systems", heavy_armor_plating.id], advanced_propulsion.id) and tech_catalog.can_research([&"scanner_drone"], deep_scan.id) and not tech_catalog.can_research([&"scanner_drone", long_range_sensors.id], deep_scan.id) and tech_catalog.can_research([&"worker_automation"], automated_refinery.id) and not tech_catalog.can_research([&"worker_automation", bulk_processing.id], automated_refinery.id), "technology branch exclusion gates are not enforced by the catalog"):
		return false

	# Discovery state: a faction starts knowing only their own planets.
	var player_known_before: Array[StringName] = game_state.known_planets_of(GameState.FACTION_PLAYER)
	if not ctx.check(player_known_before.size() == 1 and player_known_before.has(game_state.homeworld_for(GameState.FACTION_PLAYER)), "player should initially know only their own planet"):
		return false

	# Technology research is gated by prerequisites and spends resources.
	if not ctx.check(not game_state.has_technology(GameState.FACTION_PLAYER, &"scout_hull"), "scout_hull should not be researched initially"):
		return false
	if not ctx.check(not game_state.can_research_technology(GameState.FACTION_PLAYER, &"scanner_drone", tech_catalog), "scanner_drone should require scout_hull first"):
		return false
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_MATERIAL, 100)
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY, 100)
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_BIOMASS, 100)
	if not ctx.check(game_state.research_technology(GameState.FACTION_PLAYER, &"shipyard_construction", tech_catalog), "shipyard construction research should succeed"):
		return false
	var research_menu: TechnologyMenu = network.get_technology_menu()
	if not ctx.check(research_menu != null, "technology menu is missing for research progress feedback"):
		return false
	research_menu.set("_category", TechnologyDefinition.CATEGORY_SHIPS)
	research_menu.call("_set_open", true)
	research_menu.call("_refresh")
	await ctx.await_frame()
	var research_list: VBoxContainer = research_menu.get_node_or_null("TechTabUI/TechPanel/TechMargin/TechVBox/TechScroll/TechList") as VBoxContainer
	var research_progress_visible := false
	if research_list != null:
		for progress_node in research_list.find_children("ResearchProgress", "ProgressBar", true, false):
			var research_progress: ProgressBar = progress_node as ProgressBar
			if research_progress != null and research_progress.visible and research_progress.max_value > 0.0 and research_progress.value < research_progress.max_value:
				research_progress_visible = true
				break
	if not ctx.check(research_progress_visible, "active research did not render a visible progress bar"):
		return false
	research_menu.close()
	game_state.call("advance_research", 999.0)
	if not ctx.check(game_state.can_research_technology(GameState.FACTION_PLAYER, &"scout_hull", tech_catalog), "scout_hull should be researchable after shipyard construction"):
		return false
	if not ctx.check(game_state.research_technology(GameState.FACTION_PLAYER, &"scout_hull", tech_catalog), "scout_hull research should succeed"):
		return false
	game_state.call("advance_research", 999.0)
	if not ctx.check(not game_state.can_research_technology(GameState.FACTION_PLAYER, &"scout_hull", tech_catalog), "scout_hull should not be researchable twice"):
		return false
	if not ctx.check(game_state.research_technology(GameState.FACTION_PLAYER, &"scanner_drone", tech_catalog), "scanner_drone research should succeed after scout_hull"):
		return false
	game_state.call("advance_research", 999.0)
	if not ctx.check(game_state.has_technology(GameState.FACTION_PLAYER, &"scout_hull") and game_state.has_technology(GameState.FACTION_PLAYER, &"scanner_drone"), "researched technologies were not recorded"):
		return false
	for technology in tech_catalog.resolve_all():
		if not ctx.check(technology.visual_asset != null and not technology.mechanic_description.is_empty() and not String(technology.effect_id).is_empty(), "technology %s is missing a visible or mechanical effect" % technology.id):
			return false

	# Planet technologies are per-known-own-planet and have real production effects.
	var player_homeworld: StringName = game_state.homeworld_for(GameState.FACTION_PLAYER)
	var source: Planet = ctx.find_planet_by_id(field, player_homeworld)
	if not ctx.check(source != null, "player homeworld planet for technology test is missing"):
		return false

	# Fog-of-war frontier: the homeworld and its layout neighbors are revealed,
	# everything beyond is softly hidden by the fog shader. The network itself
	# stays fixed per seed.
	if not ctx.check(source.get_fog_state() == Planet.FogState.VISIBLE, "player homeworld should be fully visible"):
		return false
	var frontier_ids: Array[StringName] = [source.planet_id]
	for neighbor in network.get_neighbors(source):
		var neighbor_planet: Planet = neighbor as Planet
		if neighbor_planet != null:
			frontier_ids.append(neighbor_planet.planet_id)
			if not ctx.check(neighbor_planet.get_fog_state() != Planet.FogState.FOG, "layout neighbor should stay revealed on the frontier"):
				return false
	var hidden_beyond := 0
	for field_child in field.get_children():
		var candidate: Planet = field_child as Planet
		if candidate == null or frontier_ids.has(candidate.planet_id):
			continue
		if candidate.get_fog_state() == Planet.FogState.FOG:
			hidden_beyond += 1
	if not ctx.check(hidden_beyond > 0, "planets beyond the revealed frontier should be hidden by the fog shader"):
		return false

	# NavigationField must remember which side of each edge is a planet so its
	# fog-aware renderer can dim/skip edges outside the field of view.
	var navigation: NavigationField = field.get_node_or_null("NavigationField") as NavigationField
	if not ctx.check(navigation != null and navigation.get_edges().size() == navigation._edge_endpoints.size(), "navigation edges and per-edge planet endpoints drift apart (refresh of fog filtering cannot rely on them)"):
		return false
	var has_endpoint_tracking := false
	for endpoints in navigation._edge_endpoints:
		for endpoint in endpoints:
			if endpoint != null:
				has_endpoint_tracking = true
				break
		if has_endpoint_tracking:
			break
	if not ctx.check(has_endpoint_tracking, "navigation field did not record planet endpoints on edges; routes outside the field of view stay visible"):
		return false

	# Capturing a frontier planet expands the fog reveal: its layout-neighbors
	# transition from FOG to FRONTIER, which is what hides the connection lines
	# further out behind the nebula.
	var frontier_candidate: Planet = null
	for neighbor in network.get_neighbors(source):
		var neighbor_planet: Planet = neighbor as Planet
		if neighbor_planet != null and neighbor_planet.get_faction() == GameState.FACTION_NEUTRAL:
			frontier_candidate = neighbor_planet
			break
	if frontier_candidate != null:
		var beyond_before: int = 0
		var beyond_after: int = 0
		for field_child in field.get_children():
			var candidate: Planet = field_child as Planet
			if candidate == null or candidate == frontier_candidate:
				continue
			if candidate.get_fog_state() == Planet.FogState.FOG:
				beyond_before += 1
		game_state.set_faction(frontier_candidate.planet_id, GameState.FACTION_PLAYER)
		await ctx.await_frame()
		for field_child in field.get_children():
			var candidate: Planet = field_child as Planet
			if candidate == null or candidate == frontier_candidate:
				continue
			if candidate.get_fog_state() == Planet.FogState.FOG:
				beyond_after += 1
		if not ctx.check(beyond_after < beyond_before, "capturing a frontier planet did not expand the fog reveal (before=%d after=%d)" % [beyond_before, beyond_after]):
			return false
		game_state.set_faction(frontier_candidate.planet_id, GameState.FACTION_NEUTRAL)
		var known_dict: Dictionary = game_state.get("_known_planets").get(GameState.FACTION_PLAYER, {})
		known_dict.erase(frontier_candidate.planet_id)
		await ctx.await_frame()
	if not ctx.check(not game_state.can_research_planet_technology(GameState.FACTION_PLAYER, source.planet_id, &"planetary_extraction", tech_catalog), "planetary extraction should require planetary survey"):
		return false
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_RARE, 100)
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_MATERIAL, 100)
	if not ctx.check(game_state.research_planet_technology(GameState.FACTION_PLAYER, source.planet_id, &"planetary_survey", tech_catalog), "planetary survey research should succeed for the own homeworld"):
		return false
	if not ctx.check(game_state.has_planet_technology(source.planet_id, &"planetary_survey"), "planetary survey was not stored on the target planet"):
		return false
	if not ctx.check(game_state.can_research_planet_technology(GameState.FACTION_PLAYER, source.planet_id, &"planetary_extraction", tech_catalog), "planetary extraction should unlock after survey"):
		return false

	# Scout build gate: one free starter scout, then shipyard + researched hull/scanner + build cost.
	if not ctx.check(source != null, "player homeworld planet for scout test is missing"):
		return false
	if not ctx.check(game_state.get_starter_scouts(GameState.FACTION_PLAYER) == 1, "a fresh faction should receive exactly one starter scout"):
		return false
	if not ctx.check(ship_manager.can_build_scout(source), "the starter scout should not require a shipyard"):
		return false
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_BIOMASS, 100)
	if not ctx.check(game_state.purchase_upgrade(player_homeworld, &"shipyard", upgrade_catalog), "shipyard purchase for scout test should succeed"):
		return false
	if not ctx.check(ship_manager.can_build_scout(source), "scout build should succeed with starter scout or shipyard + researched techs"):
		return false

	# Build the one starter scout toward an unknown neutral planet and verify arrival discovers it.
	var scan_destinations: Array[Planet] = ship_manager.get_scan_destinations(source)
	var destination: Planet = null
	for scan_candidate in scan_destinations:
		if scan_candidate.get_faction() == GameState.FACTION_NEUTRAL:
			destination = scan_candidate
			break
	if not ctx.check(destination != null and not game_state.is_known(destination.planet_id, GameState.FACTION_PLAYER), "no unknown adjacent neutral planet available for scout discovery"):
		return false
	var non_neighbor_destination: Planet = null
	for route_candidate in network.get_route_destinations(source):
		var route_planet: Planet = route_candidate as Planet
		if route_planet != null and not scan_destinations.has(route_planet):
			non_neighbor_destination = route_planet
			break
	if not ctx.check(non_neighbor_destination != null and ship_manager.build_scout(source, non_neighbor_destination) == null, "scout build accepted a non-adjacent destination"):
		return false
	if not ctx.check(not game_state.can_research_planet_technology(GameState.FACTION_PLAYER, destination.planet_id, &"planetary_survey", tech_catalog), "unknown planets must not accept planet research"):
		return false
	var scout: ScoutShip = ship_manager.build_scout(source, destination)
	if not ctx.check(scout != null and ship_manager.scout_count() == 1, "scout build did not launch a scout"):
		return false
	var scout_hull: Sprite2D = scout.get_node_or_null("Hull") as Sprite2D
	var scout_scanner: Sprite2D = scout.get_node_or_null("Scanner") as Sprite2D
	if not ctx.check(scout_hull != null and scout_hull.texture != null and scout_scanner != null and scout_scanner.texture != null, "scout hull or scanner drone visual is missing"):
		return false
	if not ctx.check(not game_state.is_known(destination.planet_id, GameState.FACTION_PLAYER), "destination should still be unknown before arrival"):
		return false
	scout.call("_arrive")
	await ctx.await_frame()
	if not ctx.check(game_state.is_known(destination.planet_id, GameState.FACTION_PLAYER), "scout arrival did not discover the destination planet"):
		return false
	if not ctx.check(game_state.known_planets_of(GameState.FACTION_PLAYER).has(destination.planet_id), "discovered planet is missing from the known list"):
		return false
	if not ctx.check(game_state.has_scanned_planet(GameState.FACTION_PLAYER, destination.planet_id), "scout arrival did not store scan intel"):
		return false
	var scan_info: Dictionary = game_state.scan_info_for(GameState.FACTION_PLAYER, destination.planet_id)
	if not ctx.check(scan_info.get("resource_id", &"") == destination.get_resource_id() and int(scan_info.get("build_slots", 0)) == destination.get_build_slot_count(), "scan intel does not describe the neutral planet"):
		return false
	if not ctx.check(ship_manager.scout_count() == 0, "scout was not freed after arrival"):
		return false
	if not ctx.check(not game_state.discover_planet(GameState.FACTION_PLAYER, destination.planet_id), "discovering an already-known planet should be a no-op"):
		return false
	if not ctx.check(game_state.get_starter_scouts(GameState.FACTION_PLAYER) == 0, "the starter scout token was not consumed"):
		return false
	if not ctx.check(ship_manager.build_scout(source, destination) == null, "scout build should reject an already-known destination"):
		return false
	var second_destination: Planet = null
	for second_candidate in ship_manager.get_scan_destinations(source):
		if second_candidate != destination:
			second_destination = second_candidate
			break
	if not ctx.check(second_destination != null, "the player needs a second unknown neutral neighbor for continued scout progression"):
		return false
	var second_scout: ScoutShip = ship_manager.build_scout(source, second_destination)
	if not ctx.check(second_scout != null and game_state.get_starter_scouts(GameState.FACTION_PLAYER) == 0, "a researched second scout could not be built after the starter scout"):
		return false
	second_scout.call("_arrive")
	await ctx.await_frame()
	if not ctx.check(game_state.has_scanned_planet(GameState.FACTION_PLAYER, second_destination.planet_id), "the second scout did not reveal a second neutral neighbor"):
		return false
	var shipyard_hangar: ShipyardHangar = source.get_node_or_null("PlanetDetails/UpgradeStructure_shipyard/Hangar") as ShipyardHangar
	if not ctx.check(shipyard_hangar != null and shipyard_hangar.build_slot_count == source.get_build_slot_count(), "shipyard hangar did not inherit planet build slots"):
		return false
	if not ctx.check(shipyard_hangar.get_node_or_null("FutureShipBuilder") != null and not (shipyard_hangar.get_node("FutureShipBuilder") as Node2D).visible, "future ship builder should remain hidden before a ship is assembled"):
		return false
	if not ctx.check(not source.is_worker_spawn_enabled(), "worker production must remain off before worker factory construction"):
		return false
	if not ctx.check(game_state.research_technology(GameState.FACTION_PLAYER, GameState.TECH_WORKER_AUTOMATION, tech_catalog), "worker automation research should unlock after the first scan"):
		return false
	game_state.call("advance_research", 999.0)
	if not ctx.check(ship_manager.can_build_workers(source), "worker factory should be buildable after scan and research"):
		return false
	if not ctx.check(ship_manager.build_workers(source), "worker factory construction should succeed"):
		return false
	if not ctx.check(game_state.has_worker_factory(source.planet_id) and source.is_worker_spawn_enabled(), "worker factory did not enable automatic worker production"):
		return false
	var worker_slot: Node2D = shipyard_hangar.get_node_or_null("BuilderSlots/WorkerSlot_0") as Node2D
	var worker_sprite: Sprite2D = worker_slot.get_node_or_null("Sprite2D") as Sprite2D if worker_slot != null else null
	if not ctx.check(worker_slot != null and worker_slot.visible and worker_sprite != null and worker_sprite.texture != null, "worker factory did not reveal its dedicated hangar asset"):
		return false
	var worker_count_before_factory_tick: int = source.worker_count
	source.call("_on_spawn_timer")
	if not ctx.check(source.worker_count == worker_count_before_factory_tick + source.get_size_profile().spawn_count or source.worker_count > worker_count_before_factory_tick, "worker factory did not start slow automatic spawning"):
		return false
	var collected_resource: StringName = game_state.resource_of(destination.planet_id)
	var collect_workers_before: int = source.worker_count
	if not ctx.check(manager.call("can_dispatch_mission", source, destination, GameState.MISSION_COLLECT), "collect mission gate rejected source=%s destination=%s source_workers=%d destination_faction=%s scanned=%s" % [source.get_faction(), destination.planet_id, source.worker_count, destination.get_faction(), game_state.has_scanned_planet(GameState.FACTION_PLAYER, destination.planet_id)]):
		return false
	manager.call("_dispatch_clusters", source, destination, 1, network.get_route_path(source, destination), GameState.MISSION_COLLECT)
	var collect_cluster: WorkerCluster = null
	for manager_child in manager.get_children():
		if manager_child is WorkerCluster and manager_child.get("destination_planet") == destination:
			collect_cluster = manager_child as WorkerCluster
			break
	if not ctx.check(collect_cluster != null, "collect mission did not launch"):
		return false
	var collect_result: StringName = manager.call("_arrive_cluster", collect_cluster)
	await ctx.await_frame()
	if not ctx.check(source.worker_count == collect_workers_before - 1, "collect mission did not consume source workers"):
		return false
	if not ctx.check(collect_result == Planet.ARRIVAL_COLLECTED and game_state.get_gathering_workers(GameState.FACTION_PLAYER, destination.planet_id) > 0, "collect mission did not begin continuous gathering on the neutral planet (result=%s)" % collect_result):
		return false
	var gather_before: int = game_state.get_faction_resource(GameState.FACTION_PLAYER, collected_resource)
	var gather_generated: int = int(field.get_node_or_null("EconomyManager").call("gather_now"))
	if not ctx.check(gather_generated > 0 and game_state.get_faction_resource(GameState.FACTION_PLAYER, collected_resource) > gather_before, "gather tick did not create the first continuous neutral income (generated=%d resource=%s)" % [gather_generated, collected_resource]):
		return false
	var gatherers_registered: int = game_state.get_gathering_workers(GameState.FACTION_PLAYER, destination.planet_id)
	var source_before_recall: int = source.worker_count
	var recalled: int = int(destination.call("recall_gathering_workers", GameState.FACTION_PLAYER, gatherers_registered))
	if not ctx.check(recalled == gatherers_registered and game_state.get_gathering_workers(GameState.FACTION_PLAYER, destination.planet_id) == 0, "recall did not withdraw all gatherers (recalled=%d expected=%d)" % [recalled, gatherers_registered]):
		return false
	if not ctx.check(source.worker_count == source_before_recall + recalled, "recalled gatherers did not return to the source planet (source=%d expected=%d)" % [source.worker_count, source_before_recall + recalled]):
		return false

	# The technology menu must be reachable from the network host and render the planet branch.
	var technology_menu: TechnologyMenu = network.get_technology_menu()
	if not ctx.check(technology_menu != null, "technology menu was not created by the network"):
		return false
	technology_menu.set("_category", TechnologyDefinition.CATEGORY_PLANET)
	technology_menu.call("_refresh")
	await ctx.await_frame()
	var technology_list: VBoxContainer = technology_menu.get_node_or_null("TechTabUI/TechPanel/TechMargin/TechVBox/TechScroll/TechList") as VBoxContainer
	if not ctx.check(technology_list != null and technology_list.get_child_count() >= 3, "planet technology tab did not render known-planet technology cards"):
		return false
	var rendered_technology_cards: int = 0
	for list_child in technology_list.get_children():
		if list_child is PanelContainer:
			rendered_technology_cards += 1
			var card_content: HBoxContainer = list_child.get_child(0) as HBoxContainer
			var icon: TextureRect = card_content.get_child(0) as TextureRect if card_content != null and card_content.get_child_count() > 0 else null
			if not ctx.check(icon != null and icon.texture != null, "technology card is missing its visual asset"):
				return false
	if not ctx.check(rendered_technology_cards >= 2, "known-planet technology cards have no visual entries"):
		return false
	return true
