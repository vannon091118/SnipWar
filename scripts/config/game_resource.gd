@tool
class_name GameResource
extends Resource

@export var id: StringName
@export var display_name: String
@export var color: Color = Color.WHITE

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("game resource id is empty")
	if display_name.is_empty():
		errors.append("game resource display_name is empty")
	return errors
