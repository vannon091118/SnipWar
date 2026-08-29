@tool
class_name WorldBootstrap
extends Node2D

## World-scene bootstrap (root of scenes/world/world.tscn).
##
## Owns everything the strategy overworld needs to start: scenario selection,
## layout-seed finalization, catalog generation and GameState configuration.
## It preserves the historical ordering contract (scenario -> seed -> catalog
## -> GameState -> PlanetField/MeteorField) that the old StarfieldBackground
## used to perform, so determinism tests keep passing unchanged.
##
## The Background renderer child is a pure visual component and no longer
## touches GameState, catalogs or scenarios.

const DEFAULT_WORLD_CONFIG: WorldConfig = preload("res://resources/config/world_default.tres")
const DEFAULT_BACKGROUND_CONFIG: BackgroundConfig = preload("res://resources/config/background_default.tres")
const DEFAULT_SCENARIO_CATALOG: ScenarioCatalog = preload("res://resources/config/scenario_catalog.tres")
const ASSET_LIBRARY_SCRIPT: Script = preload("res://scripts/config/asset_library.gd")

@export var world_config: WorldConfig = DEFAULT_WORLD_CONFIG
@export var background_config: BackgroundConfig = DEFAULT_BACKGROUND_CONFIG
@export var scenario_catalog: ScenarioCatalog = DEFAULT_SCENARIO_CATALOG
@export var active_scenario_id: StringName = &""

var active_scenario: ScenarioDefinition
# The catalog the world actually runs on — generated from the world's
# building-block pool under the finalized layout seed. GameState, the
# PlanetField and the resource deal must all share this single catalog.
var active_catalog: PlanetCatalog
# Finalized per-run layout seed (authored seed for fixed scenarios, random for
# randomized ones). Finalized in _enter_tree so the generated catalog and the
# planet layout share one deterministic seed before either is built.
var active_layout_seed: int = 0

func _enter_tree() -> void:
	_apply_active_scenario()

func _ready() -> void:
	_disable_collision_debug_overlay()
	_apply_pending_timers()
	_apply_historical_handoff()

func _apply_active_scenario() -> void:
	var state: Node = get_node_or_null("/root/GameState")
	var reconnect: bool = state != null and state.has_active_run() and state.consume_world_reconnect_request()
	var catalog: ScenarioCatalog = scenario_catalog if scenario_catalog != null else DEFAULT_SCENARIO_CATALOG
	var requested_scenario_id: StringName = active_scenario_id
	if reconnect and state != null:
		var saved_context: Dictionary = state.world_session_context()
		var saved_scenario_id: StringName = StringName(saved_context.get("scenario_id", &""))
		if not String(saved_scenario_id).is_empty():
			requested_scenario_id = saved_scenario_id
	var scenario: ScenarioDefinition = catalog.resolve(requested_scenario_id)
	if scenario == null or scenario.map_definition == null:
		return
	active_scenario = scenario
	active_scenario_id = scenario.id
	var map: MapDefinition = scenario.map_definition
	var runtime_world: WorldConfig = WorldGenerator.resolve_runtime_world(map.world_config, null)
	if runtime_world != null:
		runtime_world.route_mode = scenario.resolved_route_mode()
		var discovered_assets: Dictionary = ASSET_LIBRARY_SCRIPT.scan_composition_assets()
		runtime_world.composition_base_textures = discovered_assets.get("base_textures", []) as Array[Texture2D]
		runtime_world.composition_decal_pool = discovered_assets.get("decal_textures", []) as Array[Texture2D]
	world_config = runtime_world if runtime_world != null else (map.world_config if map.world_config != null else world_config)
	background_config = scenario.background_config if scenario.background_config != null else background_config
	if reconnect and state != null:
		var session: Dictionary = state.world_session_context()
		active_layout_seed = int(session.get("layout_seed", runtime_world.layout_seed if runtime_world != null else 0))
		if runtime_world != null:
			runtime_world.layout_seed = active_layout_seed
	else:
		_finalize_layout_seed(scenario, runtime_world)
	var live_world: WorldConfig = runtime_world if runtime_world != null else map.world_config
	if live_world != null and live_world.is_infinite_world():
		# Infinite worlds use one generated definition as the chunk template; the
		# coordinator owns all live planet instantiation and identity creation.
		active_catalog = WorldGenerator.generate_catalog(live_world, active_layout_seed, 1)
	else:
		active_catalog = WorldGenerator.generate_catalog(
			live_world,
			active_layout_seed,
			WorldGenerator.target_planet_count(live_world, null)
		)

	_configure_background_renderer()
	_configure_game_state(map, reconnect)
	_configure_planet_field(map, scenario, runtime_world)
	_configure_meteor_field(map, scenario, runtime_world)

## Pushes the resolved runtime config into the pure visual Background child so
## its star generation and overlays match the active world.
func _configure_background_renderer() -> void:
	var background: Node = get_node_or_null("Background")
	if background == null:
		return
	background.set("world_config", world_config)
	background.set("background_config", background_config)

