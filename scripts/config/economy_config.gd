@tool
class_name EconomyConfig
extends Resource

@export_range(0.1, 7200.0, 0.1) var tick_interval: float = 10.0
@export_range(0, 1000000, 1) var starting_credits: int = 100
@export_range(1, 32, 1) var market_radius_hops: int = 2
@export_range(0.0, 100.0, 0.01) var market_toll_rate: float = 0.1

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if tick_interval <= 0.0:
		errors.append("economy tick_interval must be positive")
	if starting_credits < 0 or market_radius_hops < 1 or market_toll_rate < 0.0:
		errors.append("economy credit/market configuration is invalid")
	return errors
