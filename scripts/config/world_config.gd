class_name WorldConfig
extends Resource

@export var design_size: Vector2
@export var layout_seed: int
@export var decorative_seed: int
@export_range(1, 20, 1) var columns: int
@export_range(0, 20, 1) var extra_large_count: int
@export_range(0, 20, 1) var large_count: int
@export_range(0.0, 0.4, 0.01) var jitter: float
@export_range(0.0, 160.0, 1.0) var padding: float
@export_range(0.0, 160.0, 1.0) var meteor_edge_margin: float
@export var extra_large_profile_id: StringName
@export var large_profile_id: StringName
@export var default_profile_id: StringName

func meteor_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, design_size)

func validate_for_planet_count(planet_count: int) -> PackedStringArray:
	var errors := PackedStringArray()
	if design_size.x <= 0.0 or design_size.y <= 0.0:
		errors.append("world design_size must be positive")
	if columns < 1:
		errors.append("world columns must be at least one")
	if planet_count < 1:
		errors.append("world must contain at least one planet")
	if extra_large_count < 0 or large_count < 0:
		errors.append("world size class counts cannot be negative")
	if extra_large_count + large_count > planet_count:
		errors.append("world size class counts exceed the planet count")
	if jitter < 0.0 or jitter > 0.4:
		errors.append("world jitter must stay between zero and 0.4")
	if padding < 0.0:
		errors.append("world padding cannot be negative")
	if padding * 2.0 >= design_size.x or padding * 2.0 >= design_size.y:
		errors.append("world padding leaves no usable layout area")
	if meteor_edge_margin < 0.0:
		errors.append("meteor edge margin cannot be negative")
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
