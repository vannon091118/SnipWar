@tool
class_name BuildingCatalog
extends Resource

@export var buildings: Array[BuildingDefinition] = []

func resolve(id: StringName) -> BuildingDefinition:
	for building in buildings:
		if building != null and building.id == id:
			return building
	return null

func buildings_for_type(building_type: StringName) -> Array[BuildingDefinition]:
	var result: Array[BuildingDefinition] = []
	for building in buildings:
		if building != null and building.building_type == building_type:
			result.append(building)
	return result

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var ids: Dictionary = {}
	for building in buildings:
		if building == null:
			errors.append("building catalog contains a null building")
			continue
		for building_error in building.validate():
			errors.append("building %s: %s" % [building.id, building_error])
		if ids.has(building.id):
			errors.append("building ids must be unique")
		ids[building.id] = true
	return errors
