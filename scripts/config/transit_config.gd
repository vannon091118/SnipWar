@tool
class_name TransitConfig
extends Resource

@export_range(0.01, 10000.0, 0.01) var distance_unit: float
@export_range(0.0, 1000.0, 0.01) var base_seconds_per_distance_unit: float
@export_range(0.0, 10.0, 0.01) var unit_load_factor: float
@export_range(0.01, 1.0, 0.01) var overlap_budget: float
@export_range(0.0, 2.0, 0.01) var formation_depth_ratio: float
@export var cluster_tiers: Array[ClusterTierDefinition] = []

func tiers_descending_capacity() -> Array[ClusterTierDefinition]:
	var result: Array[ClusterTierDefinition] = []
	for tier in cluster_tiers:
		if tier != null:
			result.append(tier)
	result.sort_custom(Callable(self, "_sort_descending_capacity"))
	return result

func tiers_ascending_capacity() -> Array[ClusterTierDefinition]:
	var result := tiers_descending_capacity()
	result.reverse()
	return result

func tiers_ascending_display_limit() -> Array[ClusterTierDefinition]:
	var result: Array[ClusterTierDefinition] = []
	for tier in cluster_tiers:
		if tier != null:
			result.append(tier)
	result.sort_custom(Callable(self, "_sort_ascending_display_limit"))
	return result

func tier_for_amount(amount: int) -> ClusterTierDefinition:
	var target := maxi(amount, 1)
	var tiers := tiers_ascending_display_limit()
	for tier in tiers:
		if target <= tier.display_max_units:
			return tier
	var descending := tiers_descending_capacity()
	return descending[0] if not descending.is_empty() else null

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if distance_unit <= 0.0:
		errors.append("transit distance_unit must be positive")
	if base_seconds_per_distance_unit < 0.0:
		errors.append("transit base_seconds_per_distance_unit cannot be negative")
	if unit_load_factor < 0.0:
		errors.append("transit unit_load_factor cannot be negative")
	if overlap_budget <= 0.0 or overlap_budget > 1.0:
		errors.append("transit overlap_budget must be greater than zero and at most one")
	if formation_depth_ratio < 0.0:
		errors.append("transit formation_depth_ratio cannot be negative")
	if cluster_tiers.is_empty():
		errors.append("transit must define at least one cluster tier")

	var seen_ids: Dictionary = {}
	var seen_capacities: Dictionary = {}
	var seen_display_limits: Dictionary = {}
	for tier in cluster_tiers:
		if tier == null:
			errors.append("transit contains a null cluster tier")
			continue
		for tier_error in tier.validate():
			errors.append("cluster tier %s: %s" % [tier.id, tier_error])
		if tier.display_max_units < tier.capacity:
			errors.append("cluster tier %s display limit is below its capacity" % tier.id)
		if seen_ids.has(tier.id):
			errors.append("transit cluster tier ids must be unique")
		seen_ids[tier.id] = true
		if seen_capacities.has(tier.capacity):
			errors.append("transit cluster tier capacities must be unique")
		seen_capacities[tier.capacity] = true
		if seen_display_limits.has(tier.display_max_units):
			errors.append("transit cluster tier display limits must be unique")
		seen_display_limits[tier.display_max_units] = true
	if not seen_capacities.has(1):
		errors.append("transit must define a capacity-one cluster tier")
	return errors

func _sort_descending_capacity(first: ClusterTierDefinition, second: ClusterTierDefinition) -> bool:
	return first.capacity > second.capacity

func _sort_ascending_display_limit(first: ClusterTierDefinition, second: ClusterTierDefinition) -> bool:
	return first.display_max_units < second.display_max_units
