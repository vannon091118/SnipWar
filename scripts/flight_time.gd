class_name FlightTime

const DEFAULT_CONFIG: TransitConfig = preload("res://resources/config/transit_default.tres")

static func seconds_for(distance: float, unit_count: int, config: TransitConfig = null) -> float:
	var resolved_config: TransitConfig = config if config != null else DEFAULT_CONFIG
	var extra_units := maxi(unit_count - 1, 0)
	return distance * (resolved_config.base_seconds_per_distance + resolved_config.unit_load_factor * sqrt(extra_units))
