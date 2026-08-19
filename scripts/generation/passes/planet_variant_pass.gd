@tool
class_name PlanetVariantPass
extends GenerationPass

## Generation pass that resolves planet variant choices using percentage-based rules.
## Reads PlacementRule entries for texture variants and detail profiles,
## then annotates existing planet placements with their final visual identity.
##
## This pass does NOT create new placements — it modifies the planet placements
## produced by PlanetPlacementPass via the shared_data.

## Rules for planet texture variant selection (weighted, percentage-based).
@export var texture_rules: Array[PlacementRule] = []

## Rules for detail profile variant selection.
@export var detail_profile_rules: Array[PlacementRule] = []

func _init() -> void:
	pass_name = "PlanetVariant"
	order = 20

func generate(ctx: GenerationContext) -> Array[Placement]:
	var planet_placements: Array = ctx.get_shared(&"planet_placements", []) as Array
	if planet_placements.is_empty():
		return []

	for placement: Placement in planet_placements:
		if placement == null or placement.placement_type != &"planet":
			continue
		var variant_rng := ctx.rng_for_context(placement.placement_id)

		# Resolve texture variant from rules.
		if not texture_rules.is_empty():
			var chosen_texture := _weighted_select(texture_rules, variant_rng)
			if chosen_texture != null:
				placement.metadata["texture_rule"] = chosen_texture

		# Resolve detail profile variant from rules.
		if not detail_profile_rules.is_empty():
			var chosen_profile := _weighted_select(detail_profile_rules, variant_rng)
			if chosen_profile != null:
				placement.metadata["detail_profile_rule"] = chosen_profile

	return []


## Weighted random selection from PlacementRule array.
## Returns the selected PlacementRule or null.
func _weighted_select(rules: Array[PlacementRule], rng: RandomNumberGenerator) -> PlacementRule:
	if rules.is_empty():
		return null

	var total_weight := 0.0
	for rule: PlacementRule in rules:
		if rule != null:
			total_weight += rule.weight

	if total_weight <= 0.0:
		return null

	var roll := rng.randf() * total_weight
	var accumulated := 0.0
	for rule: PlacementRule in rules:
		if rule == null:
			continue
		accumulated += rule.weight
		if roll <= accumulated:
			# Check probability gate.
			if rule.evaluate_roll(rng):
				return rule
			return null

	return null
