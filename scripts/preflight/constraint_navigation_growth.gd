class_name PreflightConstraintNavigationGrowth
extends RefCounted

## WorldConfig growth contract (sqrt-scaled design_size, scaled target_planet_count),
## K-nearest graph neighbour builder, and immutability of authored .tres files
## at runtime. Runs without scene boot so it stays deterministic in the
## persistent preflight pipeline.

func constraint_name() -> String:
	return "navigation_growth"

func requires_scene() -> bool:
	return false


func run(ctx: PreflightContext) -> bool:
	var base_config: WorldConfig = preload("res://resources/config/world_default.tres")
	var base_catalog: PlanetCatalog = preload("res://resources/config/planet_catalog.tres")

	# --- resolved_design_size: 1.0 keeps authored size, sqrt-scaling otherwise.
	var identity_size: Vector2 = base_config.resolved_design_size()
	if not ctx.check(identity_size == base_config.design_size, "growth=1.0 design_size resolution drifted"):
		return false
	var grown := base_config.duplicate(true) as WorldConfig
	grown.growth_factor = 4.0
	var grown_size: Vector2 = grown.resolved_design_size()
	if not ctx.check(grown_size.x == base_config.design_size.x * 2.0 and grown_size.y == base_config.design_size.y * 2.0, "growth=4.0 design_size should double both axes (got %s)" % grown_size):
		return false

	# --- resolved_target_planet_count: linear scaling with growth and base size.
	var grown_count_target: int = grown.resolved_target_planet_count(10)
	if not ctx.check(grown_count_target == 40, "growth=4.0 target_planet_count should be 40"):
		return false
	if not ctx.check(grown.resolved_target_planet_count(0) == grown.target_planet_count, "missing base count should fall back to authored target_planet_count"):
		return false

	# --- WorldGenerator.grid_cell_positions uses the resolved design_size, not
	# the authored one. With a 4× area the cell positions must move outward.
	var authored_cells := WorldGenerator.grid_cell_positions(grown, 40)
	var flat_cells: Array[Vector2] = authored_cells as Array[Vector2]
	if not ctx.check(flat_cells.size() == 40, "growth-aware grid missing 40 cells"):
		return false
	var max_x: float = 0.0
	var max_y: float = 0.0
	for cell in flat_cells:
		if cell.x > max_x:
			max_x = cell.x
		if cell.y > max_y:
			max_y = cell.y
	# grown: columns auto-resolve to ~14 for 40 planets in 2:1 world (sqrt(40*2)=~9 in 4×).
	# We just assert that the maximum cell lands past the authored default bounds.
	if not ctx.check(max_x > base_config.design_size.x + 200.0 and max_y > base_config.design_size.y + 100.0, "growth-aware cells did not grow outward (max_x=%f max_y=%f)" % [max_x, max_y]):
		return false

	# --- resolve_runtime_world: authored file stays clean.
	var runtime_world: WorldConfig = WorldGenerator.resolve_runtime_world(base_config, base_catalog)
	if runtime_world == null:
		if not ctx.check(false, "resolve_runtime_world returned null for valid input"):
			return false
		return false
	if not ctx.check(runtime_world != base_config, "resolve_runtime_world should be a duplicate, not the authored resource"):
		return false
	if not ctx.check(runtime_world.growth_factor == base_config.growth_factor, "runtime duplicate lost growth_factor"):
		return false
	if not ctx.check(runtime_world.layout_seed == base_config.layout_seed, "layout_seed should propagate into the runtime duplicate"):
		return false
	# Authored immutability: the deep duplicate must not share reference-equal
	# sub-objects that we mutate, so a runtime change must NOT leak into the
	# authored .tres. Mutate the duplicate and reassert the original.
	var initial_authored_seed: int = base_config.layout_seed
	runtime_world.layout_seed = 99999
	if not ctx.check(base_config.layout_seed == initial_authored_seed, "runtime duplicate leaked layout_seed back into the authored file"):
		return false

	# --- K-nearest edge builder: deterministic, dedup, respects ratio + cap.
	var stand_ins := _build_stand_in_planets(5, [Vector2(0, 0), Vector2(80, 0), Vector2(160, 0), Vector2(0, 200), Vector2(160, 200)])
	# k = ceil((5-1)*0.5) = 2 neighbours per source. With this geometry each
	# plane constraint (top-2 by distance, then by index) yields 6 unique dedup
	# pairs: every source contributes 2 outgoing, but symmetric duplicates are
	# collapsed. The exact count is the deterministic, observable behaviour.
	var direct_edges := WorldGenerator.build_knn_edges(stand_ins, 0.5, 0, [])
	var direct_count: int = direct_edges.size()
	if not ctx.check(direct_count == 6, "K-nearest ratio=0.5 edges expected 6 dedup pairs for the stand-in layout (got %d)" % direct_count):
		return false
	var expected_pairs: Array = [
		[stand_ins[0], stand_ins[1]],
		[stand_ins[0], stand_ins[2]],
		[stand_ins[1], stand_ins[2]],
		[stand_ins[0], stand_ins[3]],
		[stand_ins[2], stand_ins[4]],
		[stand_ins[3], stand_ins[4]],
	]
	var expected_unmatched: int = expected_pairs.size()
	for entry in direct_edges:
		var matched := false
		for expected_index in expected_pairs.size():
			var expected: Array = expected_pairs[expected_index]
			if _same_node_pair(entry[0], entry[1], expected[0], expected[1]):
				expected_pairs.remove_at(expected_index)
				matched = true
				break
		if not matched:
			if not ctx.check(false, "unexpected K-nearest pair %s-%s" % [_position_label(entry[0]), _position_label(entry[1])]):
				return false
	if not ctx.check(expected_pairs.is_empty(), "K-nearest dropped %d expected pairs" % expected_pairs.size()):
		return false

	# Edge cap clamps the running total regardless of ratio.
	var cap_two := WorldGenerator.build_knn_edges(stand_ins, 0.5, 2, [])
	if not ctx.check(cap_two.size() == 2, "K-nearest edge cap should clamp total to 2 (got %d)" % cap_two.size()):
		return false

	# Excluding a grid edge must forbid the K-nearest layer from re-recording it.
	var grid_pair: Array = [stand_ins[0], stand_ins[1]]
	var with_grid := WorldGenerator.build_knn_edges(stand_ins, 1.0, 0, [grid_pair])
	var found_grid_in_knn: bool = false
	for entry in with_grid:
		if (entry[0] == grid_pair[0] and entry[1] == grid_pair[1]) or (entry[0] == grid_pair[1] and entry[1] == grid_pair[0]):
			found_grid_in_knn = true
			break
	if not ctx.check(not found_grid_in_knn, "K-nearest layer must dedup grid edges"):
		return false

	# Determinism: a repeated call with identical inputs must yield the same
	# edge set ordered identically.
	var first_run := WorldGenerator.build_knn_edges(stand_ins, 0.4, 0, [])
	var second_run := WorldGenerator.build_knn_edges(stand_ins, 0.4, 0, [])
	if not ctx.check(first_run.size() == second_run.size(), "K-nearest is not stable across runs"):
		return false
	for index in first_run.size():
		if not ctx.check(first_run[index][0] == second_run[index][0] and first_run[index][1] == second_run[index][1], "K-nearest ordering drifted between runs"):
			return false

	# Zero ratio = no growth (default behaviour preserved for tools/scenarios).
	var zero_ratio := WorldGenerator.build_knn_edges(stand_ins, 0.0, 0, [])
	if not ctx.check(zero_ratio.is_empty(), "K-nearest with ratio=0 should return no edges"):
		return false

	# --- NavigationConfig inheritance: ratio=-1 falls through to WorldConfig.
	var nav: NavigationConfig = preload("res://resources/config/navigation_default.tres")
	var inherited_ratio: float = nav.resolved_graph_neighbor_ratio(base_config)
	if not ctx.check(inherited_ratio == base_config.resolved_graph_neighbor_ratio(), "NavigationConfig.graph_neighbor_ratio<0 should inherit WorldConfig"):
		return false
	var override_nav := nav.duplicate(true) as NavigationConfig
	override_nav.graph_neighbor_ratio = 0.25
	var override_ratio: float = override_nav.resolved_graph_neighbor_ratio(base_config)
	if not ctx.check(is_equal_approx(override_ratio, 0.25), "NavigationConfig override ratio ignored (got %f)" % override_ratio):
		return false

	# --- WorldConfig validation: bad growth inputs should fail loudly.
	var bad_growth := base_config.duplicate(true) as WorldConfig
	bad_growth.growth_factor = 0.5
	var bad_ratio := base_config.duplicate(true) as WorldConfig
	bad_ratio.graph_neighbor_ratio = 0.6
	bad_ratio.growth_factor = 1.0
	if not ctx.check(not bad_growth.validate_for_planet_count(10).is_empty(), "growth_factor<1.0 should fail validation"):
		return false
	if not ctx.check(not bad_ratio.validate_for_planet_count(10).is_empty(), "graph_neighbor_ratio>0.5 should fail validation"):
		return false

	return true


## Builds an Array[Node2D] stand-in (one Node2D per layout coordinate). Lives
## off-tree so NavigationField never sees them — the K-nearest builder only
## cares about Node2D.global_position.
func _build_stand_in_planets(_dummy_count: int, positions: Array) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for index in positions.size():
		var node := Node2D.new()
		node.global_position = positions[index]
		result.append(node)
	return result


func _same_node_pair(first_a: Node2D, second_a: Node2D, first_b: Node2D, second_b: Node2D) -> bool:
	return (first_a == first_b and second_a == second_b) or (first_a == second_b and second_a == first_b)


func _position_label(node: Node2D) -> String:
	return "(%.1f,%.1f)" % [node.global_position.x, node.global_position.y] 
