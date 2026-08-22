class_name PreflightFixture
extends RefCounted

## Owns the mutable runtime surface used by scene-dependent preflight constraints.
## Every boot disposes the previous background before the new one enters the tree;
## StarfieldBackground then resets the single GameState autoload from the active
## catalog. This keeps one constraint's research, upgrades, fleets, workers, and
## layout mutations from becoming another constraint's hidden prerequisites.

const BACKGROUND_SCENE: PackedScene = preload("res://scenes/backgrounds/starfield_background.tscn")
const DEFAULT_RESOURCE_POOL: ResourcePool = preload("res://resources/config/resource_pool_default.tres")
const DEFAULT_UPGRADE_CATALOG: PlanetUpgradeCatalog = preload("res://resources/config/planet_upgrade_catalog_default.tres")
const DEFAULT_TECHNOLOGY_CATALOG: TechnologyCatalog = preload("res://resources/config/technology_catalog_default.tres")

# The live default scenario intentionally randomizes its seed. Preflight uses a
# private fixed seed after Bootstrap has run so reordered constraints test the
# same graph and resource deal without changing gameplay configuration.
const PREFLIGHT_LAYOUT_SEED: int = 424242

var tree: SceneTree
var background: Node
var field: Node
var network: Node
var manager: Node
var game_state: Node
var world_config: WorldConfig
var planet_catalog: PlanetCatalog
var scenario_catalog: ScenarioCatalog
var upgrade_catalog: PlanetUpgradeCatalog
var boot_count: int = 0


func _init(p_tree: SceneTree) -> void:
	tree = p_tree


## Boots a clean default scenario and publishes its references into the shared
## PreflightContext. The returned bool includes a baseline-state regression check.
func boot_default(ctx: PreflightContext) -> bool:
	await _release_current_scene()
	if tree == null or tree.root == null:
		return false

	tree.paused = false
	background = BACKGROUND_SCENE.instantiate()
	background.set("active_scenario_id", &"default")
	tree.root.add_child(background)
	await tree.process_frame

	field = background.get_node_or_null("PlanetField")
	if field == null:
		return false
	world_config = field.get("world_config") as WorldConfig
	var scenario: ScenarioDefinition = background.get("active_scenario") as ScenarioDefinition
	if world_config == null or scenario == null or scenario.map_definition == null:
		return false

	# Bootstrap has already selected the live catalog and dealt its initial
	# resources. Replace only the randomized seed and deal again for a stable
	# fixture; the production scenario remains randomized outside preflight.
	field.call("set_layout_seed", PREFLIGHT_LAYOUT_SEED)
	await tree.process_frame
	await tree.process_frame
	planet_catalog = field.get("planet_catalog") as PlanetCatalog
	var state: Node = tree.root.get_node_or_null("GameState")
	if state == null or planet_catalog == null:
		return false
	state.call("set_jobs_auto_advance", false)
	var player_homeworld_id: StringName = state.homeworld_for(GameState.FACTION_PLAYER)
	if not String(player_homeworld_id).is_empty():
		state.call("ensure_starter_research_ship", GameState.FACTION_PLAYER, player_homeworld_id)
	if world_config == null or not world_config.is_infinite_world():
		state.call("deal_resources", planet_catalog, scenario.map_definition.resource_pool if scenario.map_definition.resource_pool != null else DEFAULT_RESOURCE_POOL, PREFLIGHT_LAYOUT_SEED)
	await tree.process_frame

	world_config = field.get("world_config") as WorldConfig
	network = field.get_node_or_null("PlanetNetwork")
	manager = field.get_node_or_null("WorkerManager")
	game_state = state
	scenario_catalog = background.get("scenario_catalog") as ScenarioCatalog
	upgrade_catalog = DEFAULT_UPGRADE_CATALOG
	_disable_runtime_automation()
	# The fixture intentionally changes the seed after the live deferred setup;
	# refresh the derived fog view once the rebuilt graph is stable.
	if network != null and network.has_method("_refresh_fog_of_war"):
		network.call("_refresh_fog_of_war")
	_apply_context(ctx)
	boot_count += 1

	var baseline_errors: PackedStringArray = _baseline_errors()
	return ctx.check(
		baseline_errors.is_empty(),
		"isolated preflight fixture did not reset mutable GameState state",
		{"errors": baseline_errors, "boot_count": boot_count} if not baseline_errors.is_empty() else {"boot_count": boot_count}
	)


