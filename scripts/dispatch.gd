class_name Dispatch

const CLUSTER_CAPACITIES: Array[int] = [100, 5, 1]
const K_MAX_UNITS := 4
const M_MAX_UNITS := 99
const CLUSTER_TIERS: Array[StringName] = [&"k", &"m", &"l"]

static func amount_range(available: int) -> Vector2i:
	if available <= 0:
		return Vector2i.ZERO
	return Vector2i(1, available)

static func launch_amount(available: int, requested: int) -> int:
	if available <= 0 or requested < 1:
		return 0
	return mini(requested, available)

static func cluster_groups(unit_count: int) -> Array[int]:
	var remaining := maxi(unit_count, 0)
	var groups: Array[int] = []
	for capacity in CLUSTER_CAPACITIES:
		while remaining >= capacity:
			groups.append(capacity)
			remaining -= capacity
	return groups

static func cluster_tier(unit_count: int) -> StringName:
	if unit_count > M_MAX_UNITS:
		return &"l"
	if unit_count > K_MAX_UNITS:
		return &"m"
	return &"k"
