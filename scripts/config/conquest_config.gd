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

@export_group("Repair Drones (Module HP Regeneration)")
## Repair drone tiers regenerate module HP during grid conquest but never
## fully: T1 restores ships to a functional state (~35 %), T2 up to 50 % with
## a high charge time (low regeneration), T3 up to 60 % with medium charging.
@export_range(0.0, 1.0, 0.01) var repair_cap_t1: float = 0.35
@export_range(0.0, 1.0, 0.01) var repair_cap_t2: float = 0.5
@export_range(0.0, 1.0, 0.01) var repair_cap_t3: float = 0.6
@export_range(0.0, 100.0, 0.1) var repair_rate_t1: float = 2.0
@export_range(0.0, 100.0, 0.1) var repair_rate_t2: float = 1.2
@export_range(0.0, 100.0, 0.1) var repair_rate_t3: float = 2.8

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
	if repair_cap_t1 < 0.0 or repair_cap_t1 > 1.0 or repair_cap_t2 < 0.0 or repair_cap_t2 > 1.0 or repair_cap_t3 < 0.0 or repair_cap_t3 > 1.0:
		errors.append("conquest repair caps must be between 0 and 1")
	if repair_cap_t2 < repair_cap_t1 or repair_cap_t3 < repair_cap_t2:
		errors.append("conquest repair caps must grow with drone tier")
	if repair_rate_t1 < 0.0 or repair_rate_t2 < 0.0 or repair_rate_t3 < 0.0:
		errors.append("conquest repair rates cannot be negative")
	return errors
