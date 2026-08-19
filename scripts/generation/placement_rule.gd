@tool
class_name PlacementRule
extends Resource

## A percentage-based rule for deterministic world asset generation.
## Defines how likely an asset is to appear, with optional count bounds
## and spatial constraints. Used by GenerationPass implementations.

## Asset identifier this rule produces.
@export var asset_id: StringName = &""

## Probability per eligible position (0.0–1.0). A roll below this threshold = placed.
@export_range(0.0, 1.0, 0.01) var probability: float = 1.0

## Minimum count to place (even if probability rolls fail, up to min_count are forced).
@export_range(0, 1000, 1) var min_count: int = 0

## Maximum count to place (-1 = unlimited).
@export_range(-1, 1000, 1) var max_count: int = -1

## Weight for weighted selection when multiple rules compete for the same slot.
@export_range(0.0, 1000.0, 0.1) var weight: float = 1.0

## Minimum distance from any existing placement of the same type.
@export_range(0.0, 10000.0, 1.0) var min_distance: float = 0.0

## LOD asset variants: maps LodLevel.Level integer → Texture2D.
var lod_textures: Dictionary = {}

## LOD scale factors: maps LodLevel.Level integer → float.
var lod_scales: Dictionary = {}

## Scale range for this placement (x = min, y = max).
@export var scale_range: Vector2 = Vector2.ONE

## Bounding radius in pixels.
@export_range(1.0, 5000.0, 1.0) var radius: float = 50.0

## Render priority.
@export var priority: int = 0

## Required nearby asset types (placement depends on these existing nearby).
@export var required_nearby_types: Array[StringName] = []

## Forbidden nearby asset types (exclusion zone).
@export var forbidden_nearby_types: Array[StringName] = []

## Minimum distance from placements with any of these types.
@export var exclusion_types: Array[StringName] = []

## Minimum distance from placements with any of these types.
@export_range(0.0, 10000.0, 1.0) var exclusion_distance: float = 0.0

func evaluate_roll(rng: RandomNumberGenerator) -> bool:
	return rng.randf() < probability

func resolve_scale(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(scale_range.x, scale_range.y)

func max_count_reached(current_count: int) -> bool:
	return max_count >= 0 and current_count >= max_count

func min_count_not_met(current_count: int) -> bool:
	return current_count < min_count

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(asset_id).is_empty():
		errors.append("placement rule asset_id is empty")
	if probability < 0.0 or probability > 1.0:
		errors.append("placement rule probability must be between 0.0 and 1.0")
	if min_count < 0:
		errors.append("placement rule min_count cannot be negative")
	if max_count < -1:
		errors.append("placement rule max_count must be -1 or non-negative")
	if max_count >= 0 and min_count > max_count:
		errors.append("placement rule min_count exceeds max_count")
	if weight < 0.0:
		errors.append("placement rule weight cannot be negative")
	if scale_range.x <= 0.0 or scale_range.y < scale_range.x:
		errors.append("placement rule scale_range is invalid")
	if radius <= 0.0:
		errors.append("placement rule radius must be positive")
	return errors
