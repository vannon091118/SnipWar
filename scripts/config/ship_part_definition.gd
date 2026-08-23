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
@export var module_role: String = ""
@export var cost_resource: StringName = GameState.RES_MATERIAL
@export var cost_amount: int = 5
@export var credit_cost: int = 5
@export var workers_required: int = 1
@export_range(1, 3, 1) var tier: int = 1
@export var visual_asset: Texture2D
@export var trait_definition: TraitDefinition
@export var variant_pool: Array[ShipComponentVariant] = []
# Empty = always purchasable; otherwise the owning faction needs this research.
@export var required_tech_id: StringName = &""
@export_range(0.0, 3600.0, 0.1) var build_time: float = 0.0

@export_group("Module Damage Model")
## Base influence of this module on the ship's HP state. 0 = auto-derived
## from the slot type (hull 0.30, drive 0.20, weapon 0.20, shield 0.15,
## scanner 0.10, utility 0.05) via ModuleInfluence.base_weight().
@export_range(0.0, 1.0, 0.01) var influence_weight: float = 0.0
## Primary stat degraded when this module is destroyed. Empty = auto-derived
## from the slot type (drive → speed, weapon → dps, ...).
@export var influence_trait: StringName = &""
## Hull-defined dynamic slot layout: [{"type": &"drive", "count": 2}, ...].
## Empty on non-hull parts; empty on hulls falls back to the legacy layout
## (1 drive, 1 weapon, 1 shield, 1 scanner, catalog.max_module_slots utility).
@export var slot_schema: Array[Dictionary] = []

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
	if credit_cost < 0 or workers_required < 0:
		errors.append("ship part %s credit/worker costs cannot be negative" % id)
	if build_time < 0.0:
		errors.append("ship part %s build_time cannot be negative" % id)
	if visual_asset == null:
		errors.append("ship part %s visual_asset is missing" % id)
	if (slot_type == SLOT_DRIVE or slot_type == SLOT_WEAPON or slot_type == SLOT_SHIELD) and trait_definition == null:
		errors.append("ship part %s requires a trait_definition for visual/stat readback" % id)
	if trait_definition != null:
		errors.append_array(trait_definition.validate())
	if influence_weight < 0.0:
		errors.append("ship part %s influence_weight cannot be negative" % id)
	if slot_type == SLOT_HULL and not slot_schema.is_empty():
		var seen_types: Dictionary = {}
		for entry in slot_schema:
			var entry_type: StringName = entry.get("type", &"") as StringName
			var entry_count: int = int(entry.get("count", 0))
			if entry_type != SLOT_DRIVE and entry_type != SLOT_WEAPON and entry_type != SLOT_SHIELD and entry_type != SLOT_SCANNER and entry_type != SLOT_UTILITY:
				errors.append("ship part %s slot_schema contains invalid slot type %s" % [id, entry_type])
			elif seen_types.has(entry_type):
				errors.append("ship part %s slot_schema duplicates slot type %s" % [id, entry_type])
			elif entry_count < 1 or entry_count > 8:
				errors.append("ship part %s slot_schema count for %s must be between 1 and 8" % [id, entry_type])
			seen_types[entry_type] = true
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
