@tool
class_name ConquestConfig
extends Resource

## Tunable parameters for the deterministic conquest / tower-defense simulator.
## Defaults mirror the legacy hardcoded constants in ConquestSimulator.

@export_range(0.01, 10.0, 0.01) var tick: float = 0.5
@export_range(0.1, 300.0, 0.1) var max_time: float = 20.0
@export_range(0.0, 1.0, 0.01) var damage_variance_min: float = 0.9
@export_range(0.0, 2.0, 0.01) var damage_variance_max: float = 1.1
@export_range(0.1, 60.0, 0.1) var wave_interval: float = 3.0
@export_range(1, 100, 1) var max_waves: int = 5
@export_range(1, 1000, 1) var minions_per_wave_base: int = 3
@export_range(1.0, 100000.0, 1.0) var minion_hp: float = 10.0
@export_range(0.0, 10000.0, 0.1) var minion_dps: float = 2.0
@export_range(1.0, 10000.0, 1.0) var minion_speed: float = 60.0
@export_range(1.0, 100000.0, 1.0) var base_total_hp: float = 100.0
@export_range(0.0, 10000.0, 0.1) var tower_dps: float = 5.0
@export_range(1.0, 100000.0, 1.0) var tower_hp: float = 20.0
@export_range(1.0, 100000.0, 1.0) var worker_hp: float = 10.0
@export_range(0.0, 10000.0, 0.1) var worker_dps: float = 2.0

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if tick <= 0.0:
		errors.append("conquest tick must be positive")
	if max_time <= 0.0:
		errors.append("conquest max_time must be positive")
	if damage_variance_min < 0.0 or damage_variance_max < damage_variance_min:
		errors.append("conquest damage variance is invalid")
	if wave_interval <= 0.0:
		errors.append("conquest wave_interval must be positive")
	if max_waves < 1:
		errors.append("conquest max_waves must be positive")
	if minions_per_wave_base < 1:
		errors.append("conquest minions_per_wave_base must be positive")
	if minion_hp <= 0.0 or minion_dps < 0.0 or minion_speed <= 0.0:
		errors.append("conquest minion stats are invalid")
	if tower_dps < 0.0 or tower_hp <= 0.0:
		errors.append("conquest tower stats are invalid")
	if worker_hp <= 0.0 or worker_dps < 0.0:
		errors.append("conquest worker stats are invalid")
	return errors
