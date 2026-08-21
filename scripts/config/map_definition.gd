@tool
class_name MapDefinition
extends Resource

@export var id: StringName
@export var display_name: String
@export var world_config: WorldConfig
@export var size_profiles: Array[PlanetSizeProfile] = []
@export var navigation_config: NavigationConfig
@export var resource_pool: ResourcePool

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("map definition id is empty")
	if display_name.is_empty():
		errors.append("map definition display_name is empty")
	if world_config == null:
		errors.append("map definition world_config is missing")
	if navigation_config == null:
		errors.append("map definition navigation_config is missing")
	if world_config == null:
		return errors

	var planet_count := world_config.target_planet_count
	if world_config.is_infinite_world():
		planet_count = world_config.chunk_size * world_config.chunk_size
	elif planet_count <= 0:
		errors.append("map definition world target_planet_count must be positive")
	for world_error in world_config.validate_for_planet_count(planet_count):
		errors.append("map world: " + world_error)
	for profile_error in world_config.validate_profiles(size_profiles):
		errors.append("map profiles: " + profile_error)
	if navigation_config != null:
		for navigation_error in navigation_config.validate():
			errors.append("map navigation: " + navigation_error)
	if resource_pool != null:
		for resource_error in resource_pool.validate():
			errors.append("map resources: " + resource_error)
	return errors
