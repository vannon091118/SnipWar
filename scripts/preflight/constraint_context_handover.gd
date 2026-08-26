class_name PreflightConstraintContextHandover
extends RefCounted

## End-to-end scene handover: world -> battle -> world through the
## SceneDirectorService autoload. Verifies that GameState domain state and the
## world session survive the scene switch and that the reconnected world
## rebuilds its planet field.

func constraint_name() -> String:
	return "context_handover"

func requires_scene() -> bool:
	return true


func run(ctx: PreflightContext) -> bool:
	var state: Node = ctx.game_state
	var field: Node = ctx.field
	if not ctx.check(state != null and field != null, "context handover needs a booted world fixture"):
		return false
	var director: Node = ctx.root().get_node_or_null("SceneDirectorService")
	if not ctx.check(director != null, "SceneDirectorService autoload is missing"):
		return false

	# Baseline domain state that must survive the round trip.
	var player_planets_before: int = state.get_ownership_count(GameState.FACTION_PLAYER)
	var energy_before: int = state.get_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY)

	# Make the fixture world the director-managed current scene.
	ctx.root().get_tree().current_scene = ctx.background

	# Synthetic player-involved battle payload.
	var fleet_a := FleetSnapshot.new()
	fleet_a.fleet_id = &"fleet_handover_a"
	fleet_a.faction = GameState.FACTION_PLAYER
	fleet_a.ships = [ctx.make_ship_assembly(&"hull_t1", &"scanner_t1", [], &"weapon_t1", &"drive_t1", &"shield_t1", &"ship_handover_a", &"military")]
	fleet_a.calculate_stats()
	var fleet_b := FleetSnapshot.new()
	fleet_b.fleet_id = &"fleet_handover_b"
	fleet_b.faction = GameState.FACTION_CPU
	fleet_b.ships = [ctx.make_ship_assembly(&"hull_t1", &"scanner_t1", [], &"weapon_t1", &"drive_t1", &"shield_t1", &"ship_handover_b", &"military")]
	fleet_b.calculate_stats()
	var replay: CombatReplay = FleetBattleSimulator.simulate_battle(fleet_a, fleet_b, 4242)
	var context := BattleContext.new()
	context.battle_id = &"battle_handover"
	context.fleet_a = fleet_a.copy()
	context.fleet_b = fleet_b.copy()
	context.route_a = [Vector2.ZERO, Vector2(200, 0)]
	context.route_b = [Vector2(200, 0), Vector2.ZERO]
	context.engagement_point = Vector2(100, 0)
	context.engagement_type = &"test"
	context.replay = replay
	context.route_engagement = false

	# Switch to the battle scene.
	if not ctx.check(director.goto_scene(&"battle", context), "goto_scene(battle) rejected the handover"):
		return false
	await director.transition_completed
	await ctx.await_frame()
	await ctx.await_frame()
	var current: Node = ctx.root().get_tree().current_scene
	if not ctx.check(current is BattleScene, "battle scene did not become current after handover"):
		return false
	if not ctx.check(current.visible, "battle scene should be visible during playback"):
		return false
	if not ctx.check(state.pending_battle_context() != null, "pending battle context was not handed over through GameState"):
		return false

	# Return to the strategy overworld.
	if not ctx.check(director.goto_scene(&"world"), "goto_scene(world) rejected the return"):
		return false
	await director.transition_completed
	await ctx.await_frame()
	await ctx.await_frame()
	await ctx.await_frame()
	current = ctx.root().get_tree().current_scene
	if not ctx.check(current != null and current.name == "World", "world scene did not become current after return"):
		return false
	# Domain state is preserved across the scene round trip.
	if not ctx.check(state.get_ownership_count(GameState.FACTION_PLAYER) == player_planets_before, "ownership changed across the scene handover"):
		return false
	if not ctx.check(state.get_faction_resource(GameState.FACTION_PLAYER, GameState.RES_ENERGY) == energy_before, "resources changed across the scene handover"):
		return false
	var field_after: Node = current.get_node_or_null("PlanetField")
	if not ctx.check(field_after != null and field_after.get_child_count() > 0, "reconnected world did not rebuild its planet field"):
		return false
	# Complete the loop: world -> main menu through the director.
	if not ctx.check(director.goto_scene(&"menu"), "goto_scene(menu) rejected the loop return"):
		return false
	await director.transition_completed
	await ctx.await_frame()
	current = ctx.root().get_tree().current_scene
	if not ctx.check(current != null and current.name == "MainMenu", "main menu did not become current after the loop"):
		return false
	# Cleanup: free the menu so later fixture boots start clean.
	if current != null and is_instance_valid(current):
		current.queue_free()
	ctx.root().get_tree().current_scene = null
	await ctx.await_frame()
	return true
