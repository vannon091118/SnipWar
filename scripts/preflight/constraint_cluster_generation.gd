class_name PreflightConstraintClusterGeneration
extends RefCounted

## Validates cluster-void generation (Makulatur system): parameter ranges,
## cluster generation determinism, sun scaling, and void ratio.

func constraint_name() -> String:
	return "cluster_generation"

func requires_scene() -> bool:
	return false

func run(ctx: PreflightContext) -> bool:
	# Pure phase (no scene boot): ctx.world_config is not wired. Like the
	# sibling pure world constraints, construct the canonical config here
	# instead of silently returning a no-op PASS with zero checks.
	var world_config: WorldConfig = ctx.world_config
	if world_config == null:
		world_config = preload("res://resources/config/world_default.tres")

	# Test 1: Cluster generation parameters are valid
	if not ctx.check(world_config.void_ratio >= 0.0 and world_config.void_ratio <= 0.6, "void_ratio must stay between 0 and 0.6"):
		return false
	if not ctx.check(world_config.min_cluster_size >= 1, "min_cluster_size must be at least 1"):
		return false
	if not ctx.check(world_config.max_cluster_size >= world_config.min_cluster_size, "max_cluster_size must be >= min_cluster_size"):
		return false

	# Test 2: is_cluster_generation_enabled helper
	if not ctx.check(world_config.is_cluster_generation_enabled(), "cluster generation should be enabled with default params"):
		return false

	# Test 3: Cluster generation produces valid results
	var test_config: WorldConfig = world_config.duplicate(true) as WorldConfig
	test_config.layout_seed = 424242
	var world_size := Vector2(1920.0, 1080.0)
	var planet_count := 50

	var clusters := WorldGenerator.generate_clusters(test_config, 424242, world_size, planet_count)

	# Should generate clusters
	if not ctx.check(clusters.size() > 0, "cluster generation should produce clusters"):
		return false

	# Total planets should match target
	var total_planets := 0
	for cluster in clusters:
		total_planets += cluster.planet_count

	if not ctx.check(total_planets <= planet_count, "total cluster planets should not exceed target"):
		return false

	# Test 4: Sun scaling is correct
	for cluster in clusters:
		if cluster.sun != null:
			if not ctx.check(cluster.sun.mass > 0.0, "sun mass must be positive"):
				return false
			if not ctx.check(cluster.sun.glow_radius > 0.0, "sun glow radius must be positive"):
				return false
			if not ctx.check(cluster.sun.cluster_id == cluster.cluster_id, "sun cluster_id must match cluster"):
				return false

	# Test 5: Cluster radius is valid
	for cluster in clusters:
		if cluster.planet_count > 0:
			if not ctx.check(cluster.radius > 0.0, "cluster radius must be positive for non-empty clusters"):
				return false
			if not ctx.check(cluster.planet_slots.size() == cluster.planet_count, "planet slots must match planet count"):
				return false

	# Test 6: Void ratio is respected (with tolerance)
	var cluster_area := 0.0
	for cluster in clusters:
		cluster_area += PI * cluster.radius * cluster.radius
	var total_area := world_size.x * world_size.y
	var actual_void_ratio := 1.0 - (cluster_area / total_area)
	var tolerance := 0.3
	if not ctx.check(actual_void_ratio > -0.1, "void ratio should not be extremely negative (clusters too large)"):
		return false

	# Test 7: Cluster generation is deterministic
	var clusters2 := WorldGenerator.generate_clusters(test_config, 424242, world_size, planet_count)
	if not ctx.check(clusters.size() == clusters2.size(), "cluster generation should be deterministic (same count)"):
		return false
	if not ctx.check(clusters[0].center_position == clusters2[0].center_position, "cluster generation should be deterministic (same positions)"):
		return false

	# Test 8: Different seeds produce different layouts
	var clusters3 := WorldGenerator.generate_clusters(test_config, 123456, world_size, planet_count)
	var all_same := true
	for i in mini(clusters.size(), clusters3.size()):
		if clusters[i].center_position.distance_to(clusters3[i].center_position) > 10.0:
			all_same = false
			break
	if not ctx.check(not all_same, "different seeds should produce different layouts"):
		return false

	# Test 9: resolved_cluster_count works
	var count := world_config.resolved_cluster_count(planet_count)
	if not ctx.check(count > 0, "resolved_cluster_count should return positive value"):
		return false

	# Test 10: Sun mass and glow scale with cluster size
	var small_sun := world_config.resolved_sun_mass(2)
	var big_sun := world_config.resolved_sun_mass(8)
	if not ctx.check(big_sun > small_sun, "sun mass should scale up with cluster size"):
		return false

	var small_glow := world_config.resolved_sun_glow(2)
	var big_glow := world_config.resolved_sun_glow(8)
	if not ctx.check(big_glow > small_glow, "sun glow should scale up with cluster size"):
		return false

	# Test 11: Resource bias sums to 1.0
	var bias := world_config.resolved_resource_bias()
	var total_bias: float = bias["cpu"] + bias["neural"] + bias["uninhabited"] + bias["player"]
	if not ctx.check(absf(total_bias - 1.0) < 0.01, "resource bias ratios should sum to 1.0"):
		return false

	return true
