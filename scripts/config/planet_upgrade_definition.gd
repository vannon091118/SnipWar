@tool
class_name PlanetUpgradeDefinition
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var branch: StringName = &"economy"
@export var tier: int = 1
@export var parent_upgrade_id: StringName = &""
@export var exclusive_with: StringName = &""
@export var required_technology_id: StringName = &""
@export var cost_resource: StringName = &"energy"
@export var cost_amount: int = 10
@export var cost_workers: int = 1
@export var trait_definition: TraitDefinition
@export var visual_asset: Texture2D
@export var transformer_tint_mode: StringName = &"faction"

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("upgrade id is empty")
	if display_name.is_empty():
		errors.append("upgrade display_name is empty")
	if branch != &"economy" and branch != &"military" and branch != &"tech" and branch != &"infrastructure":
		errors.append("upgrade branch %s is invalid" % branch)
	if tier < 1:
		errors.append("upgrade tier must be >= 1")
	if cost_amount < 0:
		errors.append("cost_amount cannot be negative")
	if cost_workers < 0:
		errors.append("cost_workers cannot be negative")
	if trait_definition != null:
		errors.append_array(trait_definition.validate())
	return errors
