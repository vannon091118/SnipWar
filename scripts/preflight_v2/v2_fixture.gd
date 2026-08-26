extends RefCounted

## Wraps PreflightFixture with a state-only reset that avoids the expensive
## scene re-instantiation.  The scene is booted once via the base fixture;
## subsequent constraints get reset_state() instead of boot_default().
##
## reset_state() does NOT replicate the full boot_default() baseline check —
## it only verifies hard invariants (no tech/ship leaks, automation off).
## The runner's checkpoint/verify system catches remaining drift.

const _BaseFixture := preload("res://scripts/preflight/preflight_fixture.gd")
const _DEFAULT_RESOURCE_POOL: ResourcePool = preload("res://resources/config/resource_pool_default.tres")

var base: PreflightFixture
var tree: SceneTree
var boot_count: int = 0

## Captured once at first boot.  Every reset_state() restores this exact
## baseline instead of the post-constraint state.
var _initial_ownership: Dictionary = {}    # planet_id -> faction
var _initial_homeworlds: Dictionary = {}   # faction -> planet_id
var _initial_resources: Dictionary = {}    # planet_id -> resource_id
var _initial_starting_workers: Dictionary = {}  # planet_id -> int
var _initial_snapshot_valid: bool = false


func _init(p_tree: SceneTree) -> void:
	tree = p_tree
	base = _BaseFixture.new(p_tree)


## First boot — full scene instantiation (same as original).
## Also captures the initial baseline for future resets.
func boot_default(ctx: PreflightContext) -> bool:
	var result: bool = await base.boot_default(ctx)
	if result:
		boot_count += 1
		_capture_initial_baseline()
	return result


## Captures the current GameState as the "clean" baseline.
func _capture_initial_baseline() -> void:
	if base.game_state == null or base.field == null:
		return

	var state: Node = base.game_state
	_initial_ownership = {}
	_initial_homeworlds = {}
	_initial_resources = state.call("resource_snapshot")
	_initial_starting_workers = {}

	for child in base.field.get_children():
		var planet: Planet = child as Planet
		if planet == null:
			continue
		var pid: StringName = planet.planet_id
		_initial_ownership[pid] = state.call("faction_of", pid)
		_initial_starting_workers[pid] = state.starting_workers_of(pid)

	_initial_homeworlds[GameState.FACTION_PLAYER] = state.call("homeworld_for", GameState.FACTION_PLAYER)
	_initial_homeworlds[GameState.FACTION_CPU] = state.call("homeworld_for", GameState.FACTION_CPU)
	_initial_snapshot_valid = true


