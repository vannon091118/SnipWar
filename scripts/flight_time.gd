class_name FlightTime

const DEFAULT_CONFIG: TransitConfig = preload("res://resources/config/transit_default.tres")

static func seconds_for(distance: float, unit_count: int, config: TransitConfig = null, speed_multiplier: float = 1.0) -> float:
	var resolved_config: TransitConfig = config if config != null else DEFAULT_CONFIG
	var extra_units := maxi(unit_count - 1, 0)
	var normalized_distance: float = maxf(distance, 0.0) / resolved_config.distance_unit
	var load_multiplier := 1.0 + resolved_config.unit_load_factor * sqrt(extra_units)
	var base_time := normalized_distance * resolved_config.base_seconds_per_distance_unit * load_multiplier
	return base_time / maxf(speed_multiplier, 0.01)
