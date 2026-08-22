class_name ConceptIndex
extends RefCounted

## Hierarchical concept-to-code mapping for agent code discovery.
##
## Problem: ripgrep/code_search is exact-match only. Searching "fleet" misses
## ShipBase, ShipManager, CompositeShipView. Searching "s" produces 1000+ noise
## results. Agents need a conceptual map that transcends naming.
##
## Usage (from preflight or agent):
##   var idx := ConceptIndex.new()
##   var results := idx.search("fleet")  # → ships, combat, transit
##   var results2 := idx.search("money")  # → economy, resources, credits
##   var results3 := idx.expand("ship")   # → fleet, vessel, craft, armada, ...

## --- Concept Entry ---

class ConceptEntry extends RefCounted:
	var concept: String           ## Primary concept name (e.g. "fleet_management")
	var domain: String            ## Subsystem domain
	var classes: Array = []       ## class_name identifiers
	var files: Array = []         ## Resolved file paths (res://...)
	var methods: Array = []       ## Key public methods
	var description: String       ## One-line description

	func to_dict() -> Dictionary:
		return {
			"concept": concept,
			"domain": domain,
			"classes": classes,
			"files": files,
			"methods": methods,
			"description": description,
		}


## --- Thesaurus: synonym → canonical concept ---

var _synonyms: Dictionary = {}  ## lowercase synonym → canonical concept name
var _concepts: Dictionary = {}  ## concept name → ConceptEntry
var _class_to_concept: Dictionary = {}  ## class_name → concept name


func _init() -> void:
	_build_thesaurus()
	_build_concepts()


## --- Public API ---

## Search by free-text term. Returns Array sorted by relevance.
## Matches against: concept names, synonyms, class names, descriptions, methods.
func search(query: String) -> Array:
	var q := query.strip_edges().to_lower()
	if q.is_empty():
		return []

	var hits: Array[Dictionary] = []  # {entry, score}

	# Phase 1: exact synonym lookup (score 100)
	if _synonyms.has(q):
		var concept_name: String = _synonyms[q] as String
		if _concepts.has(concept_name):
			hits.append({"entry": _concepts[concept_name], "score": 100})

	# Phase 2: concept name contains query (score 80)
	for concept_name in _concepts:
		var entry: ConceptEntry = _concepts[concept_name] as ConceptEntry
		if String(concept_name).contains(q):
			hits.append({"entry": entry, "score": 80})

	# Phase 3: class name contains query (score 70)
	for cls_name in _class_to_concept:
		if String(cls_name).to_lower().contains(q):
			var concept_name: String = _class_to_concept[cls_name] as String
			if _concepts.has(concept_name):
				var entry: ConceptEntry = _concepts[concept_name] as ConceptEntry
				if not _hit_exists(hits, entry):
					hits.append({"entry": entry, "score": 70})

	# Phase 4: description contains query (score 50)
	for concept_name in _concepts:
		var entry: ConceptEntry = _concepts[concept_name] as ConceptEntry
		if entry.description.to_lower().contains(q):
			if not _hit_exists(hits, entry):
				hits.append({"entry": entry, "score": 50})

	# Phase 5: method name contains query (score 40)
	for concept_name in _concepts:
		var entry: ConceptEntry = _concepts[concept_name] as ConceptEntry
		for method_name in entry.methods:
			if String(method_name).to_lower().contains(q):
				if not _hit_exists(hits, entry):
					hits.append({"entry": entry, "score": 40})
				break

	# Phase 6: file path contains query (score 30)
	for concept_name in _concepts:
		var entry: ConceptEntry = _concepts[concept_name] as ConceptEntry
		for file_path in entry.files:
			if file_path.to_lower().contains(q):
				if not _hit_exists(hits, entry):
					hits.append({"entry": entry, "score": 30})
				break

	# Sort by score descending
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["score"] as int) > (b["score"] as int)
	)

	var result: Array = []
	for hit in hits:
		result.append(hit["entry"] as ConceptEntry)
	return result


