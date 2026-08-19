class_name PlanetSizeProfile
extends Resource

@export var id: StringName = &"variable"
@export var scale_range: Vector2 = Vector2.ONE
@export_range(0.01, 3600.0, 0.01) var spawn_interval: float = 1.0
@export_range(1, 100000, 1) var spawn_count: int = 1
@export_range(0.0, 2.0, 0.01) var jitter_factor: float = 1.0

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("planet size profile id is empty")
	if scale_range.x <= 0.0 or scale_range.y < scale_range.x:
		errors.append("planet size profile scale_range is invalid")
	if spawn_interval <= 0.0:
		errors.append("planet size profile spawn_interval must be positive")
	if spawn_count < 1:
		errors.append("planet size profile spawn_count must be positive")
	if jitter_factor < 0.0:
		errors.append("planet size profile jitter_factor cannot be negative")
	return errors
