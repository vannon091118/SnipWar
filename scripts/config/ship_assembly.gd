@tool
class_name ShipAssembly
extends Resource

const SLOT_HULL: StringName = &"hull"
const SLOT_DRIVE: StringName = &"drive"
const SLOT_WEAPON: StringName = &"weapon"
const SLOT_SHIELD: StringName = &"shield"
const SLOT_SCANNER: StringName = &"scanner"
const SLOT_UTILITY: StringName = &"utility"

## Typed, copyable snapshot of one assembled ship. Component IDs remain stable
## across inventory, flight, combat, replay, and hangar presentation; callers
## resolve them through ShipPartCatalog instead of indexing a loadout Dictionary.

@export_group("Identity")
@export var ship_id: StringName = &""
@export var role: StringName = &"colony"
@export var blueprint_id: StringName = &""
@export var instance_seed: int = 0

@export_group("Components")
@export var hull_id: StringName = &""
@export var drive_id: StringName = &""
@export var weapon_id: StringName = &""
@export var shield_id: StringName = &""
@export var scanner_id: StringName = &""
@export var module_ids: Array[StringName] = []

@export_group("Selected Variants")
@export var hull_variant_id: StringName = &""
@export var drive_variant_id: StringName = &""
@export var weapon_variant_id: StringName = &""
@export var shield_variant_id: StringName = &""
@export var scanner_variant_id: StringName = &""
@export var utility_variant_ids: Array[StringName] = []

func copy() -> ShipAssembly:
	return duplicate(true) as ShipAssembly

func is_empty() -> bool:
	return String(hull_id).is_empty() and String(drive_id).is_empty() and String(weapon_id).is_empty() and String(shield_id).is_empty() and String(scanner_id).is_empty() and module_ids.is_empty()

func variant_id_for(slot_type: StringName, module_index: int = -1) -> StringName:
	match slot_type:
		SLOT_HULL:
			return hull_variant_id
		SLOT_DRIVE:
			return drive_variant_id
		SLOT_WEAPON:
			return weapon_variant_id
		SLOT_SHIELD:
			return shield_variant_id
		SLOT_SCANNER:
			return scanner_variant_id
		SLOT_UTILITY:
			if module_index >= 0 and module_index < utility_variant_ids.size():
				return utility_variant_ids[module_index]
	return &""

func set_variant_id(slot_type: StringName, variant_id: StringName, module_index: int = -1) -> void:
	match slot_type:
		SLOT_HULL:
			hull_variant_id = variant_id
		SLOT_DRIVE:
			drive_variant_id = variant_id
		SLOT_WEAPON:
			weapon_variant_id = variant_id
		SLOT_SHIELD:
			shield_variant_id = variant_id
		SLOT_SCANNER:
			scanner_variant_id = variant_id
		SLOT_UTILITY:
			if module_index < 0:
				return
			while utility_variant_ids.size() <= module_index:
				utility_variant_ids.append(&"")
			utility_variant_ids[module_index] = variant_id

static func derive_role_from_modules(assembly: ShipAssembly, catalog: ShipPartCatalog = null) -> StringName:
	if assembly == null:
		return &"colony"
	if not String(assembly.weapon_id).is_empty():
		return &"military"
	var priorities: Array[StringName] = [&"colony", &"transport", &"research", &"military"]
	var selected: StringName = &""
	for module_id in assembly.module_ids:
		var module_role: StringName = &""
		if catalog != null:
			var part: ShipPartDefinition = catalog.resolve(module_id)
			if part != null:
				module_role = StringName(part.module_role)
				# A weapon mounted in a dynamic slot still arms the ship.
				if String(module_role).is_empty() and part.slot_type == ShipPartDefinition.SLOT_WEAPON:
					module_role = &"military"
		if String(module_role).is_empty():
			match module_id:
				&"colony_module": module_role = &"colony"
				&"transport_module": module_role = &"transport"
				&"science_module": module_role = &"research"
				&"defense_module": module_role = &"military"
			if String(module_role).is_empty():
				module_role = &"colony"
		var current_priority: int = priorities.find(module_role)
		var selected_priority: int = priorities.find(selected)
		if current_priority >= 0 and (selected_priority < 0 or current_priority < selected_priority):
			selected = module_role
	return selected if not String(selected).is_empty() else &"colony"

func set_module_ids(values: Array) -> void:
	module_ids.clear()
	for value in values:
		var part_id: StringName = value as StringName
		if not String(part_id).is_empty():
			module_ids.append(part_id)

func set_utility_variant_ids(values: Array) -> void:
	utility_variant_ids.clear()
	for value in values:
		utility_variant_ids.append(value as StringName)

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(ship_id).is_empty():
		errors.append("ship assembly ship_id is empty")
	if String(hull_id).is_empty():
		errors.append("ship assembly hull_id is empty")
	if String(role).is_empty():
		errors.append("ship assembly role is empty")
	if utility_variant_ids.size() > module_ids.size():
		errors.append("ship assembly has more utility variants than modules")
	return errors
