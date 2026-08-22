@tool
class_name BuildingDefinition
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export_enum("tower", "wall", "garrison", "production", "tech") var building_type: String = "tower"
@export_range(1, 100000, 1) var hp: int = 20
@export_range(0.0, 10000.0, 0.1) var dps: float = 5.0
@export_range(0.0, 10000.0, 0.1) var attack_range: float = 100.0
@export_range(0.01, 60.0, 0.01) var fire_interval: float = 1.0
@export var cost_resources: Dictionary = {}
@export var required_tech_id: StringName = &""
@export_range(0.0, 3600.0, 0.1) var build_time: float = 0.0
@export var visual_asset: Texture2D
@export_range(1, 16, 1) var grid_occupancy: int = 1
@export_range(0, 64, 1) var perimeter_slot_cost: int = 1

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("building id is empty")
	if hp < 1:
		errors.append("building hp must be positive")
	if dps < 0.0:
		errors.append("building dps cannot be negative")
	if attack_range < 0.0:
		errors.append("building attack_range cannot be negative")
	if fire_interval <= 0.0:
		errors.append("building fire_interval must be positive")
	if build_time < 0.0:
		errors.append("building build_time cannot be negative")
	if grid_occupancy < 1:
		errors.append("building grid_occupancy must be positive")
	if perimeter_slot_cost < 0:
		errors.append("building perimeter_slot_cost cannot be negative")
	return errors
