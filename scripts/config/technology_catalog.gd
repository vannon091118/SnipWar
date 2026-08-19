@tool
class_name TechnologyCatalog
extends Resource

@export var technologies: Array[TechnologyDefinition] = []

func resolve(technology_id: StringName) -> TechnologyDefinition:
	for technology in technologies:
		if technology != null and technology.id == technology_id:
			return technology
	return null

func resolve_all() -> Array[TechnologyDefinition]:
	var result: Array[TechnologyDefinition] = []
	for technology in technologies:
		if technology != null:
			result.append(technology)
	return result

func for_category(category: StringName) -> Array[TechnologyDefinition]:
	var result: Array[TechnologyDefinition] = []
	for technology in technologies:
		if technology != null and technology.category == category:
			result.append(technology)
	return result

func can_research(researched_ids: Array, technology_id: StringName) -> bool:
	if researched_ids.has(technology_id):
		return false
	var technology := resolve(technology_id)
	if technology == null:
		return false
	if not String(technology.prerequisite_tech_id).is_empty() and not researched_ids.has(technology.prerequisite_tech_id):
		return false
	return true

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if technologies.is_empty():
		errors.append("technology catalog is empty")
		return errors
	var ids: Dictionary = {}
	for technology in technologies:
		if technology == null:
			errors.append("technology catalog contains a null entry")
			continue
		errors.append_array(technology.validate())
		if ids.has(technology.id):
			errors.append("duplicate technology id: %s" % technology.id)
		ids[technology.id] = true
	for technology in technologies:
		if technology == null:
			continue
		if not String(technology.prerequisite_tech_id).is_empty() and not ids.has(technology.prerequisite_tech_id):
			errors.append("technology %s references unknown prerequisite %s" % [technology.id, technology.prerequisite_tech_id])
	return errors
