@tool
class_name TraitDefinition
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
@export var production_boost: float = 0.0
@export var worker_spawn_bonus: int = 0
@export var cluster_tier_bonus: int = 0
@export var defense_rating: int = 0
@export var perimeter_slots_bonus: int = 0
@export var range_bonus: float = 0.0
@export var transfer_speed_multiplier: float = 1.0
@export var maintenance_cost_resource: StringName = &""
@export var maintenance_cost_amount: int = 0

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("trait id is empty")
	if display_name.is_empty():
		errors.append("trait display_name is empty")
	if cluster_tier_bonus < 0:
		errors.append("trait cluster_tier_bonus cannot be negative")
	return errors
