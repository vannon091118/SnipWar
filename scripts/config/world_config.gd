@tool
class_name WorldConfig
extends Resource

const ROUTE_MODE_ALL_PLANETS := "all_planets"
const ROUTE_MODE_NEIGHBORS_ONLY := "neighbors_only"

@export var design_size: Vector2
@export var layout_seed: int
@export var decorative_seed: int
# 0 = derive the column count from design_size aspect ratio and planet count.
@export_range(0, 128, 1) var columns: int
@export_range(0, 100000, 1) var target_planet_count: int = 0
# Absolute size-class floors; used when the matching ratio below is zero.
@export_range(0, 20, 1) var extra_large_count: int
@export_range(0, 20, 1) var large_count: int
# Percentage size-class targets; when > 0 they override the absolute counts above.
@export_range(0.0, 1.0, 0.01) var extra_large_ratio: float = 0.0
@export_range(0.0, 1.0, 0.01) var large_ratio: float = 0.0
@export_range(0.0, 0.4, 0.01) var jitter: float
@export_range(0.0, 160.0, 1.0) var padding: float
@export_range(0.0, 160.0, 1.0) var meteor_edge_margin: float
@export var extra_large_profile_id: StringName
@export var large_profile_id: StringName
@export var default_profile_id: StringName
@export_enum("all_planets", "neighbors_only") var route_mode: String = ROUTE_MODE_ALL_PLANETS

func meteor_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, design_size)

func resolved_columns(planet_count: int) -> int:
	if columns > 0:
		return columns
	if planet_count <= 0 or design_size.x <= 0.0 or design_size.y <= 0.0:
		return 1
	# Fit the grid to the world aspect ratio: columns/rows ~ width/height.
	var aspect := design_size.x / design_size.y
	return maxi(1, int(round(sqrt(float(planet_count) * aspect))))

func resolved_size_class_counts(planet_count: int) -> Vector2i:
	var resolved_extra_large: int
	var resolved_large: int
	if extra_large_ratio > 0.0 or large_ratio > 0.0:
		resolved_extra_large = mini(planet_count, int(round(float(planet_count) * extra_large_ratio)))
		resolved_large = mini(maxi(0, planet_count - resolved_extra_large), int(round(float(planet_count) * large_ratio)))
	else:
		resolved_extra_large = mini(extra_large_count, planet_count)
		resolved_large = mini(large_count, maxi(0, planet_count - resolved_extra_large))
	return Vector2i(resolved_extra_large, resolved_large)

func validate_for_planet_count(planet_count: int) -> PackedStringArray:
	var errors := PackedStringArray()
	if design_size.x <= 0.0 or design_size.y <= 0.0:
		errors.append("world design_size must be positive")
	if columns < 0:
		errors.append("world columns cannot be negative")
	if planet_count < 1:
		errors.append("world must contain at least one planet")
	if target_planet_count < 0:
		errors.append("world target_planet_count cannot be negative")
	if extra_large_count < 0 or large_count < 0:
		errors.append("world size class counts cannot be negative")
	if extra_large_ratio < 0.0 or extra_large_ratio > 1.0 or large_ratio < 0.0 or large_ratio > 1.0:
		errors.append("world size class ratios must stay between zero and one")
	if extra_large_ratio + large_ratio > 1.0:
		errors.append("world size class ratios cannot exceed one")
	if extra_large_ratio == 0.0 and large_ratio == 0.0 and extra_large_count + large_count > planet_count:
		errors.append("world size class counts exceed the planet count")
	if jitter < 0.0 or jitter > 0.4:
		errors.append("world jitter must stay between zero and 0.4")
	if padding < 0.0:
		errors.append("world padding cannot be negative")
	if padding * 2.0 >= design_size.x or padding * 2.0 >= design_size.y:
		errors.append("world padding leaves no usable layout area")
	if meteor_edge_margin < 0.0:
		errors.append("meteor edge margin cannot be negative")
	if route_mode != ROUTE_MODE_ALL_PLANETS and route_mode != ROUTE_MODE_NEIGHBORS_ONLY:
		errors.append("world route_mode is invalid")
	return errors

func validate_profiles(profiles: Array[PlanetSizeProfile]) -> PackedStringArray:
	var errors := PackedStringArray()
	var profile_ids: Dictionary = {}
	for profile in profiles:
		if profile == null:
			errors.append("world contains a null planet size profile")
			continue
		for profile_error in profile.validate():
			errors.append("planet size profile %s: %s" % [profile.id, profile_error])
		if profile_ids.has(profile.id):
			errors.append("world planet size profile ids must be unique")
		profile_ids[profile.id] = true
	for required_id in [extra_large_profile_id, large_profile_id, default_profile_id]:
		if not profile_ids.has(required_id):
			errors.append("world is missing planet size profile %s" % required_id)
	return errors