# Drops the runtime duplicate onto the planet field/navigation so that the
# authored .tres is never written into. The duplicate carries the growth
# contract (sqrt-scaled design_size, scaled target_planet_count, auto-columns).
func _configure_planet_field(map: MapDefinition, scenario: ScenarioDefinition, runtime_world: WorldConfig) -> void:
	var field: SeededLayout = get_node_or_null("PlanetField") as SeededLayout
	if field == null or map == null or scenario == null:
		return
	field.position = Vector2.ZERO
	field.world_config = runtime_world if runtime_world != null else map.world_config
	field.planet_catalog = active_catalog
	field.size_profiles = map.size_profiles
	var navigation: NavigationField = field.get_node_or_null("NavigationField") as NavigationField
	if navigation != null:
		navigation.world_config = runtime_world if runtime_world != null else map.world_config
		navigation.navigation_config = map.navigation_config
	var network: Node = field.get_node_or_null("PlanetNetwork")
	if network != null:
		network.set("transit_config", scenario.transit_config)
		network.set("ui_theme_config", scenario.ui_theme_config)
	var worker_manager: Node = field.get_node_or_null("WorkerManager")
	if worker_manager != null:
		worker_manager.set("transit_config", scenario.transit_config)

func _configure_game_state(map: MapDefinition, reconnect: bool = false) -> void:
	var state: Node = get_node_or_null("/root/GameState")
	if state == null or map == null:
		return
	var live_world: WorldConfig = world_config
	if reconnect and state.has_method("reconnect_world"):
		state.reconnect_world(active_scenario_id, active_layout_seed, live_world != null and live_world.is_infinite_world())
		return
	if state.has_method("begin_new_game"):
		state.begin_new_game(
			active_catalog,
			active_scenario_id,
			active_layout_seed,
			live_world != null and live_world.is_infinite_world()
		)
	elif live_world != null and live_world.is_infinite_world():
		state.reset_for_infinite_world()
	elif active_catalog != null:
		state.reset_from_catalog(active_catalog)

func _configure_meteor_field(map: MapDefinition, scenario: ScenarioDefinition, runtime_world: WorldConfig = null) -> void:
	var meteor_field: Node2D = get_node_or_null("MeteorField") as Node2D
	if meteor_field != null and map != null and scenario != null:
		meteor_field.position = Vector2.ZERO
		meteor_field.set("world_config", runtime_world if runtime_world != null else map.world_config)
		meteor_field.set("meteor_config", scenario.meteor_config)

func get_active_scenario() -> ScenarioDefinition:
	return active_scenario

func _finalize_layout_seed(scenario: ScenarioDefinition, runtime_world: WorldConfig) -> void:
	var base_seed: int = runtime_world.layout_seed if runtime_world != null else 0
	if scenario != null and not scenario.randomize_layout_seed:
		active_layout_seed = base_seed
	else:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		active_layout_seed = rng.randi()
	if runtime_world != null:
		runtime_world.layout_seed = active_layout_seed

func _disable_collision_debug_overlay() -> void:
	# The editor's "Visible Collision Shapes" toggle draws cyan circles around every
	# ClickArea. Force it off in the running game so faction rings stay readable.
	var tree := get_tree()
	if tree != null:
		tree.set("debug_collisions_hint", false)

# --- Delegation to the pure visual Background renderer child ---

func set_visible_region(region: Rect2) -> void:
	var background: Node = get_node_or_null("Background")
	if background != null and background.has_method("set_visible_region"):
		background.call("set_visible_region", region)

func get_visible_region() -> Rect2:
	var background: Node = get_node_or_null("Background")
	if background != null and background.has_method("get_visible_region"):
		return background.call("get_visible_region")
	return Rect2(Vector2.ZERO, Vector2(960, 540))

func get_render_batch_stats() -> Dictionary:
	var background: Node = get_node_or_null("Background")
	if background != null and background.has_method("get_render_batch_stats"):
		return background.call("get_render_batch_stats")
	return {}

# --- Save/Load timer handover ---

## Applies economy/gather tick offsets saved in the run after the world scene
## (and its runtime EconomyManager) has finished booting.
func _apply_pending_timers() -> void:
	var state: Node = get_node_or_null("/root/GameState")
	if state == null or not state.has_method("consume_pending_timers"):
		return
	var timers: Dictionary = state.consume_pending_timers()
	if timers.is_empty():
		return
	var economy_manager: Node = get_node_or_null("PlanetField/EconomyManager")
	if economy_manager != null and economy_manager.has_method("restore_timer_remaining"):
		economy_manager.call(
			"restore_timer_remaining",
			float(timers.get("economy_remaining", -1.0)),
			float(timers.get("gather_remaining", -1.0))
		)

## R-052: Wendet den historischen Endzustand (Jahr 0) an.
## Liest das Ownership direkt aus WorldChronicle.final_year0_ownership()
## (Snapshot-basiert) und überschreibt die Katalog-Defaults.
func _apply_historical_handoff() -> void:
	var chronicle: Node = get_node_or_null("/root/WorldChronicle")
	if chronicle == null or not chronicle.has_method("final_year0_ownership"):
		return
	var ownership: Dictionary = chronicle.final_year0_ownership()
	if ownership.is_empty():
		return
	# Alle Planeten im Szenenbaum durchlaufen und Ownership anwenden.
	var planet_field: Node = get_node_or_null("PlanetField")
	if planet_field == null:
		return
	var planets: Array = planet_field.get_tree().get_nodes_in_group("planets")
	for planet in planets:
		var pid: String = String(planet.get("planet_id")) if planet.has_method("get") else ""
		if pid.is_empty():
			continue
		var new_owner: StringName = ownership.get(pid, &"") as StringName
		if not String(new_owner).is_empty() and planet.has_method("set_faction"):
			planet.set_faction(new_owner)
