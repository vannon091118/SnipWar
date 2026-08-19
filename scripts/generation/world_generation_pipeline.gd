@tool
class_name WorldGenerationPipeline
extends RefCounted

## Orchestrates ordered GenerationPass execution.
## Collects all placements into the ChunkGrid for chunk-based loading.
##
## Usage:
##   var ctx := GenerationContext.new()
##   ctx.set_seed(world_config.layout_seed)
##   ctx.world_config = world_config
##   ctx.expanded_catalog = catalog
##   ctx.size_profiles = profiles
##   var pipeline := WorldGenerationPipeline.new()
##   pipeline.configure(passes)
##   pipeline.execute(ctx)
##   # ctx.chunk_grid now contains all placements

var _passes: Array[GenerationPass] = []

## Register passes (replaces any prior list).
func configure(passes: Array) -> void:
	_passes.clear()
	for p: GenerationPass in passes:
		if p != null:
			_passes.append(p)
	# Sort by order hint.
	_passes.sort_custom(_sort_by_order)

## Execute all enabled passes in order.
func execute(ctx: GenerationContext) -> void:
	if ctx == null:
		return
	ctx.chunk_grid.clear()
	ctx.all_placements.clear()

	for pass_obj: GenerationPass in _passes:
		if pass_obj.disabled:
			continue
		var new_placements: Array[Placement] = pass_obj.generate(ctx)
		for placement: Placement in new_placements:
			if placement == null:
				continue
			# Assign chunk coord if not already set.
			if ctx.chunk_grid.chunk_size.x > 0.0:
				placement.chunk_coord = Placement.compute_chunk_coord(
					placement.position, ctx.chunk_grid.chunk_size
				)
			ctx.chunk_grid.insert(placement)
			ctx.all_placements.append(placement)

## Number of registered passes (including disabled).
func pass_count() -> int:
	return _passes.size()

## Number of enabled passes.
func enabled_pass_count() -> int:
	var count := 0
	for p: GenerationPass in _passes:
		if not p.disabled:
			count += 1
	return count

## Get pass by index (for debugging).
func get_pass(index: int) -> GenerationPass:
	if index >= 0 and index < _passes.size():
		return _passes[index]
	return null

static func _sort_by_order(a: GenerationPass, b: GenerationPass) -> bool:
	return a.order < b.order