## Lightweight state-only reset.  Restores the initial baseline without
## re-instantiating the scene.  Only checks hard invariants; the runner's
## checkpoint system catches remaining drift.
func reset_state(ctx: PreflightContext) -> bool:
	if base.game_state == null or base.field == null or base.world_config == null:
		return false
	if not _initial_snapshot_valid:
		return false

	var state: Node = base.game_state
	var world_config: WorldConfig = base.world_config
	var planet_catalog: PlanetCatalog = base.planet_catalog
	if planet_catalog == null:
		return false

	# 1. Reset all GameState domains
	var infinite_world: bool = world_config.is_infinite_world()
	state.call("begin_new_game", planet_catalog, &"default", PreflightFixture.PREFLIGHT_LAYOUT_SEED, infinite_world)
	state.call("set_jobs_auto_advance", false)

	# 2. Restore ownership from initial baseline (direct write, no remember_planet)
	var faction_dom = state.get("faction_domain")
	for pid in _initial_ownership:
		faction_dom.ownership[pid] = _initial_ownership[pid]

	# 3. Register homeworlds
	var player_hw: StringName = _initial_homeworlds.get(GameState.FACTION_PLAYER, &"") as StringName
	var cpu_hw: StringName = _initial_homeworlds.get(GameState.FACTION_CPU, &"") as StringName
	if not String(player_hw).is_empty():
		state.call("register_homeworld", GameState.FACTION_PLAYER, player_hw)
	if not String(cpu_hw).is_empty():
		state.call("register_homeworld", GameState.FACTION_CPU, cpu_hw)

	# 4. Restore starting workers
	for pid in _initial_starting_workers:
		faction_dom.starting_workers[pid] = _initial_starting_workers[pid]

	# 5. Restore resource assignments from initial baseline
	var econ_dom = state.get("economy_domain")
	if econ_dom != null:
		for pid in _initial_resources:
			econ_dom.planet_resources[pid] = _initial_resources[pid]

	# 6. Fix starter research ship — begin_new_game created it with empty
	# homeworld because homeworlds weren't registered yet.
	var ship_dom = state.get("ship_domain")
	if ship_dom != null and not String(player_hw).is_empty():
		var records: Array = state.call("get_research_ship_records", GameState.FACTION_PLAYER)
		if records.size() > 0:
			# Fix the record's current_planet_id
			var ship_id: StringName = records[0].get("ship_id", &"") as StringName
			if ship_dom.persistent_ships.has(ship_id):
				ship_dom.persistent_ships[ship_id].current_planet_id = player_hw

	# 7. Re-establish scanning for homeworlds
	if not String(player_hw).is_empty():
		state.call("discover_planet", GameState.FACTION_PLAYER, player_hw)
		state.call("scan_planet", GameState.FACTION_PLAYER, player_hw, &"", &"", 0)
	if not String(cpu_hw).is_empty():
		state.call("discover_planet", GameState.FACTION_CPU, cpu_hw)
		state.call("scan_planet", GameState.FACTION_CPU, cpu_hw, &"", &"", 0)

	# 8. Reset live planet node states
	for child in base.field.get_children():
		var planet: Planet = child as Planet
		if planet == null:
			continue
		planet.set_worker_spawn_enabled(false)
		planet.worker_count = state.starting_workers_of(planet.planet_id)
		planet.worker_state = 0  # WorkerState.IDLE

	# 9. Disable automation & refresh
	_disable_automation()
	if base.network != null and base.network.has_method("_refresh_fog_of_war"):
		base.network.call("_refresh_fog_of_war")

	boot_count += 1

	# Hard invariant check only — NOT the full baseline_errors check.
	# The runner's checkpoint/verify system catches remaining drift.
	var hard_errors: PackedStringArray = _hard_invariant_check()
	if not hard_errors.is_empty():
		push_warning("[v2-fixture] reset_state hard invariants failed: %s" % hard_errors)
		return false

	return true


## Only checks critical invariants that would cause constraint crashes.
func _hard_invariant_check() -> PackedStringArray:
	var errors := PackedStringArray()
	var gs: Node = base.game_state
	if gs == null:
		errors.append("game_state is null")
		return errors
	if gs.validate().size() != 0 or gs.validate_starting_setup().size() != 0:
		errors.append("GameState ownership/start setup is invalid")
	if gs.get_researched_technologies(GameState.FACTION_PLAYER).size() != 0 or gs.get_researched_technologies(GameState.FACTION_CPU).size() != 0:
		errors.append("global technology state leaked")
	return errors


## Releases the current scene before exit.
func cleanup() -> void:
	_initial_snapshot_valid = false
	await base.cleanup()


## Prepares the ship builder prerequisites (delegates to base).
func prepare_ship_builder() -> bool:
	return base.prepare_ship_builder()


# --- Direct property access for convenience ---

var background: Node:
	get: return base.background

var field: Node:
	get: return base.field

var network: Node:
	get: return base.network

var manager: Node:
	get: return base.manager

var game_state: Node:
	get: return base.game_state

var world_config: WorldConfig:
	get: return base.world_config

var planet_catalog: PlanetCatalog:
	get: return base.planet_catalog

var scenario_catalog: ScenarioCatalog:
	get: return base.scenario_catalog

var upgrade_catalog: PlanetUpgradeCatalog:
	get: return base.upgrade_catalog


func _disable_automation() -> void:
	if base.field == null:
		return
	var economy_manager: Node = base.field.get_node_or_null("EconomyManager")
	if economy_manager != null:
		economy_manager.call("set_enabled", false)
		economy_manager.call("set_gathering_enabled", false)
	var cpu_ai: Node = base.field.get_node_or_null("CpuDispatchAI")
	if cpu_ai != null:
		cpu_ai.call("set_enabled", false)
