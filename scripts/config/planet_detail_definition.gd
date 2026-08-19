@tool
class_name PlanetDetailDefinition
extends Resource

@export var id: StringName
@export var node_name_prefix: String
@export var orbit_radius_range: Vector2
@export var angular_speed_range: Vector2
@export var phase_range: Vector2
@export var sprite_size_range: Vector2
@export_range(1, 100, 1) var instance_count: int = 1
@export var textures: Array[Texture2D] = []

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("planet detail definition id is empty")
	if node_name_prefix.is_empty():
		errors.append("planet detail node_name_prefix is empty")
	if orbit_radius_range.x < 0.0 or orbit_radius_range.y < orbit_radius_range.x:
		errors.append("planet detail orbit_radius_range is invalid")
	if not is_finite(angular_speed_range.x) or not is_finite(angular_speed_range.y) or angular_speed_range.y < angular_speed_range.x:
		errors.append("planet detail angular_speed_range is invalid")
	if phase_range.y < phase_range.x:
		errors.append("planet detail phase_range is invalid")
	if sprite_size_range.x <= 0.0 or sprite_size_range.y < sprite_size_range.x:
		errors.append("planet detail sprite_size_range is invalid")
	if instance_count < 1:
		errors.append("planet detail instance_count must be positive")
	if textures.is_empty():
		errors.append("planet detail textures are missing")
	for texture in textures:
		if texture == null:
			errors.append("planet detail contains a null texture")
	return errors