## Releases the current fixture scene before the preflight process exits.
func cleanup() -> void:
	await _release_current_scene()
	if tree != null:
		tree.paused = false


## Supplies the explicit progression prerequisites used by the ship-builder
## constraint. It is deliberately part of the fixture, not an earlier constraint.
func prepare_ship_builder() -> bool:
	if game_state == null or field == null:
		return false
	var source_id: StringName = game_state.homeworld_for(GameState.FACTION_PLAYER)
	var ship_manager: Node = field.get_node_or_null("ShipManager")
	if String(source_id).is_empty() or ship_manager == null:
		return false
	_grant_player_resources(200)
	var technology_catalog: TechnologyCatalog = ship_manager.get_technology_catalog() as TechnologyCatalog if ship_manager.has_method("get_technology_catalog") else DEFAULT_TECHNOLOGY_CATALOG
	for technology_id in [&"shipyard_construction", &"scout_hull", &"scanner_drone"]:
		if game_state.has_technology(GameState.FACTION_PLAYER, technology_id):
			continue
		if not game_state.research_technology(GameState.FACTION_PLAYER, technology_id, technology_catalog):
			return false
		game_state.advance_research(999.0)
	if not game_state.has_planet_upgrade(source_id, &"shipyard"):
		if not game_state.purchase_upgrade(source_id, &"shipyard", upgrade_catalog):
			return false
	var network_node: Node = field.get_node_or_null("PlanetNetwork")
	var source: Planet = null
	for child in field.get_children():
		var candidate: Planet = child as Planet
		if candidate != null and candidate.planet_id == source_id:
			source = candidate
			break
	if network_node == null or source == null:
		return false
	for neighbor_value in network_node.call("get_neighbors", source):
		var neighbor: Planet = neighbor_value as Planet
		if neighbor == null or neighbor.get_faction() != GameState.FACTION_NEUTRAL:
			continue
		game_state.scan_planet(
			GameState.FACTION_PLAYER,
			neighbor.planet_id,
			game_state.resource_of(neighbor.planet_id),
			neighbor.get_size_profile().id,
			neighbor.get_build_slot_count()
		)
	return game_state.has_planet_upgrade(source_id, &"shipyard") and game_state.has_scanned_planet(GameState.FACTION_PLAYER)


func _grant_player_resources(amount: int) -> void:
	for resource_id in GameState.ALL_RESOURCES:
		game_state.add_faction_resource(GameState.FACTION_PLAYER, resource_id, amount)


func _disable_runtime_automation() -> void:
	if field == null:
		return
	var economy_manager: Node = field.get_node_or_null("EconomyManager")
	if economy_manager != null:
		economy_manager.call("set_enabled", false)
		economy_manager.call("set_gathering_enabled", false)
	var cpu_ai: Node = field.get_node_or_null("CpuDispatchAI")
	if cpu_ai != null:
		cpu_ai.call("set_enabled", false)


func _apply_context(ctx: PreflightContext) -> void:
	ctx.background = background
	ctx.field = field
	ctx.network = network
	ctx.manager = manager
	ctx.game_state = game_state
	ctx.world_config = world_config
	ctx.planet_catalog = planet_catalog
	ctx.scenario_catalog = scenario_catalog
	ctx.upgrade_catalog = upgrade_catalog
	ctx.original_seed = world_config.layout_seed if world_config != null else PREFLIGHT_LAYOUT_SEED
	if game_state != null and not game_state.faction_changed.is_connected(ctx.capture_faction_changed):
		game_state.faction_changed.connect(ctx.capture_faction_changed)


