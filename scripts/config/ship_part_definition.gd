@tool
class_name ShipPartDefinition
extends Resource

const SLOT_HULL := &"hull"
const SLOT_SCANNER := &"scanner"
const SLOT_MODULE := &"module"

@export var id: StringName = &""
@export var slot_type: StringName = SLOT_HULL
@export var display_name: String = ""
@export var description: String = ""
@export var cost_resource: StringName = &"material"
@export var cost_amount: int = 5
@export_range(1, 3, 1) var tier: int = 1
@export var visual_asset: Texture2D
@export var trait_definition: TraitDefinition

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("ship part id is empty")
	if slot_type != SLOT_HULL and slot_type != SLOT_SCANNER and slot_type != SLOT_MODULE:
		errors.append("ship part %s has invalid slot_type %s" % [id, slot_type])
	if display_name.is_empty():
		errors.append("ship part %s display_name is empty" % id)
	if cost_amount < 0:
		errors.append("ship part %s cost_amount cannot be negative" % id)
	if visual_asset == null:
		errors.append("ship part %s visual_asset is missing" % id)
	if trait_definition != null:
		errors.append_array(trait_definition.validate())
	return errors
