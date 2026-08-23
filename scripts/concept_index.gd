class_name ConceptIndex
extends RefCounted

## Conceptual code index for agent discovery. It maps domain language to the
## classes and files that implement it, while discovering class_name declarations
## from the project filesystem instead of relying on shell grep output.

class ConceptEntry extends RefCounted:
	var concept: String = ""
	var domain: String = ""
	var classes: Array[String] = []
	var files: Array[String] = []
	var methods: Array[String] = []
	var description: String = ""

	func to_dict() -> Dictionary:
		return {
			"concept": concept,
			"domain": domain,
			"classes": classes.duplicate(),
			"files": files.duplicate(),
			"methods": methods.duplicate(),
			"description": description,
		}

var _synonyms: Dictionary = {}
var _concepts: Dictionary = {}
var _class_to_concept: Dictionary = {}
var _class_to_file: Dictionary = {}

func _init() -> void:
	_collect_class_files("res://scripts")
	_build_concepts()

func search(query: String) -> Array[ConceptEntry]:
	var normalized: String = query.strip_edges().to_lower()
	var result: Array[Dictionary] = []
	if normalized.is_empty():
		return []
	# Pipe-alternation: split "a|b" → ["a", "b"], score each alternative, take best
	var alternatives: Array[String] = []
	for part in normalized.split("|"):
		var trimmed: String = part.strip_edges()
		if not trimmed.is_empty():
			alternatives.append(trimmed)
	if alternatives.is_empty():
		alternatives.append(normalized)
	for concept_value in _concepts.values():
		var entry: ConceptEntry = concept_value as ConceptEntry
		var best_score: int = 0
		for alt in alternatives:
			var score: int = _score_entry(entry, alt)
			if score > best_score:
				best_score = score
		if best_score > 0:
			result.append({"entry": entry, "score": best_score})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["score"]) == int(b["score"]):
			return String((a["entry"] as ConceptEntry).concept) < String((b["entry"] as ConceptEntry).concept)
		return int(a["score"]) > int(b["score"])
	)
	var entries: Array[ConceptEntry] = []
	for hit in result:
		entries.append(hit["entry"] as ConceptEntry)
	return entries

func expand(query: String) -> Array[ConceptEntry]:
	var matches: Array[ConceptEntry] = search(query)
	if matches.is_empty():
		return []
	var domain: String = matches[0].domain
	var result: Array[ConceptEntry] = []
	for concept_value in _concepts.values():
		var entry: ConceptEntry = concept_value as ConceptEntry
		if entry.domain == domain:
			result.append(entry)
	return result

func get_concept(name: String) -> ConceptEntry:
	return _concepts.get(name, null) as ConceptEntry

func class_concept(class_name_value: String) -> ConceptEntry:
	var concept_name: String = _class_to_concept.get(class_name_value, "") as String
	return _concepts.get(concept_name, null) as ConceptEntry

func get_all() -> Array[ConceptEntry]:
	var result: Array[ConceptEntry] = []
	for concept_value in _concepts.values():
		result.append(concept_value as ConceptEntry)
	return result

func by_domain(domain: String) -> Array[ConceptEntry]:
	var result: Array[ConceptEntry] = []
	for concept_value in _concepts.values():
		var entry: ConceptEntry = concept_value as ConceptEntry
		if entry.domain == domain:
			result.append(entry)
	return result

func domains() -> PackedStringArray:
	var result: PackedStringArray = []
	for concept_value in _concepts.values():
		var domain: String = (concept_value as ConceptEntry).domain
		if not result.has(domain):
			result.append(domain)
	return result

func stale_class_references() -> PackedStringArray:
	var result: PackedStringArray = []
	for concept_value in _concepts.values():
		var entry: ConceptEntry = concept_value as ConceptEntry
		for class_name_value in entry.classes:
			if not _class_to_file.has(class_name_value):
				result.append("%s.%s" % [entry.concept, class_name_value])
	return result

func summary() -> String:
	return "%d concepts across %d domains, %d class mappings, %d synonyms" % [_concepts.size(), domains().size(), _class_to_concept.size(), _synonyms.size()]

func get_unmapped_classes() -> Array[String]:
	var result: Array[String] = []
	var discovered: Dictionary = {}
	_collect_class_names("res://scripts", discovered)
	for class_name_value in discovered:
		if not _class_to_concept.has(class_name_value):
			result.append(class_name_value)
	return result

func get_concepts_with_free_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for concept_value in _concepts.values():
		var entry: ConceptEntry = concept_value as ConceptEntry
		var mapped: int = 0
		for cls in entry.classes:
			if _class_to_file.has(cls):
				mapped += 1
		if mapped < entry.classes.size():
			result.append({
				"concept": entry.concept,
				"domain": entry.domain,
				"mapped": mapped,
				"total": entry.classes.size(),
				"missing": entry.classes.size() - mapped,
				"classes": entry.classes,
				"files": entry.files,
				"methods": entry.methods,
				"description": entry.description
			})
	return result

