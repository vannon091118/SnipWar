class_name EconomyDomain
extends RefCounted

## Manages faction vaults, resource deals, planet upgrades, worker factories, and gathering state.

signal faction_resources_changed(faction: StringName, resource_id: StringName, new_amount: int)
signal planet_upgraded(planet_id: StringName, upgrade_id: StringName)
signal resource_generated(planet_id: StringName, resource_id: StringName, amount: int)
signal resources_collected(faction: StringName, planet_id: StringName, resource_id: StringName, amount: int)
signal gathering_started(faction: StringName, planet_id: StringName, workers: int)
signal gathering_withdrawn(faction: StringName, planet_id: StringName, workers: int)
signal worker_factory_built(planet_id: StringName)
signal refinery_converted(planet_id: StringName, faction: StringName, consumed: Dictionary, produced: Dictionary)
signal local_resources_changed(planet_id: StringName, resource_id: StringName, new_amount: int)
signal resource_transferred(from_planet: StringName, to_planet: StringName, resource_id: StringName, amount: int)
signal building_placed(planet_id: StringName, building_id: StringName, q: int, r: int)
signal building_removed(planet_id: StringName, q: int, r: int)

var faction_vaults: Dictionary = {}
var planet_resources: Dictionary = {}
var planet_upgrades: Dictionary = {}
var worker_factories: Dictionary = {}
var gathering_workers: Dictionary = {}
var gathering_sources: Dictionary = {}
var local_vaults: Dictionary = {}
var trade_routes: Dictionary = {}
var planet_buildings: Dictionary = {}
# Planets whose starting local stock has already been dealt (prevents
# re-seeding when an evicted chunk is regenerated).
var _local_seeded_planets: Dictionary = {}

func reset_vaults() -> void:
	faction_vaults = {
		GameState.FACTION_PLAYER: {
			GameState.RES_ENERGY: 50,
			GameState.RES_BIOMASS: 50,
			GameState.RES_RARE: 30,
			GameState.RES_MATERIAL: 30,
			GameState.RES_VOLATILE: 30
		},
		GameState.FACTION_CPU: {
			GameState.RES_ENERGY: 50,
			GameState.RES_BIOMASS: 50,
			GameState.RES_RARE: 30,
			GameState.RES_MATERIAL: 30,
			GameState.RES_VOLATILE: 30
		}
	}

func reset() -> void:
	planet_resources.clear()
	planet_upgrades.clear()
	worker_factories.clear()
	gathering_workers.clear()
	gathering_sources.clear()
	local_vaults.clear()
	trade_routes.clear()
	planet_buildings.clear()
	_local_seeded_planets.clear()
	reset_vaults()

func get_faction_resource(faction: StringName, resource_id: StringName) -> int:
	if not faction_vaults.has(faction):
		return 0
	return int(faction_vaults[faction].get(resource_id, 0))

func get_faction_vault_snapshot(faction: StringName) -> Dictionary:
	if not faction_vaults.has(faction):
		return {}
	return (faction_vaults[faction] as Dictionary).duplicate()

func add_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> int:
	if amount <= 0 or String(faction).is_empty() or not _is_valid_resource_id(resource_id):
		return get_faction_resource(faction, resource_id)
	if not faction_vaults.has(faction):
		faction_vaults[faction] = {}
	var current: int = get_faction_resource(faction, resource_id)
	var new_val := current + amount
	faction_vaults[faction][resource_id] = new_val
	faction_resources_changed.emit(faction, resource_id, new_val)
	return new_val

func can_spend_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> bool:
	if amount <= 0:
		return true
	return get_faction_resource(faction, resource_id) >= amount

func spend_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> bool:
	if amount < 0:
		return false
	if amount == 0:
		return true
	if not can_spend_faction_resource(faction, resource_id, amount):
		return false
	var current: int = get_faction_resource(faction, resource_id)
	var new_val := current - amount
	faction_vaults[faction][resource_id] = new_val
	faction_resources_changed.emit(faction, resource_id, new_val)
	return true

func set_planet_resource(planet_id: StringName, resource_id: StringName) -> void:
	if String(planet_id).is_empty() or not _is_valid_resource_id(resource_id):
		return
	planet_resources[planet_id] = resource_id

func resource_of(planet_id: StringName) -> StringName:
	return planet_resources.get(planet_id, &"") as StringName

