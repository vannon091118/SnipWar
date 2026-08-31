@tool
class_name EconomyConfig
extends Resource

@export_range(0.1, 7200.0, 0.1) var tick_interval: float = 10.0
@export_range(0, 1000000, 1) var starting_credits: int = 100
## QS-4: Per-Tick-Credit-Einkommen — macht den Tutorial-Satz „Credits kommen
## über die Runden" wahr. Jede Kolonie (Fraktion-Besitz) generiert pro Tick
## diese Menge Credits (before upgrade modifiers).
@export_range(0, 1000, 1) var credit_income_per_colony: int = 5
## QS-4: Zusätzliches Credit-Einkommen pro gebautem Upgrade pro Tick.
@export_range(0, 1000, 1) var credit_income_per_upgrade: int = 2
@export_range(1, 32, 1) var market_radius_hops: int = 2
@export_range(0.0, 100.0, 0.01) var market_toll_rate: float = 0.1

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if tick_interval <= 0.0:
		errors.append("economy tick_interval must be positive")
	if starting_credits < 0 or market_radius_hops < 1 or market_toll_rate < 0.0:
		errors.append("economy credit/market configuration is invalid")
	if credit_income_per_colony < 0 or credit_income_per_upgrade < 0:
		errors.append("economy credit income configuration is invalid")
	return errors
