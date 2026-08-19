@tool
class_name ShipPartCatalog
extends Resource

@export var parts: Array[ShipPartDefinition] = []
@export_range(0, 8, 1) var max_module_slots: int = 2

func resolve(part_id: StringName) -> ShipPartDefinition:
	for part in parts:
		if part != null and part.id == part_id:
			return part
	return null

func for_slot(slot_type: StringName) -> Array[ShipPartDefinition]:
	var result: Array[ShipPartDefinition] = []
	for part in parts:
		if part != null and part.slot_type == slot_type:
			result.append(part)
	return result

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if parts.is_empty():
		errors.append("ship part catalog is empty")
		return errors
	var ids: Dictionary = {}
	for part in parts:
		if part == null:
			errors.append("ship part catalog contains a null entry")
			continue
		errors.append_array(part.validate())
		if ids.has(part.id):
			errors.append("duplicate ship part id: %s" % part.id)
		ids[part.id] = true
	if max_module_slots < 0:
		errors.append("ship part catalog max_module_slots cannot be negative")
	return errors
