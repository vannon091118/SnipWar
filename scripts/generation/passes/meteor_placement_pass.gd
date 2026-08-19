@tool
class_name MeteorPlacementPass
extends GenerationPass

## Generation pass that places meteor decorations deterministically.
## Uses the same percentage-based PlacementRule pattern as DecorationPass,
## but reads from MeteorConfig to determine meteor properties.
## Later extensions can add different meteor types (ice, volcanic, etc.)
## by adding new PlacementRule entries.

## Rules for meteor variant selection.
@export var meteor_rules: Array[PlacementRule] = []

## Number of candidate positions to test per chunk.
@export_range(4, 256, 1) var candidates_per_chunk: int = 32

## Minimum distance from any planet.
@export_range(0.0, 500.0, 5.0) var planet_exclusion_distance: float = 60.0

## Minimum distance between meteors of the same type.
@export_range(0.0, 500.0, 5.0) var meteor_type_distance: float = 20.0

func _init() -> void:
	pass_name = "MeteorPlacement"
	order = 60

func generate(ctx: GenerationContext) -> Array[Placement]:
	var placements: Array[Placement] = []
	var config: WorldConfig = ctx.world_config
	if config == null:
		return placements
	if meteor_rules.is_empty():
		return placements

	var world_size := config.design_size
	if world_size.x <= 0.0 or world_size.y <= 0.0:
		return placements

	# Generate meteors across all chunks.
	var chunk_size: Vector2 = ctx.chunk_grid.chunk_size
	var min_chunk := Placement.compute_chunk_coord(Vector2.ZERO, chunk_size)
	var max_chunk := Placement.compute_chunk_coord(world_size, chunk_size)

	for cx in range(min_chunk.x, max_chunk.x + 1):
		for cy in range(min_chunk.y, max_chunk.y + 1):
			var chunk_coord := Vector2i(cx, cy)
			var chunk_rng := ctx.rng_for_chunk(chunk_coord)

			for rule: PlacementRule in meteor_rules:
				if rule == null:
					continue

				var rule_rng := ctx.rng_for_context(StringName("%s_%d_%d" % [rule.asset_id, cx, cy]))

				for _i in candidates_per_chunk:
					# Random position within chunk bounds.
					var chunk_origin := Vector2(
						float(chunk_coord.x) * chunk_size.x,
						float(chunk_coord.y) * chunk_size.y
					)
					var candidate_pos := chunk_origin + Vector2(
						rule_rng.randf() * chunk_size.x,
						rule_rng.randf() * chunk_size.y
					)

					# Skip if outside world bounds.
					if candidate_pos.x < 0.0 or candidate_pos.x > world_size.x:
						continue
					if candidate_pos.y < 0.0 or candidate_pos.y > world_size.y:
						continue
					# Enforce padding.
					if candidate_pos.x < config.padding or candidate_pos.x > world_size.x - config.padding:
						continue
					if candidate_pos.y < config.padding or candidate_pos.y > world_size.y - config.padding:
						continue

					# Planet exclusion.
					if planet_exclusion_distance > 0.0 and ctx.chunk_grid.has_nearby_type(
						candidate_pos, &"planet", planet_exclusion_distance
					):
						continue

					# Same-type exclusion.
					if meteor_type_distance > 0.0 and rule.min_distance > 0.0:
						var effective_dist: float = maxf(rule.min_distance, meteor_type_distance)
						if ctx.chunk_grid.has_nearby_type(candidate_pos, rule.asset_id, effective_dist):
							continue

					# Probability roll.
					if not rule.evaluate_roll(rule_rng):
						continue

					var scale := rule.resolve_scale(rule_rng)
					var placement := Placement.new()
					placement.placement_id = StringName("%s_%d_%d" % [rule.asset_id, cx, cy])
					placement.position = candidate_pos
					placement.placement_type = &"meteor"
					placement.asset_id = rule.asset_id
					placement.radius = rule.radius * scale
					placement.priority = rule.priority
					placement.lod_textures = rule.lod_textures.duplicate()
					placement.lod_scales = rule.lod_scales.duplicate()
					placement.metadata = {
						"scale": scale,
						"speed": rule_rng.randf_range(0.5, 2.0),
						"angular_speed": rule_rng.randf_range(-0.5, 0.5),
					}
					placements.append(placement)

	return placements
