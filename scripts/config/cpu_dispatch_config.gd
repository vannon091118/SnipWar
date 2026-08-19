@tool
class_name CpuDispatchConfig
extends Resource

@export var enabled: bool = true
@export_range(0.5, 3600.0, 0.5) var decision_interval: float = 12.0
@export_range(0, 100000, 1) var reserve_workers: int = 2
@export_range(1, 100000, 1) var minimum_source_workers: int = 3
@export_range(0.1, 1.0, 0.05) var dispatch_fraction: float = 0.5

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if decision_interval <= 0.0:
		errors.append("CPU decision_interval must be positive")
	if reserve_workers < 0:
		errors.append("CPU reserve_workers cannot be negative")
	if minimum_source_workers < 1:
		errors.append("CPU minimum_source_workers must be positive")
	if dispatch_fraction <= 0.0 or dispatch_fraction > 1.0:
		errors.append("CPU dispatch_fraction must be greater than zero and at most one")
	return errors
