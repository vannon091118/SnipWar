class_name PreflightConstraintLocalResources
extends RefCounted

## Local per-planet vaults, transfers, trade-route ticking and seed dealing.

const RESOURCE_POOL: ResourcePool = preload("res://resources/config/resource_pool_default.tres")

func constraint_name() -> String:
	return "local_resources"

func requires_scene() -> bool:
	return true

func run(ctx: PreflightContext) -> bool:
	var state: Node = ctx.game_state
	if state == null:
		return false
	if not ctx.check(state.has_method("get_local_resources"), "GameState should expose get_local_resources"):
		return false
	if not ctx.check(state.has_method("transfer_local_resources"), "GameState should expose transfer_local_resources"):
		return false

	var planet_a := StringName("local_test_a")
	var planet_b := StringName("local_test_b")
	state.set_planet_resource(planet_a, GameState.RES_ENERGY)
	state.set_planet_resource(planet_b, GameState.RES_MATERIAL)

	# Add / spend with overdraft protection.
	state.add_local_resource(planet_a, GameState.RES_ENERGY, 10)
	if not ctx.check(state.get_local_resource(planet_a, GameState.RES_ENERGY) == 10, "local add should increase the vault"):
		return false
	if not ctx.check(state.spend_local_resource(planet_a, GameState.RES_ENERGY, 4), "local spend within balance should succeed"):
		return false
	if not ctx.check(state.get_local_resource(planet_a, GameState.RES_ENERGY) == 6, "local spend should decrease the vault"):
		return false
	if not ctx.check(not state.spend_local_resource(planet_a, GameState.RES_ENERGY, 999), "local spend must not overdraft"):
		return false

	# Transfer moves resources between planets.
	state.add_local_resource(planet_b, GameState.RES_MATERIAL, 3)
	if not ctx.check(state.transfer_local_resources(planet_a, planet_b, GameState.RES_ENERGY, 2), "local transfer should succeed"):
		return false
	if not ctx.check(state.get_local_resource(planet_b, GameState.RES_ENERGY) == 2 and state.get_local_resource(planet_a, GameState.RES_ENERGY) == 4, "transfer should move the exact amount"):
		return false

	# Trade route tick.
	var route_id: StringName = state.register_trade_route(planet_a, planet_b, GameState.RES_ENERGY)
	if not ctx.check(not String(route_id).is_empty(), "register_trade_route should return a route id"):
		return false
	var moved: int = state.tick_trade_routes()
	if not ctx.check(moved >= 1 and state.get_local_resource(planet_b, GameState.RES_ENERGY) >= 2, "trade route tick should transfer its flow rate"):
		return false

	# Seed dealing is one-time (idempotent) and keys off the planet's own resource.
	var before: int = state.get_local_resource(planet_a, GameState.RES_ENERGY)
	state.deal_local_resources([planet_a], RESOURCE_POOL, 424242)
	var increment: int = state.get_local_resource(planet_a, GameState.RES_ENERGY) - before
	state.deal_local_resources([planet_a], RESOURCE_POOL, 424242)
	var after_second: int = state.get_local_resource(planet_a, GameState.RES_ENERGY)
	if not ctx.check(increment > 0, "local resource dealing must seed a starting stock"):
		return false
	if not ctx.check(after_second == before + increment, "local resource dealing must be idempotent (no re-seeding on chunk regeneration)"):
		return false

	return true
