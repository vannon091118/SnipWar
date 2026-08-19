@tool
class_name ShipComponentVariant
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var visual_asset: Texture2D
@export var trait_modifiers: TraitDefinition
@export_range(0.0, 100.0, 0.1) var weight: float = 1.0
@export_range(1, 3, 1) var min_tier: int = 1

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("ship component variant id is empty")
	if display_name.is_empty():
		errors.append("ship component variant %s display_name is empty" % id)
	if weight < 0.0:
		errors.append("ship component variant %s weight cannot be negative" % id)
	if min_tier < 1:
		errors.append("ship component variant %s min_tier must be at least 1" % id)
	if trait_modifiers != null:
		errors.append_array(trait_modifiers.validate())
	return errors
