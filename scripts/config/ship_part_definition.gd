@tool
class_name ShipPartDefinition
extends Resource

const SLOT_HULL := &"hull"
const SLOT_DRIVE := &"drive"
const SLOT_WEAPON := &"weapon"
const SLOT_SHIELD := &"shield"
const SLOT_SCANNER := &"scanner"
const SLOT_UTILITY := &"utility"
# Compatibility alias for older module-based assemblies/resources.
const SLOT_MODULE := SLOT_UTILITY
const LEGACY_SLOT_MODULE := &"module"

@export var id: StringName = &""
@export var slot_type: StringName = SLOT_HULL
@export var display_name: String = ""
@export var description: String = ""
@export var cost_resource: StringName = &"material"
@export var cost_amount: int = 5
@export_range(1, 3, 1) var tier: int = 1
@export var visual_asset: Texture2D
@export var trait_definition: TraitDefinition
@export var variant_pool: Array[ShipComponentVariant] = []
# Empty = always purchasable; otherwise the owning faction needs this research.
@export var required_tech_id: StringName = &""
@export_range(0.0, 3600.0, 0.1) var build_time: float = 0.0

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("ship part id is empty")
	if slot_type != SLOT_HULL and slot_type != SLOT_DRIVE and slot_type != SLOT_WEAPON and slot_type != SLOT_SHIELD and slot_type != SLOT_SCANNER and not is_utility_slot(slot_type):
		errors.append("ship part %s has invalid slot_type %s" % [id, slot_type])
	if display_name.is_empty():
		errors.append("ship part %s display_name is empty" % id)
	if cost_amount < 0:
		errors.append("ship part %s cost_amount cannot be negative" % id)
	if build_time < 0.0:
		errors.append("ship part %s build_time cannot be negative" % id)
	if visual_asset == null:
		errors.append("ship part %s visual_asset is missing" % id)
	if (slot_type == SLOT_DRIVE or slot_type == SLOT_WEAPON or slot_type == SLOT_SHIELD) and trait_definition == null:
		errors.append("ship part %s requires a trait_definition for visual/stat readback" % id)
	if trait_definition != null:
		errors.append_array(trait_definition.validate())
	var variant_ids: Dictionary = {}
	for variant in variant_pool:
		if variant == null:
			errors.append("ship part %s contains a null variant" % id)
			continue
		errors.append_array(variant.validate())
		if variant_ids.has(variant.id):
			errors.append("duplicate variant id %s on ship part %s" % [variant.id, id])
		variant_ids[variant.id] = true
	return errors

static func is_utility_slot(value: StringName) -> bool:
	return value == SLOT_UTILITY or value == LEGACY_SLOT_MODULE
