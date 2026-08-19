@tool
class_name PlanetDefinition
extends Resource

@export var planet_id: StringName
@export var display_name: String
@export var planet_role: StringName = &"planet"
@export var faction: StringName = &"neutral"
@export var planet_texture: Texture2D
@export var detail_profile: PlanetDetailProfile

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(planet_id).is_empty():
		errors.append("planet definition id is empty")
	if display_name.is_empty():
		errors.append("planet definition display_name is empty")
	if planet_texture == null:
		errors.append("planet definition texture is missing")
	if detail_profile == null:
		errors.append("planet definition detail profile is missing")
	return errors
