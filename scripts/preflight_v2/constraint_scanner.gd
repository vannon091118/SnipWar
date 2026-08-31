extends RefCounted

## Scans the preflight/ directory for constraint scripts and builds a
## registry dynamically.  No manual CONSTRAINT_REGISTRY array needed.
##
## Canonical impact metadata lives HERE (single source of truth):
##   _CONTRACT_CONSTRAINTS  contract id → [constraint ids covered]
##   _PATH_CONTRACTS        path glob        → [contract ids]
## The ChangeImpactResolver consumes scan() entries and resolves a changed
## file to its contracts, then to the full (transitive) constraint closure.
## A path with no mapping is UNRESOLVED by design — it fails closed instead
## of silently under-scoping.

const CONSTRAINT_DIR := "res://scripts/preflight"

const AUTO_MANAGED: Array = ["CHANGELOG.md", "change_index.json", "narrative_chain.json", "arcs.json", ".commit_msg.txt"]

## Canonical contract → constraint coverage (transitive closure).
## Every constraint discovered by the scanner MUST appear in exactly one
## contract; the resolver unions these to build the required scope.
var _CONTRACT_CONSTRAINTS: Dictionary = {
	"game_state": ["game_state_compatibility"],
	"save": ["save_game_roundtrip", "save_game_slots"],
	"history": ["historical_world", "event_log"],
	"ships": ["ship_catalog_and_assembly", "ship_transit_and_arrival", "research_ship", "module_damage_model", "effects_and_traits"],
	"economy": ["economy_production", "local_resources", "resources_and_seed", "upgrade_catalog", "mission_semantics"],
	"navigation": ["navigation_growth"],
	"fleet": ["flight_and_dispatch", "cpu_dispatch", "conquest_grid_combat", "layers_2_and_3"],
	"world": ["world_generator_scaling", "world_details_and_scale", "world_planets_and_dispatch", "chunk_expansion", "cluster_generation", "grid_system"],
	"sectors": ["sector_classification"],
	"combat": ["module_damage_model", "conquest_grid_combat", "layers_2_and_3", "mission_semantics"],
	"ui_flow": ["main_menu_and_flow", "pause_and_context", "ingame_player_and_transitions", "selection_and_context", "camera_and_input", "scene_boot", "paper_style", "layer_independence", "context_handover", "colony_milestone"],
	"preflight": ["agent_activity", "concept_index", "global_search", "mechanic_coverage", "dead_code", "mcp_capture_contract"],
	"doki": ["narrative_runtime", "docs_integrity"],
	"docs": ["docs_integrity", "global_search"],
	"mcp": ["mcp_capture_contract", "concept_index", "global_search"],
}

