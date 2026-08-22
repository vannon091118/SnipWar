@tool
class_name BattleConfig
extends Resource

## Tunable parameters for the deterministic fleet battle simulator. Defaults
## mirror the legacy hardcoded constants in FleetBattleSimulator.

@export_range(0.01, 10.0, 0.01) var tick: float = 0.5
@export_range(0.1, 300.0, 0.1) var max_time: float = 30.0
@export_range(0.0, 1.0, 0.01) var damage_variance_min: float = 0.85
@export_range(0.0, 2.0, 0.01) var damage_variance_max: float = 1.15

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if tick <= 0.0:
		errors.append("battle tick must be positive")
	if max_time <= 0.0:
		errors.append("battle max_time must be positive")
	if damage_variance_min < 0.0 or damage_variance_max < damage_variance_min:
		errors.append("battle damage variance is invalid")
	return errors