func deal_resources(catalog: PlanetCatalog, pool: ResourcePool = null, seed_value: int = 0) -> void:
	planet_resources.clear()
	var effective_pool: ResourcePool = pool if pool != null else GameState.DEFAULT_RESOURCE_POOL
	if catalog == null or effective_pool == null or effective_pool.resources.is_empty():
		return

	# NOTE: build + shuffle with the SAME rng instance used for the later
	# homeworld/planet shuffles. The shared-rng consumption order is part of the
	# seed-deterministic deal contract; _build_resource_id_list() is only for the
	# lazy per-chunk path (deal_resources_for_planets), which has no shared rng.
	var resource_ids: Array[StringName] = []
	for resource in effective_pool.resources:
		if resource != null and not String(resource.id).is_empty():
			resource_ids.append(resource.id)
	if resource_ids.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_shuffle(resource_ids, rng)

	var homeworld_defs: Array[PlanetDefinition] = []
	var other_defs: Array[PlanetDefinition] = []
	for definition in catalog.planets:
		if definition == null:
			continue
		if definition.planet_role == &"homeworld":
			homeworld_defs.append(definition)
		else:
			other_defs.append(definition)
	_shuffle(homeworld_defs, rng)
	_shuffle(other_defs, rng)

	var all_defs: Array[PlanetDefinition] = []
	all_defs.append_array(homeworld_defs)
	all_defs.append_array(other_defs)
	if all_defs.is_empty():
		return

	# Reserve a balanced quota for the round-robin fallback. Signature hints may
	# intentionally consume a quota early; the greedy fallback restores balance
	# for the remaining planets.
	var pool_size: int = resource_ids.size()
	var base_count: int = int(float(all_defs.size()) / float(pool_size))
	var extra_count: int = all_defs.size() % pool_size
	var available_counts: Dictionary = {}
	for index in pool_size:
		var resource_id: StringName = resource_ids[index]
		available_counts[resource_id] = base_count + (1 if index < extra_count else 0)

	var used_homeworld_resources: Dictionary = {}
	for definition in all_defs:
		var chosen_resource: StringName = &""
		var is_homeworld: bool = definition.planet_role == &"homeworld"
		var signature: StringName = definition.signature_resource
		var signature_blocked: bool = is_homeworld and used_homeworld_resources.has(signature)
		if not String(signature).is_empty() and resource_ids.has(signature) and not signature_blocked and rng.randf() < definition.signature_probability:
			# A probability-one signature is a hard preference, even if its
			# nominal quota is already exhausted.
			chosen_resource = signature

		if String(chosen_resource).is_empty():
			var best_count := -1
			for resource_id in resource_ids:
				if is_homeworld and used_homeworld_resources.has(resource_id):
					continue
				var remaining: int = int(available_counts.get(resource_id, 0))
				if remaining > best_count:
					best_count = remaining
					chosen_resource = resource_id

		# If there are more homeworlds than resource identities, release the
		# distinct-homeworld constraint and continue with the best quota.
		if String(chosen_resource).is_empty():
			var best_count := -1
			for resource_id in resource_ids:
				var remaining: int = int(available_counts.get(resource_id, 0))
				if remaining > best_count:
					best_count = remaining
					chosen_resource = resource_id

		if String(chosen_resource).is_empty():
			chosen_resource = resource_ids[0]
		set_planet_resource(definition.planet_id, chosen_resource)
		available_counts[chosen_resource] = maxi(0, int(available_counts.get(chosen_resource, 0)) - 1)
		if is_homeworld:
			used_homeworld_resources[chosen_resource] = true

func resource_snapshot() -> Dictionary:
	return planet_resources.duplicate()

