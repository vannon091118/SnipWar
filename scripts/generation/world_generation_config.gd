@tool
class_name WorldGenerationConfig
extends Resource

## Top-level configuration for the world generation pipeline.
## Holds the ordered list of passes, chunk size, and LOD distances.
## Assign per-scenario to vary generation behavior.

## The generation passes in execution order.
@export var passes: Array = []

## Spatial chunk size (pixels). Chunks this × this hold placement indices.
@export var chunk_size: Vector2 = Vector2(512.0, 512.0)

## LOD distance thresholds (FULL, REDUCED, MINIMAL, CULLED transitions).
@export var lod_config: LodLevel = null

## Validation.
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if chunk_size.x <= 0.0 or chunk_size.y <= 0.0:
		errors.append("world generation chunk_size must be positive")
	for i in passes.size():
		var pass_obj: GenerationPass = passes[i]
		if pass_obj == null:
			errors.append("world generation pass at index %d is null" % i)
		elif pass_obj.pass_name.is_empty():
			errors.append("world generation pass at index %d has empty name" % i)
	if lod_config != null:
		for lod_error in lod_config.validate():
			errors.append("world generation LOD: " + lod_error)
	return errors
