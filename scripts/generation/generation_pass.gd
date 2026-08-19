@tool
class_name GenerationPass
extends Resource

## Abstract base for a generation pass in the WorldGenerationPipeline.
## Subclass this and override generate() to add new placement types.
##
## Passes execute in registration order. Earlier passes populate the ChunkGrid;
## later passes can query it for spatial constraints (exclusion zones, dependencies).
##
## Adding a new world generation type:
##   1. Create a new script extending GenerationPass
##   2. Override generate() — read rules, use ctx.rng for deterministic rolls
##   3. Register it in WorldGenerationConfig.passes

## Display name for editor/debug.
@export var pass_name: String = "UnnamedPass"

## Execution order hint (lower = earlier). Pipeline sorts by this before running.
@export var order: int = 0

## If true, this pass is skipped during pipeline execution.
@export var disabled: bool = false

## Override in subclasses: produce placements from the context.
## Must be deterministic for the same seed.
func generate(_ctx: GenerationContext) -> Array[Placement]:
	# Default: no placements.
	return []