## Deals resources for a batch of new planets WITHOUT clearing existing
## assignments. Homeworlds in the origin chunk are assigned distinct resource
## identities whenever the pool has at least two entries; neutral slots then
## use least-used round-robin balancing.
func deal_resources_for_planets(planet_data: Array, pool: ResourcePool = null, seed_value: int = 0) -> void:
	var effective_pool: ResourcePool = pool if pool != null else GameState.DEFAULT_RESOURCE_POOL
	if effective_pool == null or effective_pool.resources.is_empty():
		return
	var resource_ids := _build_resource_id_list(effective_pool, seed_value)
	if resource_ids.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var counts: Dictionary = {}
	var homeworld_data: Array = []
	var neutral_data: Array = []
	for data in planet_data:
		if data == null:
			continue
		var p_id: StringName = data.planet_id
		if String(p_id).is_empty() or planet_resources.has(p_id):
			continue
		if data.planet_role == &"homeworld":
			homeworld_data.append(data)
		else:
			neutral_data.append(data)
	_homeworld_data_sort(homeworld_data)
	for data in homeworld_data:
		var home_id: StringName = data.planet_id
		var signature: StringName = data.signature_resource
		var chosen: StringName = &""
		if not String(signature).is_empty() and resource_ids.has(signature) and rng.randf() < float(data.signature_probability):
			var signature_used := false
			for other_home in homeworld_data:
				if other_home == data:
					continue
				if planet_resources.get(other_home.planet_id, &"") == signature:
					signature_used = true
					break
			if not signature_used or resource_ids.size() < 2:
				chosen = signature
		if String(chosen).is_empty():
			var best_count := 1 << 30
			for resource_id in resource_ids:
				var already_used := false
				if resource_ids.size() >= 2:
					for other_home in homeworld_data:
						if other_home == data:
							continue
						if planet_resources.get(other_home.planet_id, &"") == resource_id:
							already_used = true
							break
				if already_used:
					continue
				var remaining: int = int(counts.get(resource_id, 0))
				if remaining < best_count:
					best_count = remaining
					chosen = resource_id
		if String(chosen).is_empty():
				chosen = _least_used_resource(resource_ids, counts)
		planet_resources[home_id] = chosen
		counts[chosen] = int(counts.get(chosen, 0)) + 1
	for data in neutral_data:
		var p_id: StringName = data.planet_id
		var signature: StringName = data.signature_resource
		var chosen: StringName = &""
		if not String(signature).is_empty() and resource_ids.has(signature) and rng.randf() < float(data.signature_probability):
			chosen = signature
		if String(chosen).is_empty():
			chosen = _least_used_resource(resource_ids, counts)
		planet_resources[p_id] = chosen
		counts[chosen] = int(counts.get(chosen, 0)) + 1

func _homeworld_data_sort(values: Array) -> void:
	values.sort_custom(func(first, second):
		return String(first.planet_id) < String(second.planet_id)
	)

