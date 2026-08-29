class_name RunPreparation
extends RefCounted

## Bereitet einen neuen Run deterministisch VOR dem Szenenwechsel vor (z. B.
## bevor die HistoricalWorld bootet), damit `run_started` → `WorldChronicle`
## bereits gefüllt ist, wenn die Szene ihre Chronik abfragt.
##
## Spiegelt den Non-Reconnect-Pfad von `WorldBootstrap._apply_active_scenario()`
## (scenario → seed → catalog → GameState) — beide Einstiege erfüllen damit
## denselben Ordnungsvertrag. `WorldBootstrap` bleibt unverändert: Er erkennt
## einen aktiven Run über `has_active_run()` + `consume_world_reconnect_request()`
## und reconnected statt ein zweites Mal `begin_new_game()` zu rufen.

const DEFAULT_SCENARIO_CATALOG: ScenarioCatalog = preload("res://resources/config/scenario_catalog.tres")
const DEFAULT_PLANET_CATALOG: PlanetCatalog = preload("res://resources/config/planet_catalog.tres")
const ASSET_LIBRARY_SCRIPT: Script = preload("res://scripts/config/asset_library.gd")

## Erzeugt einen frischen Run im GameState. Liefert bei Erfolg
## {ok: true, scenario_id, layout_seed, infinite_world}, sonst {ok: false, error}.
## `seed_override != 0` erzwingt einen deterministischen Layout-Seed (Tests/Preflight).
static func prepare_new_run(seed_override: int = 0) -> Dictionary:
	var state: Node = _game_state()
	if state == null:
		return {"ok": false, "error": "game_state_missing"}
	var catalog: ScenarioCatalog = DEFAULT_SCENARIO_CATALOG
	var scenario: ScenarioDefinition = catalog.resolve(&"")
	if scenario == null or scenario.map_definition == null:
		return {"ok": false, "error": "scenario_unresolvable"}
	var map: MapDefinition = scenario.map_definition
	var runtime_world: WorldConfig = WorldGenerator.resolve_runtime_world(map.world_config, null)
	if runtime_world == null:
		return {"ok": false, "error": "world_config_unresolvable"}
	runtime_world.route_mode = scenario.resolved_route_mode()
	var discovered_assets: Dictionary = ASSET_LIBRARY_SCRIPT.scan_composition_assets()
	runtime_world.composition_base_textures = discovered_assets.get("base_textures", []) as Array[Texture2D]
	runtime_world.composition_decal_pool = discovered_assets.get("decal_textures", []) as Array[Texture2D]
	var layout_seed: int = _finalize_layout_seed(scenario, runtime_world, seed_override)
	var infinite_world: bool = runtime_world.is_infinite_world()
	var target_count: int = 1 if infinite_world else WorldGenerator.target_planet_count(runtime_world, null)
	var active_catalog: PlanetCatalog = WorldGenerator.generate_catalog(runtime_world, layout_seed, target_count)
	var roster: Array[Dictionary] = []
	if infinite_world:
		roster = StartRosterGenerator.generate(layout_seed, runtime_world.start_roster_count, runtime_world, active_catalog)
	if state.has_method("prepare_start_roster"):
		state.prepare_start_roster(roster)
	state.begin_new_game(active_catalog, scenario.id, layout_seed, infinite_world)
	return {
		"ok": true,
		"scenario_id": scenario.id,
		"layout_seed": layout_seed,
		"infinite_world": infinite_world,
	}


static func _finalize_layout_seed(scenario: ScenarioDefinition, runtime_world: WorldConfig, seed_override: int) -> int:
	if seed_override != 0:
		runtime_world.layout_seed = seed_override
		return seed_override
	var base_seed: int = runtime_world.layout_seed
	if scenario != null and not scenario.randomize_layout_seed:
		runtime_world.layout_seed = base_seed
		return base_seed
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var randomized_seed: int = rng.randi()
	runtime_world.layout_seed = randomized_seed
	return randomized_seed


static func _game_state() -> Node:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop == null:
		return null
	var tree: SceneTree = main_loop as SceneTree
	if tree == null or tree.get_root() == null:
		return null
	return tree.get_root().get_node_or_null("GameState")