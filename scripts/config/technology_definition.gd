@tool
class_name TechnologyDefinition
extends Resource

const CATEGORY_SHIPS := &"ships"
const CATEGORY_MECH := &"mech"
const CATEGORY_PLANET := &"planet"
const CATEGORY_DRONES := &"drones"

@export var id: StringName = &""
@export var category: StringName = CATEGORY_SHIPS
@export var display_name: String = ""
@export var description: String = ""
@export var cost_resource: StringName = GameConstants.RES_ENERGY
@export var cost_amount: int = 10
@export var credit_cost: int = 5
## Player-facing strategic category used to scan the technology tree quickly.
@export var strategic_role: StringName = &""
@export var prerequisite_tech_id: StringName = &""
## Additional prerequisites (all must be researched). Lets branches merge
## multiple trees, e.g. the drone root requires a mech AND a ship tech.
@export var prerequisite_tech_ids: Array[StringName] = []
@export var requires_discovery: bool = false
## Mutually exclusive tech: if this ID is already researched, this tech is blocked
## and vice versa — forces a branch decision.
@export var mutually_exclusive_with: StringName = &""
@export var visual_asset: Texture2D
@export_group("Mechanical Effect")
@export var effect_id: StringName = &""
@export_multiline var mechanic_description: String = ""
@export_range(0.1, 10.0, 0.05) var production_multiplier: float = 1.0
# 0 = instant (legacy); > 0 = research runs as a timed job.
@export_range(0.0, 3600.0, 0.1) var research_time: float = 0.0

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("technology id is empty")
	if display_name.is_empty():
		errors.append("technology %s display_name is empty" % id)
	if category != CATEGORY_SHIPS and category != CATEGORY_MECH and category != CATEGORY_PLANET and category != CATEGORY_DRONES:
		errors.append("technology %s has invalid category %s" % [id, category])
	if cost_amount < 0:
		errors.append("technology %s cost_amount cannot be negative" % id)
	if credit_cost < 0:
		errors.append("technology %s credit_cost cannot be negative" % id)
	if visual_asset == null:
		errors.append("technology %s visual_asset is missing" % id)
	if String(effect_id).is_empty():
		errors.append("technology %s effect_id is empty" % id)
	if mechanic_description.is_empty():
		errors.append("technology %s mechanic_description is empty" % id)
	if production_multiplier <= 0.0:
		errors.append("technology %s production_multiplier must be positive" % id)
	if research_time < 0.0:
		errors.append("technology %s research_time cannot be negative" % id)
	return errors

## Returns true when the given set of already-researched tech IDs conflicts
## with this technology's mutual-exclusion constraint.
func is_blocked_by_exclusion(researched_ids: Array) -> bool:
	if String(mutually_exclusive_with).is_empty():
		return false
	return researched_ids.has(mutually_exclusive_with)