## Canonical changed-path glob → affected contract(s). Deterministic prefixes
## over the real repository layout. Unmapped paths are left UNRESOLVED so the
## resolver fails closed (no silent under-scope).
var _PATH_CONTRACTS: Array = [
	{"glob": "scripts/state/game_state.gd", "contracts": ["game_state", "save"]},
	{"glob": "scripts/state/domains/**", "contracts": ["game_state", "economy"]},
	{"glob": "scripts/state/save_game_service.gd", "contracts": ["save"]},
	{"glob": "scripts/state/run_save_data.gd", "contracts": ["save"]},
	{"glob": "scripts/state/run_session.gd", "contracts": ["save", "ui_flow"]},
	{"glob": "scripts/state/chunk_save_data.gd", "contracts": ["save"]},
	{"glob": "scripts/state/event_bus.gd", "contracts": ["history"]},
	{"glob": "scripts/state/event_log.gd", "contracts": ["history"]},
	{"glob": "scripts/history/**", "contracts": ["history"]},
	{"glob": "scripts/ui/history/**", "contracts": ["history"]},
	{"glob": "resources/config/**", "contracts": ["economy", "ships", "docs"]},
	{"glob": "scripts/agent_activity.sh", "contracts": ["preflight"]},
	{"glob": "scripts/backgrounds/**", "contracts": ["ui_flow"]},
	{"glob": "scripts/config/ship_*", "contracts": ["ships"]},
	{"glob": "scripts/config/fleet_snapshot.gd", "contracts": ["fleet"]},
	{"glob": "scripts/objects/ships/**", "contracts": ["ships", "fleet"]},
	{"glob": "scripts/objects/workers/**", "contracts": ["ships"]},
	{"glob": "scripts/config/economy_config.gd", "contracts": ["economy"]},
	{"glob": "scripts/config/resource_pool*", "contracts": ["economy"]},
	{"glob": "scripts/config/*upgrade*", "contracts": ["economy", "ships"]},
	{"glob": "scripts/config/effect_*", "contracts": ["ships", "economy"]},
	{"glob": "scripts/config/module_*", "contracts": ["combat"]},
	{"glob": "scripts/config/assault_*", "contracts": ["combat"]},
	{"glob": "scripts/config/navigation_*", "contracts": ["navigation"]},
	{"glob": "scripts/config/cpu_*", "contracts": ["fleet"]},
	{"glob": "scripts/config/*dispatch*", "contracts": ["fleet"]},
	{"glob": "scripts/config/world_*", "contracts": ["world"]},
	{"glob": "scripts/config/asset_library.gd", "contracts": ["docs", "ui_flow"]},
	{"glob": "scripts/config/cluster_*", "contracts": ["world", "sectors"]},
	{"glob": "scripts/config/sector_*", "contracts": ["sectors"]},
	{"glob": "scripts/config/planet_*", "contracts": ["world"]},
	{"glob": "scripts/config/paper_style*", "contracts": ["ui_flow"]},
	{"glob": "scripts/bootstrap/**", "contracts": ["world", "game_state"]},
	{"glob": "scripts/state/playback_controller.gd", "contracts": ["history", "ui_flow"]},
	{"glob": "scripts/objects/planets/**", "contracts": ["world", "economy", "navigation"]},
	{"glob": "scripts/objects/conflict_manager.gd", "contracts": ["combat", "fleet"]},
	{"glob": "scripts/objects/meteors/**", "contracts": ["world"]},
	{"glob": "scripts/battle/**", "contracts": ["combat", "mcp"]},
	{"glob": "scripts/conquest/**", "contracts": ["combat", "fleet"]},
	{"glob": "scripts/simulation/**", "contracts": ["combat"]},
	{"glob": "scenes/main_menu/**", "contracts": ["ui_flow"]},
	{"glob": "scenes/ui/**", "contracts": ["ui_flow"]},
	{"glob": "scenes/objects/**", "contracts": ["ui_flow", "ships"]},
	{"glob": "scenes/battle/**", "contracts": ["combat", "mcp"]},
	{"glob": "scenes/conquest/**", "contracts": ["combat"]},
	{"glob": "scenes/world/**", "contracts": ["world", "ui_flow"]},
	{"glob": "scenes/historical_world/**", "contracts": ["history", "ui_flow"]},
	{"glob": "scripts/ui/**", "contracts": ["ui_flow", "history"]},
	{"glob": "scripts/ui/dossier/**", "contracts": ["ships", "economy"]},
	{"glob": "scripts/ui/tech_menu/**", "contracts": ["ships", "economy"]},
	{"glob": "scripts/concept_index.gd", "contracts": ["preflight"]},
	{"glob": "scripts/global_search.gd", "contracts": ["preflight", "docs"]},
	{"glob": "scripts/testing/mechanic_registry.gd", "contracts": ["preflight"]},
	{"glob": "scripts/preflight/**", "contracts": ["preflight"]},
	{"glob": "scripts/preflight_v2/**", "contracts": ["preflight"]},
	{"glob": "scripts/testing/**", "contracts": ["preflight"]},
	{"glob": "scripts/tools/**", "contracts": ["preflight"]},
	{"glob": ".githooks/**", "contracts": ["preflight"]},
	{"glob": ".gitmodules", "contracts": ["preflight"]},
	{"glob": "scripts/doki/**", "contracts": ["doki"]},
	{"glob": "narrative_runtime/**", "contracts": ["doki"]},
	{"glob": "narrative_chain.json", "contracts": ["doki"]},
	{"glob": "change_index.json", "contracts": ["doki"]},
	{"glob": "arcs.json", "contracts": ["doki"]},
	{"glob": "addons/gdscript_mcp/**", "contracts": ["mcp"]},
	{"glob": "docs/**", "contracts": ["docs"]},
	{"glob": "*.md", "contracts": ["docs"]},
	{"glob": "*.json", "contracts": ["docs", "doki"]},
	{"glob": "project.godot", "contracts": ["ui_flow", "game_state"]},
	{"glob": "icon.svg", "contracts": ["ui_flow"]},
	{"glob": "plan/**", "contracts": ["docs"]},
	{"glob": "assets/**", "contracts": ["docs", "ui_flow"]},
	{"glob": "ROADMAP.md", "contracts": ["docs"]},
	{"glob": "AGENTS.md", "contracts": ["docs"]},
	{"glob": ".gitignore", "contracts": ["docs", "preflight"]},
	{"glob": "**/*.uid", "contracts": ["preflight"]},
]


