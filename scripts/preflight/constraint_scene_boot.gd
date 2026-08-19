class_name PreflightConstraintSceneBoot
extends RefCounted

## Boots the starfield background, validates the default scenario/world wiring and
## captures the shared node/resource references into the context for later modules.

func constraint_name() -> String:
	return "scene_boot"


func run(ctx: PreflightContext) -> bool:
	var scene: PackedScene = preload("res://scenes/backgrounds/starfield_background.tscn")
	var background: Node = scene.instantiate()
	ctx.background = background
	ctx.root().add_child(background)
	await ctx.await_frame()
	await ctx.await_frame()

	var background_node: Node2D = background as Node2D
	var field: Node = background.get_node("PlanetField")
	var planet_field_node: Node2D = field as Node2D
	var meteor_field_node: Node2D = background.get_node("MeteorField") as Node2D
	if not ctx.check(background_node.global_position.distance_to(Vector2.ZERO) <= 0.01, "Background has an unexpected scene offset"):
		return false
	if not ctx.check(planet_field_node.position.distance_to(Vector2.ZERO) <= 0.01 and planet_field_node.global_position.distance_to(background_node.global_position) <= 0.01, "PlanetField has an unexpected scene offset"):
		return false
	if not ctx.check(meteor_field_node.position.distance_to(Vector2.ZERO) <= 0.01 and meteor_field_node.global_position.distance_to(background_node.global_position) <= 0.01, "MeteorField has an unexpected scene offset"):
		return false
	var world_config: WorldConfig = field.get("world_config") as WorldConfig
	if not ctx.check(world_config != null, "world config is missing"):
		return false
	var viewport_size: Vector2 = ctx.get_root().get_viewport().get_visible_rect().size
	if not ctx.check(viewport_size.distance_to(world_config.design_size) <= 0.01, "world design size differs from the Godot viewport"):
		return false
	var game_state: Node = ctx.get_root().get_node_or_null("GameState")
	if not ctx.check(game_state != null, "GameState autoload is missing"):
		return false
	if not game_state.faction_changed.is_connected(ctx.capture_faction_changed):
		game_state.faction_changed.connect(ctx.capture_faction_changed)
	if not ctx.check(game_state.validate().is_empty(), "GameState ownership validation failed"):
		return false
	var scenario_catalog: ScenarioCatalog = background.get("scenario_catalog") as ScenarioCatalog
	if not ctx.check(scenario_catalog != null and scenario_catalog.validate().is_empty(), "scenario catalog validation failed"):
		return false
	var active_scenario: ScenarioDefinition = background.get("active_scenario") as ScenarioDefinition
	if not ctx.check(active_scenario != null and active_scenario.id == &"default", "default scenario was not selected"):
		return false
	if not ctx.check(active_scenario.route_mode == ScenarioDefinition.ROUTE_MODE_ALL_PLANETS and active_scenario.route_mode == world_config.route_mode, "default scenario route rule was not applied"):
		return false
	if not ctx.check(active_scenario.map_definition != null and active_scenario.map_definition.world_config == world_config, "active scenario map was not applied"):
		return false
	var background_config: BackgroundConfig = background.get("background_config") as BackgroundConfig
	if not ctx.check(background_config != null and background_config.validate().is_empty(), "background config validation failed"):
		return false
	var background_render_stats: Dictionary = background.call("get_render_batch_stats")
	var background_batch_count: int = int(background_render_stats.get("batch_count", 0))
	var background_batched_elements: int = int(background_render_stats.get("batched_elements", 0))
	var background_source_elements: int = int(background_render_stats.get("source_elements", 0))
	var background_fold_alpha_draw_calls: int = int(background_render_stats.get("fold_alpha_draw_calls", 0))
	var background_grain_alpha_draw_calls: int = int(background_render_stats.get("grain_alpha_draw_calls", 0))
	var background_draw_calls: int = int(background_render_stats.get("estimated_draw_calls", 0))
	if not ctx.check(background_batch_count >= 2 and background_batch_count <= 3, "background render batches are missing"):
		return false
	if not ctx.check(background_batched_elements == background_config.star_count + background_config.dust_count, "background batched element count is wrong"):
		return false
	if not ctx.check(background_config.fold_alpha_bucket_count >= 2 and background_config.grain_alpha_bucket_count >= 2, "background alpha fidelity is still averaged"):
		return false
	if not ctx.check(background_fold_alpha_draw_calls >= 2 and background_fold_alpha_draw_calls <= background_config.fold_alpha_bucket_count and background_grain_alpha_draw_calls >= 2 and background_grain_alpha_draw_calls <= background_config.grain_alpha_bucket_count, "background alpha fidelity buckets are incomplete"):
		return false
	if not ctx.check(background_source_elements > background_draw_calls * 4 and background_draw_calls <= 24, "background draw-call budget is not compressed"):
		return false
	var meteor_config: MeteorConfig = background.get_node("MeteorField").get("meteor_config") as MeteorConfig
	if not ctx.check(meteor_config != null and meteor_config.validate().is_empty(), "meteor config validation failed"):
		return false
	var planet_catalog: PlanetCatalog = field.get("planet_catalog") as PlanetCatalog
	if not ctx.check(planet_catalog != null, "planet catalog is missing"):
		return false
	var catalog_errors := planet_catalog.validate()
	if not ctx.check(catalog_errors.is_empty(), "planet catalog validation failed"):
		return false
	if not ctx.check(game_state.validate_starting_setup().is_empty(), "GameState starting setup validation failed"):
		return false
	if not ctx.check(game_state.get_ownership_count(GameState.FACTION_NEUTRAL) == 8 and game_state.get_ownership_count(GameState.FACTION_PLAYER) == 1 and game_state.get_ownership_count(GameState.FACTION_CPU) == 1, "GameState ownership seed does not match the default catalog"):
		return false
	if not ctx.check(game_state.homeworld_for(GameState.FACTION_PLAYER) == &"ocean" and game_state.homeworld_for(GameState.FACTION_CPU) == &"paper", "GameState homeworld assignment is wrong"):
		return false

	ctx.field = field
	ctx.network = field.get_node("PlanetNetwork")
	ctx.manager = field.get_node("WorkerManager")
	ctx.game_state = game_state
	game_state.call("set_jobs_auto_advance", false)
	ctx.world_config = world_config
	ctx.planet_catalog = planet_catalog
	ctx.scenario_catalog = scenario_catalog
	ctx.upgrade_catalog = preload("res://resources/config/planet_upgrade_catalog_default.tres")
	return true
