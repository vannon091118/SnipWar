class_name PlanetTraitAggregator

## Aggregates PlanetUpgrade trait bonuses for a Planet node in a single catalog
## pass. Kept out of planet.gd so the repeated "iterate get_planet_upgrades() and
## sum one trait field" pattern lives in one place instead of six near-identical
## loops. Planet keeps thin public wrappers so all callers stay stable.

const DEFAULT_CATALOG: PlanetUpgradeCatalog = preload("res://resources/config/planet_upgrade_catalog_default.tres")

## Sums every trait consumed by Planet in one loop. The keys mirror the six
## values Planet used to compute individually; start values encode the neutral
## element (1.0 for the multiplicative transfer multiplier, 0 elsewhere).
static func aggregate_traits(planet: Planet) -> Dictionary:
	var traits: Dictionary = {
		"worker_spawn_bonus": 0,
		"cluster_tier_bonus": 0,
		"defense_rating": 0,
		"perimeter_slots_bonus": 0,
		"range_bonus": 0.0,
		"transfer_speed_multiplier": 1.0,
	}
	if planet == null:
		return traits
	var state: Node = GameStateAccess.autoload(planet)
	if state == null:
		return traits
	for up_id in state.get_planet_upgrades(planet.planet_id):
		var def: PlanetUpgradeDefinition = DEFAULT_CATALOG.resolve(up_id)
		if def == null or def.trait_definition == null:
			continue
		var t: TraitDefinition = def.trait_definition
		traits["worker_spawn_bonus"] += t.worker_spawn_bonus
		traits["cluster_tier_bonus"] += t.cluster_tier_bonus
		traits["defense_rating"] += t.defense_rating
		traits["perimeter_slots_bonus"] += t.perimeter_slots_bonus
		traits["range_bonus"] += t.range_bonus
		traits["transfer_speed_multiplier"] *= t.transfer_speed_multiplier
	return traits

static func get_build_slot_count(planet: Planet) -> int:
	return maxi(planet.get_size_profile().build_slot_count, 1)

static func get_perimeter_slots(planet: Planet) -> int:
	var traits := aggregate_traits(planet)
	return maxi(1, planet.get_size_profile().build_slot_count + int(traits["perimeter_slots_bonus"]))

static func get_defense_range(planet: Planet) -> float:
	var traits := aggregate_traits(planet)
	return maxf(50.0, 150.0 + float(traits["range_bonus"]))

static func get_transfer_speed_multiplier(planet: Planet) -> float:
	var traits := aggregate_traits(planet)
	return float(traits["transfer_speed_multiplier"])

static func get_cluster_tier_bonus(planet: Planet) -> int:
	var traits := aggregate_traits(planet)
	return maxi(0, int(traits["cluster_tier_bonus"]))

static func get_spawn_count(planet: Planet) -> int:
	var traits := aggregate_traits(planet)
	var count: int = planet.get_size_profile().spawn_count + int(traits["worker_spawn_bonus"])
	return mini(count, get_build_slot_count(planet))

static func aggregate_defense_rating(planet: Planet) -> int:
	var traits := aggregate_traits(planet)
	return int(traits["defense_rating"])
