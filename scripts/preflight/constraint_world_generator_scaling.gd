class_name PreflightConstraintWorldGeneratorScaling
extends RefCounted

## WorldGenerator expansion, determinism, auto-columns and size-class ratio scaling.

func constraint_name() -> String:
	return "world_generator_scaling"

func requires_scene() -> bool:
	return false


func run(ctx: PreflightContext) -> bool:
	var base_catalog: PlanetCatalog = preload("res://resources/config/planet_catalog.tres")
	var base_config: WorldConfig = preload("res://resources/config/world_default.tres")

	if not ctx.check(WorldGenerator.target_planet_count(base_config, base_catalog) == base_config.target_planet_count, "target_planet_count should honor the world config override"):
		return false
	var fallback_config := base_config.duplicate(true) as WorldConfig
	fallback_config.target_planet_count = 0
	if not ctx.check(WorldGenerator.target_planet_count(fallback_config, base_catalog) == 0, "target_planet_count should return zero without an override or catalog"):
		return false
	var explicit_config := base_config.duplicate(true) as WorldConfig
	explicit_config.target_planet_count = 24
	if not ctx.check(WorldGenerator.target_planet_count(explicit_config, base_catalog) == 24, "target_planet_count should honor an explicit override"):
		return false

	var generated := WorldGenerator.generate_catalog(base_config, 424242, 24)
	if not ctx.check(generated.planets.size() == 24, "generated catalog size is wrong"):
		return false
	var generated_ids: Dictionary = {}
	var generated_names: Dictionary = {}
	for index in generated.planets.size():
		var definition: PlanetDefinition = generated.planets[index]
		if definition == null:
			if not ctx.check(false, "generated catalog contains a null definition"):
				return false
			continue
		generated_ids[definition.planet_id] = true
		generated_names[definition.display_name] = true
		if index < 2 and not ctx.check(definition.planet_role == &"homeworld" and definition.faction == (&"a" if index == 0 else &"b"), "generated planet %d should be a homeworld" % index):
			return false
		if index >= 2 and not ctx.check(definition.planet_role == &"planet" and definition.faction == &"neutral", "generated planet %d should be a neutral world" % index):
			return false
	if not ctx.check(generated_ids.size() == 24 and generated_names.size() == 24, "generated planet ids/names are not unique"):
		return false
	var generated_again := WorldGenerator.generate_catalog(base_config, 424242, 24)
	if not ctx.check(generated.planets[23].planet_id == generated_again.planets[23].planet_id and generated.planets[23].display_name == generated_again.planets[23].display_name, "catalog generation is not deterministic"):
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
