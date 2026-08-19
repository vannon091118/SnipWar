class_name PreflightConstraintGenerationPipeline
extends RefCounted

const CONSTRAINT_NAME := "generation_pipeline"

func constraint_name() -> String:
	return CONSTRAINT_NAME

func run(ctx) -> bool:
	return _check_core(ctx)


func _check_core(ctx) -> bool:
	# Load everything at runtime to avoid preload parse-time resolution issues.
	var placement_script = load("res://scripts/generation/placement.gd")
	if placement_script == null:
		ctx.check(false, "Could not load Placement script")
		return false

	var placement = placement_script.new()
	placement.placement_id = &"test_1"
	placement.position = Vector2(100.0, 200.0)
	placement.placement_type = &"decoration"
	placement.asset_id = &"rock_01"
	placement.radius = 30.0

	var chunk_size = Vector2(512.0, 512.0)
	var chunk_coord = placement_script.call("compute_chunk_coord", placement.position, chunk_size)
	if chunk_coord != Vector2i(0, 0):
		ctx.check(false, "Placement chunk_coord incorrect")
		return false

	# Test PlacementRule.
	var rule_script = load("res://scripts/generation/placement_rule.gd")
	var rule = rule_script.new()
	rule.asset_id = &"test_rock"
	rule.probability = 0.5
	rule.min_count = 2
	rule.max_count = 10
	rule.radius = 30.0
	var rule_errors = rule.validate()
	if rule_errors.size() > 0:
		ctx.check(false, "PlacementRule validation failed: %s" % [", ".join(rule_errors)])
		return false

	# Test probability roll.
	var test_rng = RandomNumberGenerator.new()
	test_rng.seed = 42
	var roll_count = 0
	for _i in 1000:
		if rule.evaluate_roll(test_rng):
			roll_count += 1
	var rate = float(roll_count) / 1000.0
	if absf(rate - 0.5) > 0.1:
		ctx.check(false, "PlacementRule probability roll rate %.2f deviates from 0.5" % [rate])
		return false

	# Test min/max count.
	if not rule.min_count_not_met(1):
		ctx.check(false, "min_count_not_met(1) should be true for min_count=2")
		return false
	if rule.max_count_reached(5):
		ctx.check(false, "max_count_reached(5) should be false for max_count=10")
		return false

	# Test ChunkGrid.
	var grid_script = load("res://scripts/generation/chunk_grid.gd")
	var grid = grid_script.new()
	grid.chunk_size = Vector2(256.0, 256.0)
	for i in 20:
		var p = placement_script.new()
		p.placement_id = StringName("test_%d" % i)
		p.position = Vector2(float(i) * 50.0, float(i % 5) * 50.0)
		p.placement_type = &"test"
		grid.insert(p)
	if grid.total_count() != 20:
		ctx.check(false, "ChunkGrid count mismatch: %d" % grid.total_count())
		return false

	var query_rect = Rect2(Vector2.ZERO, Vector2(300.0, 300.0))
	var results = grid.query_rect(query_rect)
	if results.is_empty():
		ctx.check(false, "ChunkGrid query_rect returned empty")
		return false

	# Test LodLevel.
	var lod_script = load("res://scripts/generation/lod_level.gd")
	var lod = lod_script.new()
	lod.distance_thresholds = Vector3(200.0, 500.0, 1000.0)
	if lod.resolve_level(50.0) != 0:
		ctx.check(false, "LOD 50px should be FULL")
		return false
	if lod.resolve_level(300.0) != 1:
		ctx.check(false, "LOD 300px should be REDUCED")
		return false
	if lod.resolve_level(700.0) != 2:
		ctx.check(false, "LOD 700px should be MINIMAL")
		return false
	if lod.resolve_level(1500.0) != 3:
		ctx.check(false, "LOD 1500px should be CULLED")
		return false

	# Test pipeline determinism.
	var pipeline_script = load("res://scripts/generation/world_generation_pipeline.gd")
	var pass_script = load("res://scripts/generation/passes/planet_placement_pass.gd")
	var ctx_script = load("res://scripts/generation/generation_context.gd")

	var pipeline = pipeline_script.new()
	var planet_pass = pass_script.new()
	pipeline.configure([planet_pass])

	var config = load("res://resources/config/world_default.tres")
	var catalog = load("res://resources/config/planet_catalog.tres")
	var expanded_script = load("res://scripts/config/world_generator.gd")
	var expanded = expanded_script.call("expand_catalog", catalog, config.target_planet_count)

	var xl = load("res://resources/config/planet_sizes/extra_large.tres")
	var lg = load("res://resources/config/planet_sizes/large.tres")
	var vr = load("res://resources/config/planet_sizes/variable.tres")

	var gen_ctx_a = ctx_script.new()
	gen_ctx_a.set_seed(config.layout_seed)
	gen_ctx_a.world_config = config
	gen_ctx_a.expanded_catalog = expanded if not expanded.planets.is_empty() else catalog
	gen_ctx_a.size_profiles = [xl, lg, vr]

	var gen_ctx_b = ctx_script.new()
	gen_ctx_b.set_seed(config.layout_seed)
	gen_ctx_b.world_config = config
	gen_ctx_b.expanded_catalog = expanded if not expanded.planets.is_empty() else catalog
	gen_ctx_b.size_profiles = [xl, lg, vr]

	pipeline.execute(gen_ctx_a)
	pipeline.execute(gen_ctx_b)

	if gen_ctx_a.chunk_grid.total_count() != gen_ctx_b.chunk_grid.total_count():
		ctx.check(false, "Non-deterministic placement counts")
		return false

	var placements_a = gen_ctx_a.chunk_grid.all_placements()
	var placements_b = gen_ctx_b.chunk_grid.all_placements()
	for i in mini(placements_a.size(), placements_b.size()):
		var pa = placements_a[i]
		var pb = placements_b[i]
		if pa.position.distance_to(pb.position) > 0.01:
			ctx.check(false, "Non-deterministic position at %d" % i)
			return false

	ctx.check(true, "Generation pipeline: %d placements, deterministic" % gen_ctx_a.chunk_grid.total_count())
	return true
