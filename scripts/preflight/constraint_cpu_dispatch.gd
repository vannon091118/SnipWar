class_name PreflightConstraintCpuDispatch
extends RefCounted

## CPU dispatch AI mission launch plus source worker costs and cluster-tier
## bonuses flowing into visible dispatch clusters.

func constraint_name() -> String:
	return "cpu_dispatch"


func run(ctx: PreflightContext) -> bool:
	var field: Node = ctx.field
	var manager: Node = ctx.manager
	var game_state: Node = ctx.game_state
	var upgrade_catalog: PlanetUpgradeCatalog = ctx.upgrade_catalog
	var transit_config: TransitConfig = manager.get("transit_config") as TransitConfig

	var player_homeworld: StringName = game_state.homeworld_for(GameState.FACTION_PLAYER)
	var cpu_homeworld: Planet = ctx.find_planet_by_id(field, game_state.homeworld_for(GameState.FACTION_CPU))
	if not ctx.check(cpu_homeworld != null, "CPU homeworld for dispatch test is missing"):
		return false
	var cpu_ai: Node = field.get_node_or_null("CpuDispatchAI")
	var cpu_dispatch_config: CpuDispatchConfig = cpu_ai.get("dispatch_config") as CpuDispatchConfig
	var cpu_workers_before: int = cpu_homeworld.worker_count
	if cpu_workers_before < cpu_dispatch_config.minimum_source_workers:
		cpu_homeworld.register_workers(cpu_dispatch_config.minimum_source_workers - cpu_workers_before)
	cpu_workers_before = cpu_homeworld.worker_count
	var manager_children_before_cpu: int = manager.get_child_count()
	var cpu_dispatched: bool = cpu_ai.call("dispatch_once", true)
	if not ctx.check(cpu_dispatched and manager.get_child_count() > manager_children_before_cpu, "CPU dispatch AI did not launch a mission"):
		return false
	var cpu_cluster: WorkerCluster = null
	for manager_child in manager.get_children():
		if manager_child is WorkerCluster:
			cpu_cluster = manager_child as WorkerCluster
			break
	if not ctx.check(cpu_cluster != null and cpu_cluster.source_faction == GameState.FACTION_CPU and cpu_cluster.mission_type == GameState.MISSION_COLONY, "CPU dispatch AI did not choose a colony mission"):
		return false
	for manager_child in manager.get_children():
		if manager_child is WorkerCluster:
			(manager_child as WorkerCluster).queue_free()
	await ctx.await_frame()
	if cpu_homeworld.worker_count < cpu_workers_before:
		cpu_homeworld.register_workers(cpu_workers_before - cpu_homeworld.worker_count)
	if not ctx.check(cpu_homeworld.worker_count == cpu_workers_before, "CPU dispatch test did not restore source workers"):
		return false

	# --- WORKER COSTS ---
	var upgrade_test_technology_catalog: TechnologyCatalog = preload("res://resources/config/technology_catalog_default.tres")
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY, 50)
	if not game_state.has_technology(GameState.FACTION_PLAYER, &"shipyard_construction"):
		if not ctx.check(game_state.research_technology(GameState.FACTION_PLAYER, &"shipyard_construction", upgrade_test_technology_catalog), "shipyard construction research should unlock the shipyard build"):
			return false
		game_state.call("advance_research", 999.0)
	var shipyard_upgrade: PlanetUpgradeDefinition = upgrade_catalog.resolve(&"shipyard")
	if not ctx.check(shipyard_upgrade != null and shipyard_upgrade.workers_required == 2, "shipyard should reserve 2 workers"):
		return false
	if not ctx.check(not game_state.can_purchase_upgrade(player_homeworld, &"shipyard", upgrade_catalog, 1), "shipyard must not be buyable with only 1 worker"):
		return false
	if not ctx.check(game_state.can_purchase_upgrade(player_homeworld, &"shipyard", upgrade_catalog, 2), "shipyard must be buyable with 2 workers"):
		return false

	# Test source traits flowing into visible dispatch tiers
	var upgrade_planet: Planet = ctx.find_planet_by_id(field, player_homeworld)
	if not ctx.check(upgrade_planet != null and upgrade_planet.get_cluster_tier_bonus() == 0, "planet cluster tier bonus should start at zero"):
		return false
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_BIOMASS, 100)
	game_state.add_faction_resource(GameState.FACTION_PLAYER, GameState.RES_MATERIAL, 100)
	if not ctx.check(game_state.purchase_upgrade(player_homeworld, &"shipyard", upgrade_catalog), "shipyard purchase for tier bonus test should succeed"):
		return false
	if not ctx.check(game_state.purchase_upgrade(player_homeworld, &"war_shipyard", upgrade_catalog), "war_shipyard purchase for tier bonus test should succeed"):
		return false
	var source_tier_bonus: int = upgrade_planet.get_cluster_tier_bonus()
	if not ctx.check(source_tier_bonus == 1, "war_shipyard bonus did not reach the source planet"):
		return false
	if not ctx.check(Dispatch.cluster_tier(5, transit_config, source_tier_bonus) == &"l", "source tier bonus did not reach visible dispatch tier"):
		return false
	var bonus_route: Array[Vector2] = [upgrade_planet.global_position, cpu_homeworld.global_position]
	manager.call("_dispatch_clusters", upgrade_planet, cpu_homeworld, 1, bonus_route, GameState.MISSION_MILITARY)
	var bonus_cluster: WorkerCluster = null
	for manager_child in manager.get_children():
		if manager_child is WorkerCluster:
			bonus_cluster = manager_child as WorkerCluster
			break
	if not ctx.check(bonus_cluster != null and bonus_cluster.cluster_tier_bonus == source_tier_bonus, "worker manager did not pass the source tier bonus"):
		return false
	var bonus_sprite: Sprite2D = bonus_cluster.get_node_or_null("Sprite2D") as Sprite2D
	var expected_bonus_tier: ClusterTierDefinition = Dispatch.cluster_definition(1, transit_config, source_tier_bonus)
	if not ctx.check(bonus_sprite != null and expected_bonus_tier != null and bonus_sprite.texture == expected_bonus_tier.texture, "worker cluster did not render the bonus tier"):
		return false
	bonus_cluster.queue_free()
	await ctx.await_frame()

	# --- CPU SHIP PATH: module-model loadouts after research ---
	# dispatch_once(true) above already ran the CPU research driver once; a
	# second tick advances scanner_drone so a full loadout becomes buildable
	# (scanner_t1 is gated behind it).
	if not ctx.check(game_state.has_technology(GameState.FACTION_CPU, &"shipyard_construction"), "CPU research driver should research shipyard construction"):
		return false
	# Keep ticking the research driver until the scanner tech lands (the ship
	# line is shipyard → scout_hull → scanner_drone).
	for _tick_index in range(4):
		cpu_ai.call("dispatch_once", true)
		if game_state.has_technology(GameState.FACTION_CPU, &"scanner_drone"):
			break
	if not ctx.check(game_state.has_technology(GameState.FACTION_CPU, &"scanner_drone"), "CPU research driver should advance the scanner tech"):
		return false
	game_state.add_faction_resource(GameState.FACTION_CPU, GameState.RES_ENERGY, 400)
	game_state.add_faction_resource(GameState.FACTION_CPU, GameState.RES_MATERIAL, 400)
	game_state.add_faction_resource(GameState.FACTION_CPU, GameState.RES_BIOMASS, 100)
	cpu_homeworld.register_workers(maxi(0, cpu_dispatch_config.minimum_source_workers - cpu_homeworld.worker_count))
	var conflict_manager: Node = field.get_node_or_null("ConflictManager")
	var ships_before: int = conflict_manager.get_child_count() if conflict_manager != null else 0
	# The ship path is staged: buy shipyard → start build → dispatch once the
	# build job completes (advance_builds mirrors GameState._process ticking).
	var ship_launched := false
	for _ship_tick in range(6):
		game_state.call("advance_builds", 999.0)
		if conflict_manager != null and conflict_manager.get_child_count() > ships_before:
			ship_launched = true
			break
		cpu_ai.call("_maybe_build_and_dispatch_ship", cpu_homeworld, cpu_dispatch_config)
	if not ctx.check(ship_launched, "CPU ship path should launch a ship after research"):
		return false
	if not ctx.check(conflict_manager != null and conflict_manager.get_child_count() > ships_before, "CPU ship dispatch should add a ShipBase"):
		return false
	for ship_child in conflict_manager.get_children():
		if ship_child is Node2D and String(ship_child.name).begins_with("Ship_"):
			ship_child.queue_free()
	await ctx.await_frame()

	return true