func _baseline_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if game_state == null or field == null or planet_catalog == null:
		errors.append("fixture references are incomplete")
		return errors
	var coordinator: Node = field.get_chunk_coordinator() if field != null and field.has_method("get_chunk_coordinator") else null
	if game_state.validate().size() != 0 or game_state.validate_starting_setup().size() != 0:
		errors.append("GameState ownership/start setup is invalid")
	if game_state.get_researched_technologies(GameState.FACTION_PLAYER).size() != 0 or game_state.get_researched_technologies(GameState.FACTION_CPU).size() != 0:
		errors.append("global technology state leaked into the fixture")
	if game_state.known_planets_of(GameState.FACTION_PLAYER).size() != 1 or game_state.known_planets_of(GameState.FACTION_CPU).size() != 1:
		errors.append("discovery state is not at the two-homeworld baseline")
	if world_config != null and world_config.is_infinite_world():
		var assigned_resources: Dictionary = game_state.resource_snapshot()
		var seen_resource_ids: Dictionary = {}
		for assigned_id in assigned_resources.values():
			seen_resource_ids[assigned_id] = true
		if assigned_resources.size() < 2 or seen_resource_ids.size() < DEFAULT_RESOURCE_POOL.resources.size():
			errors.append("infinite-world resource deal is incomplete: assigned=%d distinct=%d pool=%d" % [assigned_resources.size(), seen_resource_ids.size(), DEFAULT_RESOURCE_POOL.resources.size()])
	else:
		if game_state.resource_snapshot().size() != planet_catalog.planets.size():
			errors.append("resource deal does not cover the active catalog: resources=%d active_catalog=%d" % [game_state.resource_snapshot().size(), planet_catalog.planets.size()])
		var resource_errors: PackedStringArray = game_state.validate_resources(DEFAULT_RESOURCE_POOL)
		if not resource_errors.is_empty():
			errors.append("fixture resource deal is invalid: %s" % resource_errors)
	for child in field.get_children():
		var planet: Planet = child as Planet
		if planet == null:
			continue
		if planet.worker_count != game_state.starting_workers_of(planet.planet_id):
			errors.append("worker state leaked on %s" % planet.planet_id)
		if planet.is_worker_spawn_enabled():
			errors.append("worker automation leaked on %s" % planet.planet_id)
		if not game_state.get_planet_upgrades(planet.planet_id).is_empty():
			errors.append("upgrade state leaked on %s" % planet.planet_id)
		if not game_state.get_planet_technologies(planet.planet_id).is_empty():
			errors.append("planet technology state leaked on %s" % planet.planet_id)
		if not game_state.get_ship_part_inventory(planet.planet_id).is_empty():
			errors.append("ship-part inventory leaked on %s" % planet.planet_id)
		if not game_state.get_ship_assemblies(planet.planet_id).is_empty():
			errors.append("ship assemblies leaked on %s" % planet.planet_id)
		if not game_state.get_ship_build_jobs(planet.planet_id).is_empty():
			errors.append("ship-build jobs leaked on %s" % planet.planet_id)
	if network == null or manager == null:
		errors.append("runtime network/worker modules are missing")
	var economy_manager: Node = field.get_node_or_null("EconomyManager")
	if economy_manager != null and (economy_manager.call("is_enabled") or economy_manager.call("is_gathering_enabled")):
		errors.append("economy automation was not disabled for the fixture")
	var cpu_ai: Node = field.get_node_or_null("CpuDispatchAI")
	if cpu_ai != null and cpu_ai.call("is_enabled"):
		errors.append("CPU automation was not disabled for the fixture")
	return errors


func _release_current_scene() -> void:
	if background != null and is_instance_valid(background):
		background.queue_free()
		background = null
		await tree.process_frame
	field = null
	network = null
	manager = null
	game_state = null
	world_config = null
	planet_catalog = null
	scenario_catalog = null
	upgrade_catalog = null