func _collect_class_names(path: String, result: Dictionary) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var entry: String = directory.get_next()
		if entry.is_empty():
			break
		if entry.begins_with("."):
			continue
		var child_path: String = path.path_join(entry)
		if directory.current_is_dir():
			_collect_class_names(child_path, result)
		elif entry.ends_with(".gd"):
			_scan_class_name(child_path, result)
	directory.list_dir_end()

func _scan_class_name(path: String, result: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.begins_with("class_name "):
			var class_name_value: String = line.substr("class_name ".length()).strip_edges()
			if not class_name_value.is_empty():
				result[class_name_value] = path
			break
	file.close()

func _score_entry(entry: ConceptEntry, query: String) -> int:
	if _synonyms.get(query, "") == entry.concept:
		return 100
	if entry.concept.to_lower().contains(query):
		return 80
	for class_name_value in entry.classes:
		if class_name_value.to_lower().contains(query):
			return 70
	for method_name in entry.methods:
		if method_name.to_lower().contains(query):
			return 55
	if entry.description.to_lower().contains(query):
		return 50
	for file_path in entry.files:
		if file_path.to_lower().contains(query):
			return 30
	return 0

func _collect_class_files(path: String) -> void:
	var directory: DirAccess = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	while true:
		var file_name: String = directory.get_next()
		if file_name.is_empty():
			break
		if file_name.begins_with("."):
			continue
		var child_path: String = path.path_join(file_name)
		if directory.current_is_dir():
			_collect_class_files(child_path)
		elif file_name.ends_with(".gd"):
			_scan_class_file(child_path)
	directory.list_dir_end()

func _scan_class_file(path: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	while not file.eof_reached():
		var line: String = file.get_line().strip_edges()
		if line.begins_with("class_name "):
			var class_name_value: String = line.substr("class_name ".length()).strip_edges()
			if not class_name_value.is_empty():
				_class_to_file[class_name_value] = path
			break
	file.close()

func _build_concepts() -> void:
	_add_concept("fleet_management", "ships", ["ShipBase", "ShipManager", "ShipAssembly", "FleetSnapshot", "FleetOverview", "ShipPartCatalog", "ShipPartDefinition", "ShipBlueprint", "ShipComponentVariant", "ShipConfig", "ShipyardHangar", "CompositeShipView", "AssaultMinionDefinition", "Dispatch"], ["assemble_ship", "disassemble_ship", "launch_ship", "create_fleet_from_planet", "dispatch_ship"], "Ships, fleets, assembly, dispatch and ship parts", ["fleet", "flotte", "ship", "schiff", "vessel", "armada", "shipyard", "hangar"])
	_add_concept("economy_resources", "economy", ["EconomyDomain", "EconomyConfig", "EconomyWindow", "ResourcePool", "GameResource", "BuildingCatalog", "PlanetUpgradeCatalog", "BuildingDefinition", "ClusterTierDefinition", "PlanetEconomyManager"], ["add_faction_resource", "spend_faction_resource", "get_faction_resource", "purchase_upgrade", "place_planet_building", "get_local_resource"], "Vaults, resources, upgrades, buildings and trade", ["economy", "ökonomie", "resource", "ressource", "money", "geld", "credit", "vault", "upgrade", "building", "trade", "handel"])
	_add_concept("workers_transit", "transit", ["WorkerCluster", "FlightTime", "TransitConfig", "TransitRecord", "CpuLoadoutBuilder"], ["begin_worker_transport", "update_worker_transport", "complete_worker_transport", "get_worker_transport_records"], "Worker transit, cluster packing and flight time", ["worker", "arbeiter", "transport", "transit", "cluster", "flight", "flug", "flight time"])
	_add_concept("navigation_world", "navigation", ["NavigationField", "NavigationWaypoint", "NavigationConfig", "NavigationWaypointDefinition", "NavigationWaypointCatalog"], ["find_route", "get_neighbors", "build_graph"], "Routes, waypoints and navigation graph", ["navigation", "routing", "route", "pfad", "waypoint", "graph", "neighbor", "nachbar"])
	_add_concept("world_generation", "world", ["WorldConfig", "WorldGenerator", "WorldBootstrap", "SeededLayout", "ChunkCoordinator", "PlanetCatalog", "PlanetDefinition", "SectorClassifier", "SectorAnchor", "SectorFlavor", "SectorFlavorCatalog", "ScenarioCatalog", "ScenarioDefinition", "MapDefinition", "BackgroundConfig", "BackgroundNebulaDefinition", "AssetLibrary", "ConceptIndex"], ["generate_catalog", "set_layout_seed", "reset_for_infinite_world", "resolved_target_planet_count", "is_infinite_world"], "Seeded world generation, catalogs, chunks and sectors", ["world", "welt", "layout", "seed", "catalog", "katalog", "chunk", "infinite", "unendlich", "sector", "generator"])
	_add_concept("planets", "planets", ["Planet", "PlanetNetwork", "PlanetNetworkUI", "PlanetGrid", "PlanetProcedural", "PlanetArrivalResolver", "SelectionService", "ContextMenuBuilder", "PlanetDetails", "PlanetDetailOrbit", "PlanetTraitAggregator", "PlanetView", "PlanetDetailDefinition", "PlanetDetailFidelity", "PlanetDetailProfile", "PlanetGridCell", "PlanetGridConfig", "PlanetSizeProfile", "PlanetUpgradeDefinition", "PlanetUpgradeCatalog", "MeteorConfig"], ["register_planet", "set_faction", "homeworld_for", "discover_planet", "scan_planet", "known_planets_of"], "Planet lifecycle, ownership, discovery and planet UI", ["planet", "planetoid", "homeworld", "heimwelt", "faction", "fraktion", "scan", "discover", "discovery", "capture"])
	_add_concept("combat_battle", "combat", ["FleetBattleSimulator", "ConquestSimulator", "BattleScene", "ConquestScene", "CombatReplay", "BattleContext", "BattleEvent", "BattleConfig", "ConquestConfig", "RouteEngagementResolver", "CaptureDecisionOverlay", "EffectDefinition", "ModuleInfluence", "TraitDefinition", "TransformerConfig", "PaperStyleConfig"], ["simulate_battle", "simulate_conquest", "set_pending_battle_context"], "Fleet combat, conquest and replays", ["combat", "kampf", "battle", "schlacht", "conquest", "replay", "simulator", "conflict"])
	_add_concept("technology_research", "tech", ["TechDomain", "TechnologyMenu", "TechnologyCatalog", "TechnologyDefinition", "TechResearchView", "TechShipBuilderView", "TechPlanetView", "TechResearchShipView", "ParchmentTechTreeView", "WorkshopView", "PlanetDossierView"], ["has_technology", "research_technology", "can_research_technology", "advance_research"], "Technology research, prerequisites and tech UI", ["technology", "technologie", "tech", "research", "forschung", "prerequisite", "voraussetzung", "trait"])
	_add_concept("ui_systems", "ui", ["PlanetPanel", "VaultBar", "MainMenu", "PauseMenu", "MessageFeed", "ModalCoordinator", "PaperDossier", "UIThemeConfig", "FloatingText", "IngamePlayerControls", "ModuleHpBar", "SelectionActionTooltip", "UIBaseUtils", "CaptureDecisionOverlay", "EconomyWindow", "FleetOverview"], ["setup", "show_panel", "hide_panel", "refresh"], "Menus, panels, overlays, messages and theming", ["menu", "panel", "button", "overlay", "tooltip", "toast", "dossier", "pause", "theme"])
	_add_concept("scene_flow", "scenes", ["SceneDirector", "RunSession", "RunSaveData", "ChunkSaveData"], ["goto_scene", "snapshot_run", "restore_run", "request_new_run", "reconnect_world"], "Scene transitions, sessions and save/load", ["scene", "szene", "director", "transition", "wechsel", "save", "load", "speichern", "laden", "snapshot", "session"])
	_add_concept("testing_quality", "preflight", ["PreflightContext", "PreflightFixture", "MechanicRegistry", "ScenarioLoader", "ScenarioSnapshot", "PreflightConstraintCameraAndInput", "PreflightConstraintChunkExpansion", "PreflightConstraintColonyMilestone", "PreflightConstraintConceptIndex", "PreflightConstraintConquestGridCombat", "PreflightConstraintContextHandover", "PreflightConstraintCpuDispatch", "PreflightConstraintEconomyProduction", "PreflightConstraintEffectsAndTraits", "PreflightConstraintEventLog", "PreflightConstraintFlightAndDispatch", "PreflightConstraintGameStateCompatibility", "PreflightConstraintGridSystem", "PreflightConstraintIngamePlayerAndTransitions", "PreflightConstraintLayers2And3", "PreflightConstraintLocalResources", "PreflightConstraintMainMenuAndFlow", "PreflightConstraintMechanicCoverage", "PreflightConstraintMissionSemantics", "PreflightConstraintModuleDamageModel", "PreflightConstraintNavigationGrowth", "PreflightConstraintPaperStyle", "PreflightConstraintPauseAndContext", "PreflightConstraintResearchShip", "PreflightConstraintResourcesAndSeed", "PreflightConstraintSaveGameRoundtrip", "PreflightConstraintSaveGameSlots", "PreflightConstraintSceneBoot", "PreflightConstraintSectorClassification", "PreflightConstraintSelectionAndContext", "PreflightConstraintShipCatalogAndAssembly", "PreflightConstraintShipTransitAndArrival", "PreflightConstraintUpgradeCatalog", "PreflightConstraintWorldDetailsAndScale", "PreflightConstraintWorldGeneratorScaling", "PreflightConstraintWorldPlanetsAndDispatch"], ["constraint_name", "run", "boot_default", "check"], "Preflight constraints, fixtures and scenario coverage", ["preflight", "constraint", "test", "fixture", "scenario", "mechanic", "coverage"])
	_add_concept("cpu_ai", "ai", ["CpuDispatchConfig", "CpuDispatchAI"], ["set_enabled", "is_enabled"], "CPU dispatch AI and automation", ["cpu", "ai", "opponent", "gegner", "autopilot"])
	_add_concept("missions", "missions", ["TechResearchShipView", "GameStateAccess", "PathUtils"], ["get_research_missions", "queue_research_mission", "get_research_ship_records"], "Scout, collect and research missions", ["mission", "auftrag", "scout", "collect", "research mission"])
	_add_concept("background_visuals", "background", ["StarfieldBackground", "MapCamera", "MeteorConfig", "BackgroundConfig", "BackgroundNebulaDefinition"], ["_draw_background", "_draw_stars", "_draw_nebulae"], "Starfield, meteors, fog and camera visuals", ["background", "hintergrund", "starfield", "meteor", "fog", "camera", "zoom", "pan"])
	_add_concept("events_signals", "events", [], ["push", "log_silent"], "Event log, toast messages and signals", ["event", "eventlog", "log", "signal", "message"])
	_add_concept("selection_input", "input", ["SelectionService", "MapCamera", "ContextMenuBuilder"], ["select_planet", "selected_planet", "deselect"], "Selection and input handling", ["select", "selekt", "click", "klick", "input", "context menu", "rechtsklick"])
	_add_concept("faction_domain", "factions", ["FactionDomain"], ["set_faction", "discover_planet", "scan_planet", "is_known", "has_scanned_planet"], "Faction ownership and discovery state", ["ownership", "besitz", "faction", "fraktion"])
	_add_concept("ship_domain", "ships", ["ShipDomain"], ["get_ship_part_inventory", "assemble_ship", "disassemble_ship", "launch_ship"], "Ship domain inventory and fleet state", ["ship domain", "assembly", "blueprint"])
	_add_concept("game_state_access", "state", ["GameStateAccess"], ["get_game_state", "get_state"], "GameState facade access helper", ["state", "facade", "access", "gamestate"])
	_add_concept("mcp_remote_testing", "mcp", ["McpToolRegistry", "McpRuntimeTools", "McpInputScheduler", "McpVision", "McpVisionCapture", "McpVisionColor", "McpVisionCompare", "McpVisionDetect", "McpVisionHelpers", "McpUxPipeline", "McpUxLive", "McpUxText", "McpUxGeometry", "McpUxDetect", "McpUxClassify", "McpDebug", "McpDebugHelpers", "McpDebugPerf", "McpDebugProject", "McpDebugRuntime", "McpE2E", "McpPlaythroughTools", "McpPlaythroughArchive", "McpGoalPlayer", "McpCodeAnalyzer", "McpAudioTools", "McpCustomToolLoader", "McpContextStore", "McpLifecycle", "McpProtocol", "McpDock", "McpTestScenario"], ["dispatch_tool", "dispatch_async", "get_tool_defs", "capture_screenshot", "activate_virtual_mouse", "set_freeze", "step_one_frame", "step_frames", "play_goal", "analyze_project", "runtime_click", "runtime_key", "runtime_ux_scan"], "MCP bridge: remote testing, virtual input, vision/OCR, UX scan, freeze/step, goal-based playtesting", ["mcp", "remote test", "agent", "automation", "vision", "ocr", "virtual mouse", "freeze", "step", "playthrough", "e2e", "remote control"])

func _add_concept(concept_name: String, domain: String, class_names: Array[String], method_names: Array[String], description: String, synonyms: Array[String]) -> void:
	var entry: ConceptEntry = ConceptEntry.new()
	entry.concept = concept_name
	entry.domain = domain
	entry.methods = method_names.duplicate()
	entry.description = description
	for class_name_value in class_names:
		entry.classes.append(class_name_value)
		_class_to_concept[class_name_value] = concept_name
		if _class_to_file.has(class_name_value):
			entry.files.append(_class_to_file[class_name_value] as String)
	_concepts[concept_name] = entry
	for synonym in synonyms:
		_synonyms[synonym.to_lower()] = concept_name
