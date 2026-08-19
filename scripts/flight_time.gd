class_name FlightTime

const BASE_SECONDS_PER_DISTANCE := 1.0
const SLOWDOWN_PER_EXTRA_UNIT := 0.2
const GROUP_SLOWDOWN_FACTOR := 0.3

static func seconds_for(distance: float, unit_count: int) -> float:
	var extra_units := maxi(unit_count - 1, 0)
	return distance * (
		BASE_SECONDS_PER_DISTANCE
		+ SLOWDOWN_PER_EXTRA_UNIT * extra_units
		+ GROUP_SLOWDOWN_FACTOR * sqrt(extra_units)
	)
