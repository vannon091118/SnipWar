@tool
class_name PlanetCatalog
extends Resource

@export var planets: Array[PlanetDefinition] = []

func definition_for(planet_id: StringName) -> PlanetDefinition:
	for definition in planets:
		if definition != null and definition.planet_id == planet_id:
			return definition
	return null

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if planets.is_empty():
		errors.append("planet catalog is empty")

	var planet_ids: Dictionary = {}
	var display_names: Dictionary = {}
	var detail_profiles: Dictionary = {}
	for definition in planets:
		if definition == null:
			errors.append("planet catalog contains a null definition")
			continue
		for definition_error in definition.validate():
			errors.append("planet %s: %s" % [definition.planet_id, definition_error])
		if planet_ids.has(definition.planet_id):
			errors.append("planet definition ids must be unique")
		planet_ids[definition.planet_id] = true
		if display_names.has(definition.display_name):
			errors.append("planet display names must be unique")
		display_names[definition.display_name] = true
		if definition.detail_profile != null:
			if not detail_profiles.has(definition.detail_profile.id):
				for profile_error in definition.detail_profile.validate():
					errors.append("detail profile %s: %s" % [definition.detail_profile.id, profile_error])
				detail_profiles[definition.detail_profile.id] = true
	return errors
