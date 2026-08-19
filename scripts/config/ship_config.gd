@tool
class_name ShipConfig
extends Resource

@export var scout_hull_tech_id: StringName = &"scout_hull"
@export var scout_scanner_tech_id: StringName = &"scanner_drone"
@export var scout_build_cost_resource: StringName = &"material"
@export var scout_build_cost_amount: int = 5
@export_range(10.0, 400.0, 1.0) var scout_speed: float = 80.0

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(scout_hull_tech_id).is_empty():
		errors.append("ship scout_hull_tech_id is empty")
	if String(scout_scanner_tech_id).is_empty():
		errors.append("ship scout_scanner_tech_id is empty")
	if scout_build_cost_amount < 0:
		errors.append("ship scout_build_cost_amount cannot be negative")
	if scout_speed <= 0.0:
		errors.append("ship scout_speed must be positive")
	return errors