## Expand a term into related concepts (synonyms + domain siblings).
## Returns Array — useful for "show me everything related to X".
func expand(query: String) -> Array:
	var q := query.strip_edges().to_lower()
	var concept_set: Dictionary = {}  # dedup

	# Find the canonical concept for this term
	var canonical: String = ""
	if _synonyms.has(q):
		canonical = _synonyms[q] as String

	# Search by class name match too
	if canonical.is_empty():
		for cls_name in _class_to_concept:
			if String(cls_name).to_lower() == q:
				canonical = _class_to_concept[cls_name] as String
				break

	# If we found a canonical concept, add it + its domain siblings
	if not canonical.is_empty() and _concepts.has(canonical):
		var primary: ConceptEntry = _concepts[canonical] as ConceptEntry
		concept_set[canonical] = true
		# Add all concepts in the same domain
		for concept_name in _concepts:
			var entry: ConceptEntry = _concepts[concept_name] as ConceptEntry
			if entry.domain == primary.domain:
				concept_set[concept_name] = true
	else:
		# Fuzzy: add all concepts where query appears in any field
		var search_results := search(query)
		for entry in search_results:
			concept_set[entry.concept] = true

	var result: Array = []
	for concept_name in concept_set:
		if _concepts.has(concept_name):
			result.append(_concepts[concept_name] as ConceptEntry)
	return result


## Get all concepts for a specific domain.
func by_domain(domain: String) -> Array:
	var result: Array = []
	for concept_name in _concepts:
		var entry: ConceptEntry = _concepts[concept_name] as ConceptEntry
		if entry.domain == domain:
			result.append(entry)
	return result


## Get a concept by exact name.
func get_concept(name: String) -> ConceptEntry:
	return _concepts.get(name, null) as ConceptEntry


## Get the concept that owns a given class_name.
func class_concept(cls_name: String) -> ConceptEntry:
	var concept_name: String = _class_to_concept.get(cls_name, "") as String
	if concept_name.is_empty():
		return null
	return _concepts.get(concept_name, null) as ConceptEntry


## List all available domains.
func domains() -> PackedStringArray:
	var seen: Dictionary = {}
	var result: PackedStringArray = []
	for concept_name in _concepts:
		var entry: ConceptEntry = _concepts[concept_name] as ConceptEntry
		if not seen.has(entry.domain):
			seen[entry.domain] = true
			result.append(entry.domain)
	return result


## Summary for reporting.
func summary() -> String:
	return "%d concepts across %d domains, %d class mappings, %d synonyms" % [
		_concepts.size(), domains().size(), _class_to_concept.size(), _synonyms.size()
	]


## --- Thesaurus Construction ---

