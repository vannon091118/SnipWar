class_name Dispatch

const DEFAULT_CONFIG: TransitConfig = preload("res://resources/config/transit_default.tres")

static func amount_range(available: int) -> Vector2i:
	if available <= 0:
		return Vector2i.ZERO
	return Vector2i(1, available)

static func launch_amount(available: int, requested: int) -> int:
	if available <= 0 or requested < 1:
		return 0
	return mini(requested, available)

static func cluster_groups(unit_count: int, config: TransitConfig = null) -> Array[int]:
	var resolved_config: TransitConfig = config if config != null else DEFAULT_CONFIG
	var remaining := maxi(unit_count, 0)
	var groups: Array[int] = []
	for tier in resolved_config.tiers_descending_capacity():
		if tier.capacity <= 0:
			continue
		while remaining >= tier.capacity:
			groups.append(tier.capacity)
			remaining -= tier.capacity
	return groups

static func cluster_tier(unit_count: int, config: TransitConfig = null, tier_bonus: int = 0) -> StringName:
	var definition := cluster_definition(unit_count, config, tier_bonus)
	return definition.id if definition != null else &""

static func cluster_definition(unit_count: int, config: TransitConfig = null, tier_bonus: int = 0) -> ClusterTierDefinition:
	var resolved_config: TransitConfig = config if config != null else DEFAULT_CONFIG
	var tiers := resolved_config.tiers_ascending_display_limit()
	if tiers.is_empty():
		return null
	var target := maxi(unit_count, 1)
	var selected_index := tiers.size() - 1
	for index in tiers.size():
		if target <= tiers[index].display_max_units:
			selected_index = index
			break
	var resolved_bonus := maxi(tier_bonus, 0)
	selected_index = mini(selected_index + resolved_bonus, tiers.size() - 1)
	return tiers[selected_index]
