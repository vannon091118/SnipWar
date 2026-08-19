@tool
class_name LodLevel
extends RefCounted

## LOD (Level of Detail) thresholds and helpers.
## Used by ChunkGrid and LodManager to decide asset fidelity by distance.

enum Level {
	FULL = 0,    ## All details, animations running
	REDUCED = 1, ## Simplified sprite, throttled animation
	MINIMAL = 2, ## Icon/silhouette only, no animation
	CULLED = 3,  ## Not rendered at all
}

const LEVEL_NAMES: Dictionary = {
	Level.FULL: &"full",
	Level.REDUCED: &"reduced",
	Level.MINIMAL: &"minimal",
	Level.CULLED: &"culled",
}

## Distance thresholds for each LOD transition (pixels).
## Index 0 = FULL↔REDUCED, 1 = REDUCED↔MINIMAL, 2 = MINIMAL↔CULLED.
@export var distance_thresholds: Vector3 = Vector3(200.0, 500.0, 1000.0)

func resolve_level(distance: float) -> Level:
	if distance < distance_thresholds.x:
		return Level.FULL
	if distance < distance_thresholds.y:
		return Level.REDUCED
	if distance < distance_thresholds.z:
		return Level.MINIMAL
	return Level.CULLED

func level_name(level: Level) -> StringName:
	return LEVEL_NAMES.get(level, &"culled") as StringName

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if distance_thresholds.x < 0.0:
		errors.append("LOD FULL threshold cannot be negative")
	if distance_thresholds.y < distance_thresholds.x:
		errors.append("LOD REDUCED threshold must be >= FULL threshold")
	if distance_thresholds.z < distance_thresholds.y:
		errors.append("LOD MINIMAL threshold must be >= REDUCED threshold")
	return errors
