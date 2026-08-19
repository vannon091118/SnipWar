@tool
class_name ShipPartDefinition
extends Resource

const SLOT_HULL := &"hull"
const SLOT_SCANNER := &"scanner"
const SLOT_MODULE := &"module"
const SLOT_WEAPON := &"weapon"

@export var id: StringName = &""
@export var slot_type: StringName = SLOT_HULL
@export var display_name: String = ""
@export var description: String = ""
@export var cost_resource: StringName = &"material"
@export var cost_amount: int = 5
@export_range(1, 3, 1) var tier: int = 1
@export var visual_asset: Texture2D
@export var trait_definition: TraitDefinition
# Empty = always purchasable; otherwise the owning faction needs this research.
@export var required_tech_id: StringName = &""
@export_range(0.0, 3600.0, 0.1) var build_time: float = 0.0

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("ship part id is empty")
	if slot_type != SLOT_HULL and slot_type != SLOT_SCANNER and slot_type != SLOT_MODULE and slot_type != SLOT_WEAPON:
		errors.append("ship part %s has invalid slot_type %s" % [id, slot_type])
	if display_name.is_empty():
		errors.append("ship part %s display_name is empty" % id)
	if cost_amount < 0:
		errors.append("ship part %s cost_amount cannot be negative" % id)
	if build_time < 0.0:
		errors.append("ship part %s build_time cannot be negative" % id)
	if visual_asset == null:
		errors.append("ship part %s visual_asset is missing" % id)
	if trait_definition != null:
		errors.append_array(trait_definition.validate())
	return errors
