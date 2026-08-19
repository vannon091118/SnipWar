@tool
class_name ShipConfig
extends Resource

@export var scout_hull_tech_id: StringName = &"scout_hull"
@export var scout_scanner_tech_id: StringName = &"scanner_drone"
@export var scout_build_cost_resource: StringName = GameState.RES_MATERIAL
@export var scout_build_cost_amount: int = 5
@export var worker_build_cost_resource: StringName = GameState.RES_MATERIAL
@export var worker_build_cost_amount: int = 5
@export_range(10.0, 400.0, 1.0) var scout_speed: float = 80.0
@export_group("Scout Visual")
@export var scanner_offset: Vector2 = Vector2(7.0, -5.0)
@export_range(0.1, 2.0, 0.05) var scanner_visual_scale: float = 0.5
@export_group("Hangar Visual")
@export_range(4.0, 64.0, 1.0) var hangar_slot_spacing: float = 16.0
@export_range(4.0, 48.0, 1.0) var worker_visual_size: float = 14.0
@export var hangar_worker_offset: Vector2 = Vector2(0.0, -8.0)

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(scout_hull_tech_id).is_empty():
		errors.append("ship scout_hull_tech_id is empty")
	if String(scout_scanner_tech_id).is_empty():
		errors.append("ship scout_scanner_tech_id is empty")
	if scout_build_cost_amount < 0:
		errors.append("ship scout_build_cost_amount cannot be negative")
	if worker_build_cost_amount < 0:
		errors.append("ship worker_build_cost_amount cannot be negative")
	if scanner_visual_scale <= 0.0:
		errors.append("ship scanner visual scale must be positive")
	if hangar_slot_spacing <= 0.0 or worker_visual_size <= 0.0:
		errors.append("ship hangar visual tuning must be positive")
	if scout_speed <= 0.0:
		errors.append("ship scout_speed must be positive")
	return errors
