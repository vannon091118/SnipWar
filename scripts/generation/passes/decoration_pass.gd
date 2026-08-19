@tool
class_name DecorationPass
extends GenerationPass

## Generation pass that places background decorations between planets.
## Uses percentage-based PlacementRules for deterministic, extensible decoration
## generation. Supports spatial constraints (exclusion zones around planets,
## minimum distances between decorations of the same type).
##
## This is the primary extension point: add new PlacementRule entries to
## add new decoration types without modifying any core code.

## Decoration rules evaluated per candidate position.
@export var rules: Array[PlacementRule] = []

## Grid subdivision for candidate positions (cells × cells).
@export_range(4, 128, 1) var candidate_grid_resolution: int = 16

## Minimum distance from any planet placement.
@export_range(0.0, 500.0, 5.0) var planet_exclusion_distance: float = 80.0

## Minimum distance between decorations of the same type.
@export_range(0.0, 500.0, 5.0) var decoration_type_distance: float = 30.0

func _init() -> void:
	pass_name = "Decoration"
	order = 50

func generate(ctx: GenerationContext) -> Array[Placement]:
	var placements: Array[Placement] = []
	var config: WorldConfig = ctx.world_config
	if config == null:
		return placements
	if rules.is_empty():
		return placements

	var world_size := config.design_size
	if world_size.x <= 0.0 or world_size.y <= 0.0:
		return placements

	# Generate candidate positions on a deterministic grid.
	var cell_size := Vector2(
		world_size.x / float(candidate_grid_resolution),
		world_size.y / float(candidate_grid_resolution)
	)

	# Sub-RNG for candidate shuffle (deterministic per world seed).
	var candidate_rng := ctx.rng_for_context(&"decoration_candidates")
	var candidate_count := candidate_grid_resolution * candidate_grid_resolution

	# Shuffle candidates to randomize which cells get decorations first.
	var candidate_indices: Array[int] = []
	for i in candidate_count:
		candidate_indices.append(i)
	_shuffle(candidate_indices, candidate_rng)

	# Track per-type counts for min/max enforcement.
	var type_counts: Dictionary = {}

	for rule: PlacementRule in rules:
		if rule == null:
			continue
		type_counts[rule.asset_id] = 0

	# Process each rule independently (percentage-based per rule).
	for rule: PlacementRule in rules:
		if rule == null:
			continue

		var rule_rng := ctx.rng_for_context(rule.asset_id)
		var placed_for_rule := 0

		for idx in candidate_count:
			if rule.max_count_reached(placed_for_rule):
				break

			var cell_idx: int = candidate_indices[idx]
			var col := cell_idx % candidate_grid_resolution
			var row := cell_idx / candidate_grid_resolution

			# Center of the cell + jitter.
			var candidate_pos := Vector2(
				(float(col) + 0.5) * cell_size.x + rule_rng.randf_range(-cell_size.x * 0.3, cell_size.x * 0.3),
				(float(row) + 0.5) * cell_size.y + rule_rng.randf_range(-cell_size.y * 0.3, cell_size.y * 0.3)
			)

			# Enforce world bounds.
			if candidate_pos.x < config.padding or candidate_pos.x > world_size.x - config.padding:
				continue
			if candidate_pos.y < config.padding or candidate_pos.y > world_size.y - config.padding:
				continue

			# Exclusion zone: too close to a planet?
			if planet_exclusion_distance > 0.0 and ctx.chunk_grid.has_nearby_type(
				candidate_pos, &"planet", planet_exclusion_distance
			):
				continue

			# Exclusion zone: too close to same-type decoration?
			if decoration_type_distance > 0.0 and rule.min_distance > 0.0:
				var effective_distance: float = maxf(rule.min_distance, decoration_type_distance)
				if ctx.chunk_grid.has_nearby_type(candidate_pos, rule.asset_id, effective_distance):
					continue

			# Required nearby check.
			if not rule.required_nearby_types.is_empty():
				if not ctx.chunk_grid.has_required_nearby(
					candidate_pos, rule.required_nearby_types, 200.0 * 200.0
				):
					continue

			# Forbidden nearby check.
			if not rule.forbidden_nearby_types.is_empty():
				if ctx.chunk_grid.has_forbidden_nearby(
					candidate_pos, rule.forbidden_nearby_types, 100.0 * 100.0
				):
					continue

			# Probability roll.
			if not rule.evaluate_roll(rule_rng):
				# Force-place up to min_count.
				if not rule.min_count_not_met(placed_for_rule):
					continue

			var scale := rule.resolve_scale(rule_rng)
			var placement := Placement.new()
			placement.placement_id = StringName("%s_d%d_%d" % [rule.asset_id, idx, placed_for_rule])
			placement.position = candidate_pos
			placement.placement_type = &"decoration"
			placement.asset_id = rule.asset_id
			placement.radius = rule.radius * scale
			placement.priority = rule.priority
			placement.lod_textures = rule.lod_textures.duplicate()
			placement.lod_scales = rule.lod_scales.duplicate()
			placement.metadata = {
				"scale": scale,
				"rule_asset_id": rule.asset_id,
			}

			placements.append(placement)
			placed_for_rule += 1
			type_counts[rule.asset_id] = type_counts.get(rule.asset_id, 0) + 1

	return placements


func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = value
