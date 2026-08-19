@tool
class_name EconomyConfig
extends Resource

@export_range(0.1, 3600.0, 0.1) var tick_interval: float = 10.0

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if tick_interval <= 0.0:
		errors.append("economy tick_interval must be positive")
	return errors