func _build_thesaurus() -> void:
	# Fleet / Ships
	_thesaurus("fleet", "fleet_management")
	_thesaurus("flotte", "fleet_management")
	_thesaurus("vessel", "fleet_management")
	_thesaurus("ship", "fleet_management")
	_thesaurus("schiff", "fleet_management")
	_thesaurus("armada", "fleet_management")
	_thesaurus("craft", "fleet_management")
	_thesaurus("vehicle", "fleet_management")
	_thesaurus("hull", "fleet_management")
	_thesaurus("assembly", "fleet_management")
	_thesaurus("shipyard", "fleet_management")
	_thesaurus("hangar", "fleet_management")
	_thesaurus("dispatch", "fleet_management")
	_thesaurus("launch", "fleet_management")
	_thesaurus("blueprint", "fleet_management")
	_thesaurus("modul", "fleet_management")
	_thesaurus("weapon", "fleet_management")
	_thesaurus("scanner", "fleet_management")
	_thesaurus("drive", "fleet_management")
	_thesaurus("shield", "fleet_management")

	# Economy / Resources
	_thesaurus("economy", "economy_resources")
	_thesaurus("ökonomie", "economy_resources")
	_thesaurus("resource", "economy_resources")
	_thesaurus("ressource", "economy_resources")
	_thesaurus("money", "economy_resources")
	_thesaurus("geld", "economy_resources")
	_thesaurus("credit", "economy_resources")
	_thesaurus("kredit", "economy_resources")
	_thesaurus("vault", "economy_resources")
	_thesaurus("tresor", "economy_resources")
	_thesaurus("harvest", "economy_resources")
	_thesaurus("ernte", "economy_resources")
	_thesaurus("gather", "economy_resources")
	_thesaurus("sammeln", "economy_resources")
	_thesaurus("gatherer", "economy_resources")
	_thesaurus("deal", "economy_resources")
	_thesaurus("upgrade", "economy_resources")
	_thesaurus("factory", "economy_resources")
	_thesaurus("fabrik", "economy_resources")
	_thesaurus("refinery", "economy_resources")
	_thesaurus("trade", "economy_resources")
	_thesaurus("handel", "economy_resources")
	_thesaurus("building", "economy_resources")
	_thesaurus("gebäude", "economy_resources")
	_thesaurus("local resource", "economy_resources")
	_thesaurus("lokal resource", "economy_resources")
	_thesaurus("planet building", "economy_resources")

	# Workers / Transit
	_thesaurus("worker", "workers_transit")
	_thesaurus("arbeiter", "workers_transit")
	_thesaurus("transport", "workers_transit")
	_thesaurus("transit", "workers_transit")
	_thesaurus("cluster", "workers_transit")
	_thesaurus("tier", "workers_transit")
	_thesaurus("formation", "workers_transit")
	_thesaurus("flight", "workers_transit")
	_thesaurus("flug", "workers_transit")
	_thesaurus("flugzeit", "workers_transit")
	_thesaurus("flight time", "workers_transit")

	# Navigation / World
	_thesaurus("navigation", "navigation_world")
	_thesaurus("routing", "navigation_world")
	_thesaurus("route", "navigation_world")
	_thesaurus("pfad", "navigation_world")
	_thesaurus("waypoint", "navigation_world")
	_thesaurus("waypoints", "navigation_world")
	_thesaurus("graph", "navigation_world")
	_thesaurus("neighbor", "navigation_world")
	_thesaurus("nachbar", "navigation_world")
	_thesaurus("adjacency", "navigation_world")
	_thesaurus("k-nearest", "navigation_world")

	# World generation / Layout
	_thesaurus("world", "world_generation")
	_thesaurus("welt", "world_generation")
	_thesaurus("layout", "world_generation")
	_thesaurus("seed", "world_generation")
	_thesaurus("catalog", "world_generation")
	_thesaurus("katalog", "world_generation")
	_thesaurus("chunk", "world_generation")
	_thesaurus("infinite", "world_generation")
	_thesaurus("unendlich", "world_generation")
	_thesaurus("sector", "world_generation")
	_thesaurus("flavor", "world_generation")
	_thesaurus("classifier", "world_generation")
	_thesaurus("generation", "world_generation")
	_thesaurus("generator", "world_generation")

	# Planets
	_thesaurus("planet", "planets")
	_thesaurus("planetoid", "planets")
	_thesaurus("homeworld", "planets")
	_thesaurus("heimwelt", "planets")
	_thesaurus("neutral", "planets")
	_thesaurus("owned", "planets")
	_thesaurus("faction", "planets")
	_thesaurus("fraktion", "planets")
	_thesaurus("ownership", "planets")
	_thesaurus("besitz", "planets")
	_thesaurus("scan", "planets")
	_thesaurus("discover", "planets")
	_thesaurus("discovery", "planets")
	_thesaurus("size profile", "planets")
	_thesaurus("detail", "planets")
	_thesaurus("procedural", "planets")
	_thesaurus("grid", "planets")
	_thesaurus("orbit", "planets")
	_thesaurus("capture", "planets")
	_thesaurus("eroberung", "planets")

	# Combat / Battle
	_thesaurus("combat", "combat_battle")
	_thesaurus("kampf", "combat_battle")
	_thesaurus("battle", "combat_battle")
	_thesaurus("schlacht", "combat_battle")
	_thesaurus("conquest", "combat_battle")
	_thesaurus("replay", "combat_battle")
	_thesaurus("simulator", "combat_battle")
	_thesaurus("hp", "combat_battle")
	_thesaurus("dps", "combat_battle")
	_thesaurus("wave", "combat_battle")
	_thesaurus("conflict", "combat_battle")
	_thesaurus("engagement", "combat_battle")
	_thesaurus("tower defense", "combat_battle")

	# Technology / Research
	_thesaurus("technology", "technology_research")
	_thesaurus("technologie", "technology_research")
	_thesaurus("tech", "technology_research")
	_thesaurus("research", "technology_research")
	_thesaurus("forschung", "technology_research")
	_thesaurus("prerequisite", "technology_research")
	_thesaurus("voraussetzung", "technology_research")
	_thesaurus("trait", "technology_research")
	_thesaurus("effect", "technology_research")
	_thesaurus("effect_definition", "technology_research")

	# UI
	_thesaurus("menu", "ui_systems")
	_thesaurus("panel", "ui_systems")
	_thesaurus("button", "ui_systems")
	_thesaurus("overlay", "ui_systems")
	_thesaurus("tooltip", "ui_systems")
	_thesaurus("toast", "ui_systems")
	_thesaurus("feed", "ui_systems")
	_thesaurus("message", "ui_systems")
	_thesaurus("theme", "ui_systems")
	_thesaurus("style", "ui_systems")
	_thesaurus("parchment", "ui_systems")
	_thesaurus("paper", "ui_systems")
	_thesaurus("dossier", "ui_systems")
	_thesaurus("pause", "ui_systems")

	# Scene flow
	_thesaurus("scene", "scene_flow")
	_thesaurus("szene", "scene_flow")
	_thesaurus("director", "scene_flow")
	_thesaurus("transition", "scene_flow")
	_thesaurus("wechsel", "scene_flow")
	_thesaurus("context handover", "scene_flow")
	_thesaurus("save", "scene_flow")
	_thesaurus("load", "scene_flow")
	_thesaurus("speichern", "scene_flow")
	_thesaurus("laden", "scene_flow")
	_thesaurus("slot", "scene_flow")
	_thesaurus("snapshot", "scene_flow")
	_thesaurus("session", "scene_flow")

	# Events / Signals
	_thesaurus("signal", "events_signals")
	_thesaurus("event", "events_signals")
	_thesaurus("eventlog", "events_signals")
	_thesaurus("log", "events_signals")
	_thesaurus("push", "events_signals")

	# Preflight / Testing
	_thesaurus("preflight", "testing_quality")
	_thesaurus("constraint", "testing_quality")
	_thesaurus("test", "testing_quality")
	_thesaurus("fixture", "testing_quality")
	_thesaurus("scenario", "testing_quality")
	_thesaurus("mechanic", "testing_quality")
	_thesaurus("coverage", "testing_quality")

	# CPU AI
	_thesaurus("cpu", "cpu_ai")
	_thesaurus("ai", "cpu_ai")
	_thesaurus("opponent", "cpu_ai")
	_thesaurus("gegner", "cpu_ai")
	_thesaurus("autopilot", "cpu_ai")

	# Missions
	_thesaurus("mission", "missions")
	_thesaurus("auftrag", "missions")
	_thesaurus("scout", "missions")
	_thesaurus("collect", "missions")
	_thesaurus("gather mission", "missions")
	_thesaurus("research mission", "missions")

	# Persistent ships
	_thesaurus("persistent", "persistent_ships")
	_thesaurus("persistent ship", "persistent_ships")
	_thesaurus("research ship", "persistent_ships")
	_thesaurus("forschungsschiff", "persistent_ships")

	# Background / Visuals
	_thesaurus("background", "background_visuals")
	_thesaurus("hintergrund", "background_visuals")
	_thesaurus("starfield", "background_visuals")
	_thesaurus("nebula", "background_visuals")
	_thesaurus("meteor", "background_visuals")
	_thesaurus("multi mesh", "background_visuals")
	_thesaurus("multimesh", "background_visuals")
	_thesaurus("fog", "background_visuals")
	_thesaurus("fog of war", "background_visuals")

	# Selection / Input
	_thesaurus("select", "selection_input")
	_thesaurus("selekt", "selection_input")
	_thesaurus("click", "selection_input")
	_thesaurus("klick", "selection_input")
	_thesaurus("input", "selection_input")
	_thesaurus("camera", "selection_input")
	_thesaurus("pan", "selection_input")
	_thesaurus("zoom", "selection_input")
	_thesaurus("context menu", "selection_input")
	_thesaurus("rechtsklick", "selection_input")


