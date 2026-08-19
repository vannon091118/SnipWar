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
	if technology.is_blocked_by_exclusion(researched_ids):
		return false
	return true

## Returns the mutually exclusive peer of technology_id, or empty if none.
func get_exclusion_peer(technology_id: StringName) -> StringName:
	var technology := resolve(technology_id)
	if technology == null:
		return &""
	return technology.mutually_exclusive_with

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
		if not String(technology.mutually_exclusive_with).is_empty():
			if not ids.has(technology.mutually_exclusive_with):
				errors.append("technology %s references unknown exclusion %s" % [technology.id, technology.mutually_exclusive_with])
			else:
				var peer: TechnologyDefinition = resolve(technology.mutually_exclusive_with)
				if peer != null and not String(peer.mutually_exclusive_with).is_empty() and peer.mutually_exclusive_with != technology.id:
					errors.append("technology %s exclusion mismatch: %s excludes %s, not %s" % [technology.id, technology.id, peer.mutually_exclusive_with, technology.mutually_exclusive_with])
	return errors
