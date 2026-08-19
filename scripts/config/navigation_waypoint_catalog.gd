@tool
class_name NavigationWaypointCatalog
extends Resource

@export var definitions: Array[NavigationWaypointDefinition] = []

func definition_for_edge(edge_index: int) -> NavigationWaypointDefinition:
	if definitions.is_empty():
		return null
	var safe_index := maxi(edge_index, 0)
	for definition in definitions:
		if definition != null and safe_index % definition.every_n_edges == 0:
			return definition
	return definitions[definitions.size() - 1] as NavigationWaypointDefinition

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if definitions.is_empty():
		errors.append("navigation waypoint catalog is empty")
	var ids: Dictionary = {}
	for definition in definitions:
		if definition == null:
			errors.append("navigation waypoint catalog contains a null definition")
			continue
		for definition_error in definition.validate():
			errors.append("waypoint %s: %s" % [definition.id, definition_error])
		if ids.has(definition.id):
			errors.append("navigation waypoint definition ids must be unique")
		ids[definition.id] = true
	return errors
