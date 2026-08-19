class_name PreflightConstraintWorldGeneratorScaling
extends RefCounted

## WorldGenerator expansion, determinism, auto-columns and size-class ratio scaling.

func constraint_name() -> String:
	return "world_generator_scaling"


func run(ctx: PreflightContext) -> bool:
	var base_catalog: PlanetCatalog = preload("res://resources/config/planet_catalog.tres")
	var base_config: WorldConfig = preload("res://resources/config/world_default.tres")

	if not ctx.check(WorldGenerator.target_planet_count(base_config, base_catalog) == base_catalog.planets.size(), "target_planet_count should fall back to the catalog size"):
		return false
	var explicit_config := base_config.duplicate(true) as WorldConfig
	explicit_config.target_planet_count = 24
	if not ctx.check(WorldGenerator.target_planet_count(explicit_config, base_catalog) == 24, "target_planet_count should honor an explicit override"):
		return false

	var expanded := WorldGenerator.expand_catalog(base_catalog, 24)
	if not ctx.check(expanded.planets.size() == 24, "expanded catalog size is wrong"):
		return false
	var expanded_ids: Dictionary = {}
	var expanded_names: Dictionary = {}
	for index in expanded.planets.size():
		var definition: PlanetDefinition = expanded.planets[index]
		if definition == null:
			if not ctx.check(false, "expanded catalog contains a null definition"):
				return false
			continue
		expanded_ids[definition.planet_id] = true
		expanded_names[definition.display_name] = true
		if index < base_catalog.planets.size() and not ctx.check(definition.planet_id == base_catalog.planets[index].planet_id, "base planet identity changed during expansion"):
			return false
	if not ctx.check(expanded_ids.size() == 24 and expanded_names.size() == 24, "expanded planet ids/names are not unique"):
		return false
	for index in range(base_catalog.planets.size(), expanded.planets.size()):
		var rolled: PlanetDefinition = expanded.planets[index]
		if not ctx.check(rolled.planet_role == &"planet" and rolled.faction == &"neutral", "rolled planet %s must be a neutral world, not a homeworld clone" % rolled.planet_id):
			return false
	var expanded_again := WorldGenerator.expand_catalog(base_catalog, 24)
	if not ctx.check(expanded.planets[23].planet_id == expanded_again.planets[23].planet_id and expanded.planets[23].display_name == expanded_again.planets[23].display_name, "catalog expansion is not deterministic"):
		return false

	var grid_config := base_config.duplicate(true) as WorldConfig
	grid_config.design_size = Vector2(1920.0, 1080.0)
	grid_config.columns = 0
	var auto_columns := grid_config.resolved_columns(20)
	if not ctx.check(auto_columns >= 1 and auto_columns <= 20, "auto column resolution is out of range"):
		return false
	var cell_positions := WorldGenerator.grid_cell_positions(grid_config, 20)
	if not ctx.check(cell_positions.size() == 20, "grid cell position count is wrong"):
		return false
	for position in cell_positions:
		if not ctx.check(position.x >= 0.0 and position.x <= 1920.0 and position.y >= 0.0 and position.y <= 1080.0, "grid cell position is outside world bounds"):
			return false
	grid_config.columns = 5
	if not ctx.check(grid_config.resolved_columns(20) == 5, "explicit columns should override auto resolution"):
		return false

	var absolute_config := base_config.duplicate(true) as WorldConfig
	absolute_config.extra_large_count = 2
	absolute_config.large_count = 1
	if not ctx.check(absolute_config.resolved_size_class_counts(10) == Vector2i(2, 1), "absolute size class counts are wrong"):
		return false
	if not ctx.check(absolute_config.resolved_size_class_counts(2) == Vector2i(2, 0), "absolute size class counts should clamp to the planet count"):
		return false
	var ratio_config := base_config.duplicate(true) as WorldConfig
	ratio_config.extra_large_ratio = 0.2
	ratio_config.large_ratio = 0.1
	if not ctx.check(ratio_config.resolved_size_class_counts(100) == Vector2i(20, 10), "ratio size class counts are wrong"):
		return false
	if not ctx.check(ratio_config.validate_for_planet_count(100).is_empty(), "ratio-scaled world config should validate"):
		return false
	ratio_config.extra_large_ratio = 0.9
	ratio_config.large_ratio = 0.5
	if not ctx.check(not ratio_config.validate_for_planet_count(100).is_empty(), "size class ratios exceeding one should fail validation"):
		return false

	return true
