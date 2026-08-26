extends RefCounted

## Wraps PreflightFixture with a state-only reset that avoids the expensive
## scene re-instantiation.  The scene is booted once via the base fixture;
## subsequent constraints get reset_state() instead of boot_default().

const _BaseFixture := preload("res://scripts/preflight/preflight_fixture.gd")

var base: PreflightFixture
var tree: SceneTree
var boot_count: int = 0


func _init(p_tree: SceneTree) -> void:
	tree = p_tree
	base = _BaseFixture.new(p_tree)


## First boot — full scene instantiation (same as original).
func boot_default(ctx: PreflightContext) -> bool:
	var result: bool = await base.boot_default(ctx)
	if result:
		boot_count += 1
	return result


## Lightweight state-only reset.  Calls begin_new_game + deal_resources
## on the same scene instance.  Returns a context-ready bool.
func reset_state(ctx: PreflightContext) -> bool:
	if base.game_state == null or base.field == null:
		return false

	var state: Node = base.game_state
	var world_config: WorldConfig = base.world_config
	var planet_catalog: PlanetCatalog = base.planet_catalog
	var scenario_catalog: ScenarioCatalog = base.scenario_catalog

	if world_config == null or planet_catalog == null:
		return false

	# reset_state delegates to full boot_default — scene node state cannot be
	# partially reset because begin_new_game() only touches GameState data, not
	# the live planet/network nodes that scene constraints depend on.
	var result: bool = await base.boot_default(ctx)
	if result:
		boot_count += 1
	return result


## Releases the current scene before exit.
func cleanup() -> void:
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