func _thesaurus(synonym: String, canonical: String) -> void:
	_synonyms[synonym] = canonical


## --- Concept Construction ---

func _build_concepts() -> void:
	_add_concept("fleet_management", "ships", [
		"ShipBase", "ShipManager", "ShipyardHangar", "CompositeShipView",
		"ShipAssembly", "ShipBlueprint", "ShipPartCatalog", "ShipPartDefinition",
		"ShipComponentVariant", "ShipConfig", "FleetSnapshot", "FleetOverview",
		"IngamePlayerControls", "Dispatch",
	], [
		"scripts/objects/ships/ship_base.gd",
		"scripts/objects/ships/ship_manager.gd",
		"scripts/objects/ships/shipyard_hangar.gd",
		"scripts/objects/ships/composite_ship_view.gd",
		"scripts/config/ship_assembly.gd",
		"scripts/config/ship_blueprint.gd",
		"scripts/config/ship_part_catalog.gd",
		"scripts/config/ship_part_definition.gd",
		"scripts/config/ship_component_variant.gd",
		"scripts/config/ship_config.gd",
		"scripts/config/fleet_snapshot.gd",
		"scripts/ui/fleet_overview.gd",
		"scripts/ui/ingame_player_controls.gd",
		"scripts/dispatch.gd",
	], [
		"assemble_ship", "disassemble_ship", "launch_ship", "create_fleet_from_planet",
		"preview_fleet_from_planet", "disband_fleet_to_planet", "reconcile_defender_fleet",
		"get_ship_assemblies", "get_ship_part_inventory", "ship_build_in_progress",
		"buy_ship_part", "can_assemble_ship",
	], "Ship assembly, dispatch, fleet management, part catalog, blueprint system"
	)

	_add_concept("economy_resources", "economy", [
		"EconomyDomain", "EconomyConfig", "PlanetEconomyManager", "EconomyWindow",
		"ResourcePool", "GameResource", "BuildingCatalog", "BuildingDefinition",
		"PlanetUpgradeCatalog", "PlanetUpgradeDefinition",
		"TraitDefinition", "EffectDefinition",
	], [
		"scripts/state/domains/economy_domain.gd",
		"scripts/config/economy_config.gd",
		"scripts/objects/planets/economy_manager.gd",
		"scripts/ui/economy_window.gd",
		"scripts/config/resource_pool.gd",
		"scripts/config/game_resource.gd",
		"scripts/config/building_catalog.gd",
		"scripts/config/building_definition.gd",
		"scripts/config/planet_upgrade_catalog.gd",
		"scripts/config/planet_upgrade_definition.gd",
		"scripts/config/trait_definition.gd",
		"scripts/config/effect_definition.gd",
	], [
		"add_faction_resource", "spend_faction_resource", "can_spend_faction_resource",
		"get_faction_resource", "deal_resources", "deal_resources_for_planets",
		"register_gathering_workers", "withdraw_gathering_workers", "gather_income_tick",
		"purchase_upgrade", "can_purchase_upgrade", "has_planet_upgrade",
		"can_place_planet_building", "place_planet_building", "remove_planet_building",
		"get_local_resource", "add_local_resource", "spend_local_resource",
		"transfer_local_resources", "deal_local_resources",
		"can_register_trade_route", "register_trade_route", "tick_trade_routes",
		"has_worker_factory", "can_build_worker_factory", "build_worker_factory",
	], "Economy domain: vaults, resources, upgrades, buildings, gathering, trade routes"
	)

	_add_concept("workers_transit", "transit", [
		"WorkerCluster", "ClusterTierDefinition", "FlightTime", "TransitConfig",
		"TransitRecord",
	], [
		"scripts/objects/workers/worker_cluster.gd",
		"scripts/config/cluster_tier_definition.gd",
		"scripts/flight_time.gd",
		"scripts/config/transit_config.gd",
		"scripts/config/transit_record.gd",
	], [
		"begin_worker_transport", "update_worker_transport", "complete_worker_transport",
		"get_worker_transport_records", "set_worker_transport_escorted",
		"register_transit", "update_transit", "remove_transit", "get_transit",
	], "Worker transit, cluster packing, flight time calculation, transit records"
	)

	_add_concept("navigation_world", "navigation", [
		"NavigationField", "NavigationWaypoint", "NavigationConfig",
		"NavigationWaypointCatalog", "NavigationWaypointDefinition",
	], [
		"scripts/objects/planets/navigation_field.gd",
		"scripts/objects/planets/navigation_waypoint.gd",
		"scripts/config/navigation_config.gd",
		"scripts/config/navigation_waypoint_catalog.gd",
		"scripts/config/navigation_waypoint_definition.gd",
	], [
		"find_route", "get_neighbors", "build_graph",
	], "Navigation field, waypoint system, K-nearest graph, route finding"
	)

	_add_concept("world_generation", "world", [
		"WorldConfig", "WorldGenerator", "WorldBootstrap", "SeededLayout",
		"ChunkCoordinator", "ChunkSaveData", "ScenarioCatalog", "ScenarioDefinition",
		"MapDefinition", "PlanetCatalog", "PlanetDefinition", "SectorClassifier",
		"SectorFlavor", "SectorFlavorCatalog", "SectorAnchor", "AssetLibrary",
		"BackgroundConfig", "PaperStyleConfig", "MeteorConfig",
	], [
		"scripts/config/world_config.gd",
		"scripts/config/world_generator.gd",
		"scripts/bootstrap/world_bootstrap.gd",
		"scripts/objects/seeded_layout.gd",
		"scripts/objects/chunk_coordinator.gd",
		"scripts/state/chunk_save_data.gd",
		"scripts/config/scenario_catalog.gd",
		"scripts/config/scenario_definition.gd",
		"scripts/config/map_definition.gd",
		"scripts/config/planet_catalog.gd",
		"scripts/config/planet_definition.gd",
		"scripts/config/sector_classifier.gd",
		"scripts/config/sector_flavor.gd",
		"scripts/config/sector_flavor_catalog.gd",
		"scripts/config/sector_anchor.gd",
		"scripts/config/asset_library.gd",
		"scripts/config/background_config.gd",
		"scripts/config/paper_style_config.gd",
		"scripts/config/meteor_config.gd",
	], [
		"generate_catalog", "reset_from_catalog", "reset_for_infinite_world",
		"set_layout_seed", "_refresh_chunks", "configure",
		"resolved_columns", "resolved_size_class_counts", "resolved_design_size",
		"resolved_target_planet_count", "is_infinite_world", "chunk_size",
	], "World generation, seeded layout, chunk system, sectors, scenarios, catalogs"
	)

	_add_concept("planets", "planets", [
		"Planet", "PlanetView", "PlanetDetails", "PlanetDetailOrbit",
		"PlanetProcedural", "PlanetTraitAggregator", "PlanetArrivalResolver",
		"PlanetNetwork", "PlanetNetworkUI", "PlanetGrid", "PlanetGridConfig",
		"PlanetGridCell", "PlanetSizeProfile", "PlanetDetailProfile",
		"PlanetDetailDefinition", "PlanetDetailFidelity", "SelectionService",
		"ContextMenuBuilder",
	], [
		"scripts/objects/planets/planet.gd",
		"scripts/objects/planets/view/planet_view.gd",
		"scripts/objects/planets/planet_details.gd",
		"scripts/objects/planets/planet_detail_orbit.gd",
		"scripts/objects/planets/procedural/planet_procedural.gd",
		"scripts/objects/planets/traits/planet_trait_aggregator.gd",
		"scripts/objects/planets/arrival/planet_arrival_resolver.gd",
		"scripts/objects/planets/planet_network.gd",
		"scripts/objects/planets/planet_network_ui.gd",
		"scripts/objects/planets/planet_grid.gd",
		"scripts/config/planet_grid_config.gd",
		"scripts/config/planet_grid_cell.gd",
		"scripts/config/planet_size_profile.gd",
		"scripts/config/planet_detail_profile.gd",
		"scripts/config/planet_detail_definition.gd",
		"scripts/config/planet_detail_fidelity.gd",
		"scripts/objects/selection_service.gd",
		"scripts/objects/planets/context/context_menu_builder.gd",
	], [
		"register_planet", "register_homeworld", "faction_of", "is_owned_by",
		"homeworld_for", "discover_planet", "scan_planet", "has_scanned_planet",
		"capture_planet", "steal_resources", "get_faction_credits",
		"all_owned_planets", "get_ownership_count", "known_planets_of",
		"set_faction", "set_pending_battle_context", "pending_battle_context",
	], "Planet lifecycle, ownership, discovery, scanning, traits, grid, context menus"
	)

	_add_concept("combat_battle", "combat", [
		"FleetBattleSimulator", "ConquestSimulator", "BattleScene",
		"ConquestScene", "BattleEvent", "CombatReplay", "BattleConfig",
		"BattleContext", "AssaultMinionDefinition", "ConquestConfig",
		"RouteEngagementResolver", "CaptureDecisionOverlay",
	], [
		"scripts/simulation/fleet_battle_simulator.gd",
		"scripts/simulation/conquest_simulator.gd",
		"scripts/battle/battle_scene.gd",
		"scripts/conquest/conquest_scene.gd",
		"scripts/simulation/battle_event.gd",
		"scripts/config/combat_replay.gd",
		"scripts/config/battle_config.gd",
		"scripts/config/battle_context.gd",
		"scripts/config/assault_minion_definition.gd",
		"scripts/config/conquest_config.gd",
		"scripts/simulation/route_engagement_resolver.gd",
		"scripts/ui/capture_decision_overlay.gd",
	], [
		"simulate_battle", "simulate_conquest", "create",
	], "Fleet battle simulator, conquest simulator, tower-defense combat, replay"
	)

	_add_concept("technology_research", "tech", [
		"TechDomain", "TechnologyMenu", "TechnologyCatalog", "TechnologyDefinition",
		"TechResearchView", "TechResearchShipView", "TechShipBuilderView", "TechPlanetView",
	], [
		"scripts/state/domains/tech_domain.gd",
		"scripts/ui/technology_menu.gd",
		"scripts/config/technology_catalog.gd",
		"scripts/config/technology_definition.gd",
		"scripts/ui/tech_menu/tech_research_view.gd",
		"scripts/ui/tech_menu/tech_research_ship_view.gd",
		"scripts/ui/tech_menu/tech_ship_builder_view.gd",
		"scripts/ui/tech_menu/tech_planet_view.gd",
	], [
		"has_technology", "research_technology", "can_research_technology",
		"get_researched_technologies", "research_in_progress", "research_remaining",
		"has_planet_technology", "research_planet_technology", "can_research_planet_technology",
		"get_planet_technologies", "advance_research",
	], "Technology research, planet tech, prerequisites, tech UI views"
	)

	_add_concept("ui_systems", "ui", [
		"PlanetPanel", "VaultBar", "MainMenu", "PauseMenu", "MessageFeed",
		"SelectionActionTooltip", "FloatingText", "ModalCoordinator",
		"PaperDossier", "PlanetDossierView", "WorkshopView", "ParchmentTechTreeView",
		"UIThemeConfig",
	], [
		"scripts/ui/planet_panel.gd",
		"scripts/ui/vault_bar.gd",
		"scripts/ui/main_menu.gd",
		"scripts/ui/pause_menu.gd",
		"scripts/ui/message_feed.gd",
		"scripts/ui/selection_tooltip.gd",
		"scripts/ui/floating_text.gd",
		"scripts/ui/dossier/modal_coordinator.gd",
		"scripts/ui/dossier/paper_dossier.gd",
		"scripts/ui/dossier/planet_dossier_view.gd",
		"scripts/ui/dossier/workshop_view.gd",
		"scripts/ui/dossier/parchment_tech_tree_view.gd",
		"scripts/ui/ui_base_utils.gd",
		"scripts/config/ui_theme_config.gd",
	], [
		"setup", "show_panel", "hide_panel", "refresh",
	], "UI panels, vault bar, menus, tooltips, dossier views, theming"
	)

	_add_concept("scene_flow", "scenes", [
		"SceneDirector", "RunSession", "RunSaveData",
	], [
		"scripts/ui/scene_director.gd",
		"scripts/state/run_session.gd",
		"scripts/state/run_save_data.gd",
	], [
		"goto_scene", "snapshot_run", "restore_run", "session",
		"request_new_run", "reconnect_world", "has_active_run",
		"pending_chunk_data", "consume_pending_chunk_data",
		"pending_timers", "consume_pending_timers",
	], "Scene director, save/load, run sessions, context handover"
	)

	_add_concept("events_signals", "events", [], [
	], [
		"push", "log_silent",
	], "Event log, toast messages, silent logging"
	)

	_add_concept("testing_quality", "preflight", [
		"PreflightContext", "PreflightFixture",
		"MechanicRegistry", "ScenarioLoader", "ScenarioSnapshot",
	], [
		"scripts/preflight/preflight_context.gd",
		"scripts/preflight/preflight_fixture.gd",
		"scripts/testing/mechanic_registry.gd",
		"scripts/testing/scenario_loader.gd",
		"scripts/testing/scenario_snapshot.gd",
	], [
		"constraint_name", "run", "boot_default", "cleanup",
		"check", "assert_eq", "assert_true",
	], "Preflight test suite, constraints, fixtures, scenario loading, mechanic coverage"
	)

	_add_concept("cpu_ai", "ai", [
		"CpuDispatchConfig", "CpuDispatchAI",
	], [
		"scripts/config/cpu_dispatch_config.gd",
		"scripts/objects/planets/cpu_dispatch_ai.gd",
	], [
		"set_enabled", "is_enabled",
	], "CPU opponent dispatch AI, automation config"
	)

	_add_concept("missions", "missions", [
	], [
	], [
		"get_research_missions", "queue_research_mission", "cancel_research_mission",
		"get_research_ship_records", "advance_research_ship_tasks",
	], "Scout, collect, research missions, gather missions"
	)

	_add_concept("persistent_ships", "ships", [
		"TechResearchShipView",
	], [
		"scripts/ui/tech_menu/tech_research_ship_view.gd",
	], [
		"register_persistent_fleet", "get_persistent_ship_records",
		"mark_persistent_ship_arrived", "mark_persistent_ship_lost",
		"get_persistent_ship",
	], "Persistent/research ships, long-range dispatch, fleet tracking"
	)

	_add_concept("background_visuals", "background", [
		"StarfieldBackground", "MapCamera", "BackgroundConfig", "BackgroundNebulaDefinition",
		"PaperStyleConfig", "MeteorConfig",
	], [
		"scripts/backgrounds/starfield_background.gd",
		"scripts/backgrounds/map_camera.gd",
		"scripts/config/background_config.gd",
		"scripts/config/background_nebula_definition.gd",
		"scripts/config/paper_style_config.gd",
		"scripts/config/meteor_config.gd",
	], [
		"_draw_background", "_draw_stars", "_draw_nebulae",
	], "Starfield background, nebulas, meteors, paper style, map camera"
	)

	_add_concept("selection_input", "input", [
		"SelectionService", "MapCamera",
	], [
		"scripts/objects/selection_service.gd",
		"scripts/backgrounds/map_camera.gd",
	], [
		"select_planet", "selected_planet", "deselect",
	], "Planet selection, camera controls, input handling, context menus"
	)

	_add_concept("faction_domain", "factions", [
		"FactionDomain",
	], [
		"scripts/state/domains/faction_domain.gd",
	], [
		"set_faction", "register_planet", "register_homeworld",
		"discover_planet", "scan_planet", "is_known", "has_scanned_planet",
		"known_planets_of", "mark_milestone", "has_milestone", "get_milestones",
	], "Faction ownership, discovery, scanning intel, milestones"
	)

	_add_concept("ship_domain", "ships", [
		"ShipDomain",
	], [
		"scripts/state/domains/ship_domain.gd",
	], [
		"get_ship_part_inventory", "get_ship_part_count", "add_ship_part",
		"spend_ship_part", "can_buy_ship_part", "buy_ship_part",
		"get_ship_assemblies", "has_ship_assembly", "get_ship_assembly",
		"can_assemble_ship", "assemble_ship", "disassemble_ship", "launch_ship",
		"get_ship_build_jobs", "ship_build_in_progress", "ship_build_remaining",
		"create_fleet_from_planet", "preview_fleet_from_planet",
		"disband_fleet_to_planet", "reconcile_defender_fleet",
	], "Ship domain: part inventory, assembly, fleet creation, build jobs"
	)


func _add_concept(
	concept: String, domain: String, classes: Array, files: Array,
	methods: Array, description: String
) -> void:
	var entry := ConceptEntry.new()
	entry.concept = concept
	entry.domain = domain
	entry.classes = classes.duplicate()
	entry.files = files.duplicate()
	entry.methods = methods.duplicate()
	entry.description = description
	_concepts[concept] = entry
	for cls_name in classes:
		_class_to_concept[cls_name] = concept


func _hit_exists(hits: Array[Dictionary], entry: ConceptEntry) -> bool:
	for hit in hits:
		if (hit["entry"] as ConceptEntry) == entry:
			return true
	return false