## Builds a shuffled list of resource IDs from the pool.
func _build_resource_id_list(pool: ResourcePool, seed_value: int) -> Array[StringName]:
	var resource_ids: Array[StringName] = []
	for resource in pool.resources:
		if resource != null and not String(resource.id).is_empty():
			resource_ids.append(resource.id)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(resource_ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: StringName = resource_ids[i]
		resource_ids[i] = resource_ids[j]
		resource_ids[j] = tmp
	return resource_ids

func _least_used_resource(resource_ids: Array[StringName], counts: Dictionary) -> StringName:
	var best: StringName = resource_ids[0] if not resource_ids.is_empty() else &""
	var best_count: int = int(counts.get(best, 0))
	for rid in resource_ids:
		var c: int = int(counts.get(rid, 0))
		if c < best_count:
			best_count = c
			best = rid
	return best

func validate_resources(pool: ResourcePool = null, homeworlds: Dictionary = {}) -> PackedStringArray:
	var errors := PackedStringArray()
	var effective_pool: ResourcePool = pool if pool != null else GameState.DEFAULT_RESOURCE_POOL
	if planet_resources.is_empty():
		errors.append("resources have not been dealt")
		return errors
	if effective_pool == null or effective_pool.resources.is_empty():
		errors.append("resource pool is empty")
		return errors

	var counts: Dictionary = {}
	for planet_id in planet_resources:
		var resource_id: StringName = resource_of(planet_id as StringName)
		if String(resource_id).is_empty():
			errors.append("planet %s has no resource" % planet_id)
			continue
		counts[resource_id] = int(counts.get(resource_id, 0)) + 1

	var homeworld_resources: Dictionary = {}
	for planet_id_value in homeworlds.values():
		var planet_id: StringName = planet_id_value as StringName
		var resource_id: StringName = resource_of(planet_id)
		if String(resource_id).is_empty():
			continue
		if homeworld_resources.has(resource_id):
			errors.append("homeworlds share resource %s" % resource_id)
		homeworld_resources[resource_id] = true

	if counts.size() < effective_pool.resources.size():
		errors.append("not every pool resource is represented")
	if counts.size() > 1:
		var min_count := 1 << 30
		var max_count := 0
		for count in counts.values():
			min_count = mini(min_count, int(count))
			max_count = maxi(max_count, int(count))
		if max_count - min_count > 1:
			errors.append("resource distribution is unbalanced")
	return errors

func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = value

func has_planet_upgrade(planet_id: StringName, upgrade_id: StringName) -> bool:
	if not planet_upgrades.has(planet_id):
		return false
	var list: Array = planet_upgrades[planet_id]
	return list.has(upgrade_id)

func get_planet_upgrades(planet_id: StringName) -> Array[StringName]:
	if not planet_upgrades.has(planet_id):
		return []
	var typed_list: Array[StringName] = []
	for item in planet_upgrades[planet_id]:
		typed_list.append(item as StringName)
	return typed_list

func can_purchase_upgrade(faction: StringName, planet_id: StringName, upgrade_id: StringName, available_workers: int = -1, catalog: PlanetUpgradeCatalog = null) -> bool:
	var effective_catalog: PlanetUpgradeCatalog = catalog if catalog != null else GameState.DEFAULT_UPGRADE_CATALOG
	if effective_catalog == null or faction == GameState.FACTION_NEUTRAL or not faction_vaults.has(faction):
		return false
	var upgrade: PlanetUpgradeDefinition = effective_catalog.resolve(upgrade_id)
	if upgrade == null or has_planet_upgrade(planet_id, upgrade_id):
		return false
	if not String(upgrade.parent_upgrade_id).is_empty() and not has_planet_upgrade(planet_id, upgrade.parent_upgrade_id):
		return false
	if not String(upgrade.exclusive_with).is_empty() and has_planet_upgrade(planet_id, upgrade.exclusive_with):
		return false
	if available_workers >= 0 and available_workers < upgrade.cost_workers:
		return false
	return can_spend_faction_resource(faction, upgrade.cost_resource, upgrade.cost_amount)

func purchase_upgrade(faction: StringName, planet_id: StringName, upgrade_id: StringName, available_workers: int = -1, catalog: PlanetUpgradeCatalog = null) -> bool:
	if not can_purchase_upgrade(faction, planet_id, upgrade_id, available_workers, catalog):
		return false
	var effective_catalog: PlanetUpgradeCatalog = catalog if catalog != null else GameState.DEFAULT_UPGRADE_CATALOG
	var upgrade: PlanetUpgradeDefinition = effective_catalog.resolve(upgrade_id)
	if not spend_faction_resource(faction, upgrade.cost_resource, upgrade.cost_amount):
		return false
	add_planet_upgrade(planet_id, upgrade_id)
	return true

func add_planet_upgrade(planet_id: StringName, upgrade_id: StringName) -> void:
	if String(planet_id).is_empty() or String(upgrade_id).is_empty():
		return
	if not planet_upgrades.has(planet_id):
		planet_upgrades[planet_id] = []
	var list: Array = planet_upgrades[planet_id]
	if not list.has(upgrade_id):
		list.append(upgrade_id)
		planet_upgrades[planet_id] = list
		planet_upgraded.emit(planet_id, upgrade_id)

func has_worker_factory(planet_id: StringName) -> bool:
	return worker_factories.get(planet_id, false) as bool

func can_build_worker_factory(
	faction: StringName,
	planet_id: StringName,
	has_shipyard: bool,
	first_scan_done: bool,
	has_automation_tech: bool,
	available_slots: int = -1,
	cost_resource: StringName = GameState.RES_MATERIAL,
	cost_amount: int = 5
) -> bool:
	if faction == GameState.FACTION_NEUTRAL or not faction_vaults.has(faction) or has_worker_factory(planet_id):
		return false
	if not has_shipyard or not first_scan_done or not has_automation_tech:
		return false
	if available_slots >= 0 and available_slots <= 0:
		return false
	return can_spend_faction_resource(faction, cost_resource, cost_amount)

func build_worker_factory(
	faction: StringName,
	planet_id: StringName,
	has_shipyard: bool,
	first_scan_done: bool,
	has_automation_tech: bool,
	available_slots: int = -1,
	cost_resource: StringName = GameState.RES_MATERIAL,
	cost_amount: int = 5
) -> bool:
	if not can_build_worker_factory(faction, planet_id, has_shipyard, first_scan_done, has_automation_tech, available_slots, cost_resource, cost_amount):
		return false
	if not spend_faction_resource(faction, cost_resource, cost_amount):
		return false
	worker_factories[planet_id] = true
	worker_factory_built.emit(planet_id)
	return true

func register_gathering_workers(faction: StringName, planet_id: StringName, source_planet_id: StringName, count: int) -> void:
	if String(faction).is_empty() or String(planet_id).is_empty() or count <= 0:
		return
	if not gathering_workers.has(faction):
		gathering_workers[faction] = {}
	if not gathering_sources.has(faction):
		gathering_sources[faction] = {}
	var current: int = gathering_workers[faction].get(planet_id, 0)
	gathering_workers[faction][planet_id] = current + count
	gathering_sources[faction][planet_id] = source_planet_id
	gathering_started.emit(faction, planet_id, count)

func get_gathering_source(faction: StringName, planet_id: StringName) -> StringName:
	if not gathering_sources.has(faction):
		return &""
	return gathering_sources[faction].get(planet_id, &"") as StringName

func withdraw_gathering_workers(faction: StringName, planet_id: StringName, amount: int = -1) -> Dictionary:
	if not gathering_workers.has(faction) or not gathering_workers[faction].has(planet_id):
		return {"count": 0, "source_planet_id": &""}
	var current: int = gathering_workers[faction].get(planet_id, 0)
	var count: int = current if amount < 0 else mini(current, maxi(amount, 0))
	var source_planet_id: StringName = get_gathering_source(faction, planet_id)
	if count <= 0:
		return {"count": 0, "source_planet_id": source_planet_id}
	var remaining := current - count
	if remaining <= 0:
		gathering_workers[faction].erase(planet_id)
		if gathering_sources.has(faction):
			gathering_sources[faction].erase(planet_id)
	else:
		gathering_workers[faction][planet_id] = remaining
	if count > 0:
		gathering_withdrawn.emit(faction, planet_id, count)
	return {"count": count, "source_planet_id": source_planet_id}

func gathering_workers_on(faction: StringName, planet_id: StringName) -> int:
	if not gathering_workers.has(faction):
		return 0
	return int(gathering_workers[faction].get(planet_id, 0))

func gather_income_tick(base_amounts: Dictionary, catalog: PlanetUpgradeCatalog = null) -> int:
	var effective_catalog: PlanetUpgradeCatalog = catalog if catalog != null else GameState.DEFAULT_UPGRADE_CATALOG
	var total_earned := 0
	for faction in gathering_workers:
		var faction_name := faction as StringName
		var planets: Dictionary = gathering_workers[faction]
		for p_id in planets:
			var planet_id := p_id as StringName
			var count: int = planets[p_id]
			if count <= 0:
				continue
			var res_id: StringName = resource_of(planet_id)
			if not _is_valid_resource_id(res_id):
				continue
			var base_amt: int = maxi(int(base_amounts.get(planet_id, 1)), 1)
			var gather_multiplier := 1.0
			if effective_catalog != null:
				for upgrade_id in get_planet_upgrades(planet_id):
					var upgrade: PlanetUpgradeDefinition = effective_catalog.resolve(upgrade_id)
					if upgrade != null and upgrade.trait_definition != null:
						gather_multiplier *= upgrade.trait_definition.gather_income_multiplier
			var earned: int = maxi(1, int(round(float(count * base_amt) * gather_multiplier)))
			add_faction_resource(faction_name, res_id, earned)
			total_earned += earned
			resources_collected.emit(faction_name, planet_id, res_id, earned)
	return total_earned

# Generates consumed-amount of the planet's resource for its owning faction,
# applying per-upgrade production boosts and per-planet tech multipliers.
# Maintenance costs are subtracted best-effort (refinery upgrade may leave the
# faction broke — production is still added).
func generate_resources_for_planet(
	planet_id: StringName,
	faction_domain: FactionDomain,
	tech: TechDomain,
	catalog: PlanetUpgradeCatalog,
	base_amount: int = 1
) -> int:
	var faction: StringName = faction_domain.faction_of(planet_id)
	if faction == GameState.FACTION_NEUTRAL or not faction_vaults.has(faction):
		return 0
	var resource_id: StringName = resource_of(planet_id)
	if String(resource_id).is_empty() or not _is_valid_resource_id(resource_id):
		return 0
	var multiplier := 1.0
	for up_id in get_planet_upgrades(planet_id):
		var def: PlanetUpgradeDefinition = catalog.resolve(up_id) if catalog != null else null
		if def != null and def.trait_definition != null:
			multiplier += def.trait_definition.production_boost
			var maintenance_resource: StringName = def.trait_definition.maintenance_cost_resource
			if not String(maintenance_resource).is_empty() and def.trait_definition.maintenance_cost_amount > 0:
				spend_faction_resource(faction, maintenance_resource, def.trait_definition.maintenance_cost_amount)
	for planet_technology_id in tech.get_planet_technologies(planet_id):
		var planet_technology: TechnologyDefinition = GameState.DEFAULT_TECHNOLOGY_CATALOG.resolve(planet_technology_id)
		if planet_technology != null:
			multiplier *= planet_technology.production_multiplier
	var final_amount: int = maxi(1, int(round(float(maxi(base_amount, 1)) * multiplier)))
	add_faction_resource(faction, resource_id, final_amount)
	resource_generated.emit(planet_id, resource_id, final_amount)
	return final_amount

# Material→Rare conversion (refinery upgrade only). Refunds the spent material
# if energy runs short mid-transaction; emits refinery_converted on success.
func convert_refinery_resources(planet_id: StringName, faction_domain: FactionDomain) -> Dictionary:
	var faction: StringName = faction_domain.faction_of(planet_id)
	if faction == GameState.FACTION_NEUTRAL or not faction_vaults.has(faction) or not has_planet_upgrade(planet_id, &"refinery"):
		return {"converted": false}
	var material: int = get_faction_resource(faction, GameState.RES_MATERIAL)
	var energy: int = get_faction_resource(faction, GameState.RES_ENERGY)
	if material < 2 or energy < 1:
		return {"converted": false}
	if not spend_faction_resource(faction, GameState.RES_MATERIAL, 2):
		return {"converted": false}
	if not spend_faction_resource(faction, GameState.RES_ENERGY, 1):
		add_faction_resource(faction, GameState.RES_MATERIAL, 2)
		return {"converted": false}
	var produced_resource: StringName = GameState.RES_RARE
	add_faction_resource(faction, produced_resource, 1)
	var consumed := {GameState.RES_MATERIAL: 2, GameState.RES_ENERGY: 1}
	var produced := {produced_resource: 1}
	refinery_converted.emit(planet_id, faction, consumed, produced)
	return {"converted": true, "consumed": consumed, "produced": produced}

# Local copy of GameState.is_valid_resource — calling the static via the autoload
# instance triggers a STATIC_CALLED_ON_INSTANCE warning under Godot's parser.
func _is_valid_resource_id(resource_id: StringName) -> bool:
	return resource_id == GameState.RES_ENERGY or resource_id == GameState.RES_BIOMASS or resource_id == GameState.RES_RARE or resource_id == GameState.RES_MATERIAL or resource_id == GameState.RES_VOLATILE

# --- LOCAL VAULTS (per-planet) ---

func local_vault(planet_id: StringName) -> Dictionary:
	if not local_vaults.has(planet_id):
		local_vaults[planet_id] = GameState.DEFAULT_RESOURCE_POOL.empty_vault()
	return local_vaults[planet_id]

func get_local_resource(planet_id: StringName, resource_id: StringName) -> int:
	return int(local_vault(planet_id).get(resource_id, 0))

func add_local_resource(planet_id: StringName, resource_id: StringName, amount: int) -> int:
	if amount <= 0 or String(planet_id).is_empty() or not _is_valid_resource_id(resource_id):
		return get_local_resource(planet_id, resource_id)
	var vault := local_vault(planet_id)
	var new_val := get_local_resource(planet_id, resource_id) + amount
	vault[resource_id] = new_val
	local_vaults[planet_id] = vault
	local_resources_changed.emit(planet_id, resource_id, new_val)
	return new_val

func spend_local_resource(planet_id: StringName, resource_id: StringName, amount: int) -> bool:
	if amount < 0:
		return false
	if amount == 0:
		return true
	if get_local_resource(planet_id, resource_id) < amount:
		return false
	var vault := local_vault(planet_id)
	var new_val := get_local_resource(planet_id, resource_id) - amount
	vault[resource_id] = new_val
	local_vaults[planet_id] = vault
	local_resources_changed.emit(planet_id, resource_id, new_val)
	return true

func transfer_resources(from_planet: StringName, to_planet: StringName, resource_id: StringName, amount: int) -> bool:
	if amount <= 0 or from_planet == to_planet:
		return false
	if not spend_local_resource(from_planet, resource_id, amount):
		return false
	add_local_resource(to_planet, resource_id, amount)
	resource_transferred.emit(from_planet, to_planet, resource_id, amount)
	return true

## Seeds a small deterministic starting stock of each planet's own resource.
func seed_local_resources(planet_ids: Array, pool: ResourcePool = null, seed_value: int = 0) -> void:
	var effective_pool: ResourcePool = pool if pool != null else GameState.DEFAULT_RESOURCE_POOL
	if effective_pool == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for planet_id_value in planet_ids:
		var planet_id: StringName = planet_id_value as StringName
		if _local_seeded_planets.has(planet_id):
			continue
		var res_id: StringName = resource_of(planet_id)
		if String(res_id).is_empty():
			continue
		var vault := local_vault(planet_id)
		var starting := maxi(1, rng.randi_range(2, 8))
		vault[res_id] = int(vault.get(res_id, 0)) + starting
		local_vaults[planet_id] = vault
		_local_seeded_planets[planet_id] = true

# --- BUILDINGS ON GRID ---

func can_spend_building_cost(faction: StringName, building: BuildingDefinition) -> bool:
	if building == null or building.cost_resources.is_empty():
		return true
	for resource_id in building.cost_resources:
		var amount: int = int(building.cost_resources[resource_id])
		if amount > 0 and not can_spend_faction_resource(faction, resource_id as StringName, amount):
			return false
	return true

func spend_building_cost(faction: StringName, building: BuildingDefinition) -> bool:
	if not can_spend_building_cost(faction, building):
		return false
	for resource_id in building.cost_resources:
		var amount: int = int(building.cost_resources[resource_id])
		if amount > 0:
			spend_faction_resource(faction, resource_id as StringName, amount)
	return true

func record_planet_building(planet_id: StringName, building_id: StringName, q: int, r: int) -> void:
	if String(planet_id).is_empty() or String(building_id).is_empty():
		return
	if not planet_buildings.has(planet_id):
		planet_buildings[planet_id] = {}
	planet_buildings[planet_id]["%d:%d" % [q, r]] = building_id
	building_placed.emit(planet_id, building_id, q, r)

func remove_planet_building(planet_id: StringName, q: int, r: int) -> StringName:
	if not planet_buildings.has(planet_id):
		return &""
	var key := "%d:%d" % [q, r]
	var removed: StringName = planet_buildings[planet_id].get(key, &"") as StringName
	if String(removed).is_empty():
		return &""
	planet_buildings[planet_id].erase(key)
	building_removed.emit(planet_id, q, r)
	return removed

func planet_building_at(planet_id: StringName, q: int, r: int) -> StringName:
	if not planet_buildings.has(planet_id):
		return &""
	return planet_buildings[planet_id].get("%d:%d" % [q, r], &"") as StringName

func planet_buildings_of(planet_id: StringName) -> Dictionary:
	return planet_buildings.get(planet_id, {}).duplicate()

# --- TRADE ROUTES ---

func register_trade_route(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> StringName:
	if String(from_planet).is_empty() or String(to_planet).is_empty() or from_planet == to_planet:
		return &""
	var route_id := StringName("route_%d" % trade_routes.size())
	trade_routes[route_id] = {
		"from": from_planet,
		"to": to_planet,
		"resource_id": resource_id,
		"flow_rate": 1,
		"active": true,
	}
	return route_id

func trade_routes_snapshot() -> Dictionary:
	return trade_routes.duplicate()

func tick_trade_routes() -> int:
	var moved := 0
	for route_id in trade_routes:
		var route: Dictionary = trade_routes[route_id]
		if not bool(route.get("active", false)):
			continue
		var resource_id: StringName = route["resource_id"]
		var amount: int = int(route.get("flow_rate", 1))
		var from_planet: StringName = route["from"]
		var to_planet: StringName = route["to"]
		if transfer_resources(from_planet, to_planet, resource_id, amount):
			moved += amount
	return moved
