@tool
class_name ShipBlueprint
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var seed_base: int = 0
@export var default_components: Dictionary = {}

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("ship blueprint id is empty")
	if display_name.is_empty():
		errors.append("ship blueprint %s display_name is empty" % id)
	return errors