## Returns Array[Dictionary] — each entry has keys:
##   id, script, desc, requires_scene, contracts, is_auto_managed
func scan() -> Array[Dictionary]:
	var registry: Array[Dictionary] = []
	var dir := DirAccess.open(CONSTRAINT_DIR)
	if dir == null:
		push_error("[constraint_scanner] Cannot open directory: %s" % CONSTRAINT_DIR)
		return registry

	dir.list_dir_begin()
	while true:
		var entry: String = dir.get_next()
		if entry.is_empty():
			break
		if entry.begins_with("."):
			continue
		if not entry.begins_with("constraint_"):
			continue
		if not entry.ends_with(".gd"):
			continue

		var file_path: String = CONSTRAINT_DIR.path_join(entry)
		var script: Script = load(file_path) as Script
		if script == null:
			push_warning("[constraint_scanner] Failed to load: %s" % file_path)
			continue

		var instance: RefCounted = script.new() as RefCounted
		if instance == null:
			push_warning("[constraint_scanner] Failed to instantiate: %s" % file_path)
			continue

		# Check for required interface
		if not _has_interface(instance):
			push_warning("[constraint_scanner] No constraint_name/run interface: %s" % file_path)
			continue

		var c_id: String = String(instance.constraint_name())
		var c_desc: String = ""
		if instance.has_method("constraint_description"):
			c_desc = String(instance.constraint_description())
		# Safe default: scene required. Constraints must opt-in to pure
		# by explicitly returning false from requires_scene().
		var c_requires_scene: bool = true
		if instance.has_method("requires_scene"):
			c_requires_scene = bool(instance.requires_scene())

		registry.append({
			"id": c_id,
			"script": script,
			"desc": c_desc,
			"requires_scene": c_requires_scene,
			"contracts": contracts_for(c_id),
			"is_auto_managed": AUTO_MANAGED.has(c_id),
		})

	dir.list_dir_end()
	return registry


## Canonical contract coverage — a constraint must belong to at least one
## contract (the resolver needs the closure). Used by both scan() and the
## scope resolver's manifest validation.
func contracts_for(constraint_id: String) -> Array[String]:
	var contracts: Array[String] = []
	for contract_id in _CONTRACT_CONSTRAINTS:
		var ids: Array = _CONTRACT_CONSTRAINTS[contract_id]
		if ids.has(constraint_id) and not contracts.has(contract_id):
			contracts.append(String(contract_id))
	return contracts


## Canonical contract id → [constraint ids covered] (the full closure).
func contract_constraints(contract_id: String) -> Array[String]:
	return contract_to_id_list(_CONTRACT_CONSTRAINTS.get(contract_id, []))


## Canonical path glob → affected contract ids.
func path_contracts() -> Array:
	return _PATH_CONTRACTS


func _has_interface(instance: RefCounted) -> bool:
	return instance.has_method("constraint_name") and instance.has_method("run")


static func contract_to_id_list(source: Array) -> Array[String]:
	var out: Array[String] = []
	for item in source:
		out.append(String(item))
	return out