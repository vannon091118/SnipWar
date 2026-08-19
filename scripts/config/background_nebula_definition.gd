@tool
class_name BackgroundNebulaDefinition
extends Resource

@export var normalized_position: Vector2
@export_range(0.0, 2.0, 0.01) var radius_ratio: float
@export var color: Color

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if normalized_position.x < 0.0 or normalized_position.x > 1.0 or normalized_position.y < 0.0 or normalized_position.y > 1.0:
		errors.append("background nebula position must be normalized")
	if radius_ratio <= 0.0:
		errors.append("background nebula radius_ratio must be positive")
	return errors
