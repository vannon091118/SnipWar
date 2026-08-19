@tool
class_name TechnologyDefinition
extends Resource

const CATEGORY_SHIPS := &"ships"
const CATEGORY_MECH := &"mech"
const CATEGORY_PLANET := &"planet"

@export var id: StringName = &""
@export var category: StringName = CATEGORY_SHIPS
@export var display_name: String = ""
@export var description: String = ""
@export var cost_resource: StringName = &"energy"
@export var cost_amount: int = 10
@export var prerequisite_tech_id: StringName = &""
@export var visual_asset: Texture2D
@export_group("Mechanical Effect")
@export var effect_id: StringName = &""
@export_multiline var mechanic_description: String = ""
@export_range(0.1, 10.0, 0.05) var production_multiplier: float = 1.0

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("technology id is empty")
	if display_name.is_empty():
		errors.append("technology %s display_name is empty" % id)
	if category != CATEGORY_SHIPS and category != CATEGORY_MECH and category != CATEGORY_PLANET:
		errors.append("technology %s has invalid category %s" % [id, category])
	if cost_amount < 0:
		errors.append("technology %s cost_amount cannot be negative" % id)
	if visual_asset == null:
		errors.append("technology %s visual_asset is missing" % id)
	if String(effect_id).is_empty():
		errors.append("technology %s effect_id is empty" % id)
	if mechanic_description.is_empty():
		errors.append("technology %s mechanic_description is empty" % id)
	if production_multiplier <= 0.0:
		errors.append("technology %s production_multiplier must be positive" % id)
	return errors
