class_name FlightTime

const BASE_SECONDS_PER_DISTANCE := 1.0
const UNIT_LOAD_FACTOR := 0.12
const CLUSTER_LOAD_FACTOR := 0.18

static func seconds_for(distance: float, unit_count: int) -> float:
	var groups := Dispatch.cluster_groups(unit_count)
	var extra_units := maxi(unit_count - 1, 0)
	var extra_clusters := maxi(groups.size() - 1, 0)
	return distance * (
		BASE_SECONDS_PER_DISTANCE
		+ UNIT_LOAD_FACTOR * sqrt(extra_units)
		+ CLUSTER_LOAD_FACTOR * extra_clusters
	)
