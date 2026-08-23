class_name EconomyDomain
extends RefCounted

## Manages faction vaults, resource deals, planet upgrades, worker factories, and gathering state.

const DEFAULT_ECONOMY_CONFIG: EconomyConfig = preload("res://resources/config/economy_default.tres")

var economy_config: EconomyConfig = DEFAULT_ECONOMY_CONFIG
var _next_trade_route_index: int = 0
var _trade_tick_index: int = 0
var market_prices: Dictionary = {}
var trade_volumes: Dictionary = {}
var worker_transport_records: Dictionary = {}
var _next_worker_transport_index: int = 0

signal faction_resources_changed(faction: StringName, resource_id: StringName, new_amount: int)
signal credits_changed(faction: StringName, new_amount: int)
signal workers_reserved(planet_id: StringName, job_id: StringName, amount: int)
signal workers_released(planet_id: StringName, job_id: StringName, amount: int)
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
var faction_credits: Dictionary = {}
var worker_reservations: Dictionary = {}
var upgrade_build_jobs: Dictionary = {}
var planet_resources: Dictionary = {}
var planet_upgrades: Dictionary = {}
var worker_factories: Dictionary = {}
var gathering_workers: Dictionary = {}
var gathering_sources: Dictionary = {}
var local_vaults: Dictionary = {}
var trade_routes: Dictionary = {}
var planet_buildings: Dictionary = {}
var building_jobs: Dictionary = {}
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
	var config: EconomyConfig = economy_config if economy_config != null else DEFAULT_ECONOMY_CONFIG
	faction_credits = {
		GameState.FACTION_PLAYER: config.starting_credits,
		GameState.FACTION_CPU: config.starting_credits,
	}

func reset() -> void:
	planet_resources.clear()
	planet_upgrades.clear()
	worker_reservations.clear()
	upgrade_build_jobs.clear()
	worker_factories.clear()
	gathering_workers.clear()
	gathering_sources.clear()
	local_vaults.clear()
	trade_routes.clear()
	planet_buildings.clear()
	building_jobs.clear()
	market_prices.clear()
	trade_volumes.clear()
	_next_trade_route_index = 0
	_trade_tick_index = 0
	worker_transport_records.clear()
	_next_worker_transport_index = 0
	_local_seeded_planets.clear()
	reset_vaults()

func credit_transport_resources(faction: StringName, resource_id: StringName, amount: int) -> bool:
	if amount <= 0 or not _is_valid_resource_id(resource_id):
		return false
	add_faction_resource(faction, resource_id, amount)
	return true

func get_faction_credits(faction: StringName) -> int:
	return int(faction_credits.get(faction, 0))

## Creates the data-side record for a physical worker round-trip. The visible
## WorkerCluster is disposable; this record is the source of truth across
## chunk cycling and scene rebuilds.
func begin_worker_transport(faction: StringName, source_planet_id: StringName, destination_planet_id: StringName, amount: int, duration: float, route_path: Array[Vector2]) -> StringName:
	if faction == GameState.FACTION_NEUTRAL or String(source_planet_id).is_empty() or String(destination_planet_id).is_empty() or amount <= 0:
		return &""
	_next_worker_transport_index += 1
	var transport_id := StringName("worker_transport_%d" % _next_worker_transport_index)
	worker_transport_records[transport_id] = {
		"transport_id": transport_id,
		"faction": faction,
		"source_planet_id": source_planet_id,
		"destination_planet_id": destination_planet_id,
		"amount": amount,
		"phase": &"outbound",
		"cargo_amount": 0,
		"cargo_resource_id": &"",
		"duration": maxf(duration, 0.001),
		"elapsed": 0.0,
		"route_path": route_path.duplicate(),
		"escorted": false,
	}
	return transport_id

func update_worker_transport(transport_id: StringName, phase: StringName, cargo_resource_id: StringName = &"", cargo_amount: int = 0) -> bool:
	if not worker_transport_records.has(transport_id):
		return false
	var record: Dictionary = worker_transport_records[transport_id]
	record["phase"] = phase
	if not String(cargo_resource_id).is_empty():
		record["cargo_resource_id"] = cargo_resource_id
	record["cargo_amount"] = maxi(cargo_amount, 0)
	worker_transport_records[transport_id] = record
	return true

func set_worker_transport_escorted(transport_id: StringName, escorted: bool = true) -> bool:
	if not worker_transport_records.has(transport_id):
		return false
	var record: Dictionary = worker_transport_records[transport_id]
	record["escorted"] = escorted
	worker_transport_records[transport_id] = record
	return true

func get_worker_transport_records(faction: StringName = &"") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in worker_transport_records.values():
		var record: Dictionary = value as Dictionary
		if record != null and (String(faction).is_empty() or record.get("faction", &"") == faction):
			result.append(record.duplicate(true))
	return result

func complete_worker_transport(transport_id: StringName, delivered: bool = true) -> bool:
	if not worker_transport_records.has(transport_id):
		return false
	var record: Dictionary = worker_transport_records[transport_id]
	record["phase"] = &"delivered" if delivered else &"cancelled"
	worker_transport_records.erase(transport_id)
	return true

func add_faction_credits(faction: StringName, amount: int) -> int:
	if amount <= 0 or String(faction).is_empty():
		return get_faction_credits(faction)
	var new_amount: int = get_faction_credits(faction) + amount
	faction_credits[faction] = new_amount
	credits_changed.emit(faction, new_amount)
	return new_amount

func can_spend_faction_credits(faction: StringName, amount: int) -> bool:
	return amount <= 0 or get_faction_credits(faction) >= amount

func spend_faction_credits(faction: StringName, amount: int) -> bool:
	if amount < 0 or not can_spend_faction_credits(faction, amount):
		return false
	if amount == 0:
		return true
	faction_credits[faction] = get_faction_credits(faction) - amount
	credits_changed.emit(faction, faction_credits[faction])
	return true

func can_spend_cost(faction: StringName, resource_id: StringName, resource_amount: int, credit_amount: int) -> bool:
	return can_spend_faction_resource(faction, resource_id, resource_amount) and can_spend_faction_credits(faction, credit_amount)

func spend_cost(faction: StringName, resource_id: StringName, resource_amount: int, credit_amount: int) -> bool:
	if not can_spend_cost(faction, resource_id, resource_amount, credit_amount):
		return false
	if not spend_faction_resource(faction, resource_id, resource_amount):
		return false
	return spend_faction_credits(faction, credit_amount)

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

func available_workers(planet_id: StringName, total_workers: int) -> int:
	var reserved := 0
	if worker_reservations.has(planet_id):
		for amount in (worker_reservations[planet_id] as Dictionary).values():
			reserved += int(amount)
	return maxi(0, total_workers - reserved)

func reserve_workers(planet_id: StringName, job_id: StringName, amount: int, total_workers: int) -> bool:
	if amount <= 0:
		return true
	if available_workers(planet_id, total_workers) < amount:
		return false
	if not worker_reservations.has(planet_id):
		worker_reservations[planet_id] = {}
	var jobs: Dictionary = worker_reservations[planet_id]
	jobs[job_id] = int(jobs.get(job_id, 0)) + amount
	workers_reserved.emit(planet_id, job_id, amount)
	return true

func release_workers(planet_id: StringName, job_id: StringName) -> int:
	if not worker_reservations.has(planet_id):
		return 0
	var jobs: Dictionary = worker_reservations[planet_id]
	var amount: int = int(jobs.get(job_id, 0))
	jobs.erase(job_id)
	if jobs.is_empty():
		worker_reservations.erase(planet_id)
	if amount > 0:
		workers_released.emit(planet_id, job_id, amount)
	return amount

func can_purchase_upgrade(faction: StringName, planet_id: StringName, upgrade_id: StringName, available_workers: int = -1, catalog: PlanetUpgradeCatalog = null) -> bool:
	var effective_catalog: PlanetUpgradeCatalog = catalog if catalog != null else GameState.DEFAULT_UPGRADE_CATALOG
	if effective_catalog == null or faction == GameState.FACTION_NEUTRAL or not faction_vaults.has(faction):
		return false
	var upgrade: PlanetUpgradeDefinition = effective_catalog.resolve(upgrade_id)
	if upgrade == null or has_planet_upgrade(planet_id, upgrade_id):
		return false
	if upgrade_build_jobs.has(planet_id) and (upgrade_build_jobs[planet_id] as Dictionary).has(upgrade_id):
		return false
	if not effective_catalog.can_unlock(get_planet_upgrades(planet_id), upgrade_id):
		return false
	if available_workers >= 0 and available_workers < upgrade.workers_required:
		return false
	return can_spend_cost(faction, upgrade.cost_resource, upgrade.cost_amount, upgrade.credit_cost)

func purchase_upgrade(faction: StringName, planet_id: StringName, upgrade_id: StringName, available_workers: int = -1, catalog: PlanetUpgradeCatalog = null) -> bool:
	if not can_purchase_upgrade(faction, planet_id, upgrade_id, available_workers, catalog):
		return false
	var effective_catalog: PlanetUpgradeCatalog = catalog if catalog != null else GameState.DEFAULT_UPGRADE_CATALOG
	var upgrade: PlanetUpgradeDefinition = effective_catalog.resolve(upgrade_id)
	var reservation_id := StringName("upgrade_%s_%s" % [String(planet_id), String(upgrade_id)])
	if upgrade.workers_required > 0 and available_workers >= 0 and not reserve_workers(planet_id, reservation_id, upgrade.workers_required, available_workers):
		return false
	if not spend_cost(faction, upgrade.cost_resource, upgrade.cost_amount, upgrade.credit_cost):
		release_workers(planet_id, reservation_id)
		return false
	if upgrade.build_time > 0.0:
		if not upgrade_build_jobs.has(planet_id):
			upgrade_build_jobs[planet_id] = {}
		upgrade_build_jobs[planet_id][upgrade_id] = {
			"remaining": upgrade.build_time,
			"faction": faction,
			"reservation_id": reservation_id,
			"cost_resource": upgrade.cost_resource,
			"cost_amount": upgrade.cost_amount,
			"credit_cost": upgrade.credit_cost,
		}
	else:
		add_planet_upgrade(planet_id, upgrade_id)
		# Instant jobs still reserve and release labor atomically.
		release_workers(planet_id, reservation_id)
	return true

func upgrade_build_in_progress(planet_id: StringName, upgrade_id: StringName = &"") -> bool:
	if not upgrade_build_jobs.has(planet_id):
		return false
	if String(upgrade_id).is_empty():
		return not (upgrade_build_jobs[planet_id] as Dictionary).is_empty()
	return (upgrade_build_jobs[planet_id] as Dictionary).has(upgrade_id)

func upgrade_build_remaining(planet_id: StringName, upgrade_id: StringName) -> float:
	if not upgrade_build_in_progress(planet_id, upgrade_id):
		return 0.0
	return float((upgrade_build_jobs[planet_id] as Dictionary)[upgrade_id].get("remaining", 0.0))

func advance_upgrade_builds(delta: float) -> void:
	if delta <= 0.0:
		return
	for planet_value in upgrade_build_jobs.keys():
		var planet_id: StringName = planet_value as StringName
		var jobs: Dictionary = upgrade_build_jobs[planet_id]
		for upgrade_value in jobs.keys():
			var upgrade_id: StringName = upgrade_value as StringName
			var job: Dictionary = jobs[upgrade_id]
			var remaining: float = float(job.get("remaining", 0.0)) - delta
			if remaining > 0.0:
				job["remaining"] = remaining
				continue
			jobs.erase(upgrade_id)
			add_planet_upgrade(planet_id, upgrade_id)
			release_workers(planet_id, job.get("reservation_id", &"") as StringName)
		if jobs.is_empty():
			upgrade_build_jobs.erase(planet_id)

func abort_upgrade_build(planet_id: StringName, upgrade_id: StringName) -> bool:
	if not upgrade_build_in_progress(planet_id, upgrade_id):
		return false
	var job: Dictionary = (upgrade_build_jobs[planet_id] as Dictionary).get(upgrade_id, {})
	(upgrade_build_jobs[planet_id] as Dictionary).erase(upgrade_id)
	release_workers(planet_id, job.get("reservation_id", &"") as StringName)
	add_faction_resource(job.get("faction", &"") as StringName, job.get("cost_resource", &"") as StringName, int(job.get("cost_amount", 0)))
	add_faction_credits(job.get("faction", &"") as StringName, int(job.get("credit_cost", 0)))
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
	cost_amount: int = 5,
	credit_cost: int = 5
) -> bool:
	if faction == GameState.FACTION_NEUTRAL or not faction_vaults.has(faction) or has_worker_factory(planet_id):
		return false
	if not has_shipyard or not first_scan_done or not has_automation_tech:
		return false
	if available_slots >= 0 and available_slots <= 0:
		return false
	return can_spend_cost(faction, cost_resource, cost_amount, credit_cost)

func build_worker_factory(
	faction: StringName,
	planet_id: StringName,
	has_shipyard: bool,
	first_scan_done: bool,
	has_automation_tech: bool,
	available_slots: int = -1,
	cost_resource: StringName = GameState.RES_MATERIAL,
	cost_amount: int = 5,
	credit_cost: int = 5
) -> bool:
	if not can_build_worker_factory(faction, planet_id, has_shipyard, first_scan_done, has_automation_tech, available_slots, cost_resource, cost_amount, credit_cost):
		return false
	if not spend_cost(faction, cost_resource, cost_amount, credit_cost):
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
			if def.trait_definition.maintenance_credit_cost > 0:
				spend_faction_credits(faction, def.trait_definition.maintenance_credit_cost)
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
	if building == null or not can_spend_faction_credits(faction, building.credit_cost):
		return false
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
	return spend_faction_credits(faction, building.credit_cost)

func queue_planet_building(planet_id: StringName, building_id: StringName, q: int, r: int, faction: StringName, reservation_id: StringName, build_time: float, costs: Dictionary) -> bool:
	var key := "%d:%d" % [q, r]
	if planet_building_at(planet_id, q, r) != &"" or building_jobs.get(planet_id, {}).has(key):
		return false
	if not building_jobs.has(planet_id):
		building_jobs[planet_id] = {}
	building_jobs[planet_id][key] = {
		"building_id": building_id,
		"q": q,
		"r": r,
		"faction": faction,
		"reservation_id": reservation_id,
		"remaining": maxf(build_time, 0.001),
		"costs": costs.duplicate(true),
	}
	return true

func building_job_in_progress(planet_id: StringName, q: int, r: int) -> bool:
	return building_jobs.has(planet_id) and (building_jobs[planet_id] as Dictionary).has("%d:%d" % [q, r])

func advance_building_jobs(delta: float) -> void:
	if delta <= 0.0:
		return
	for planet_value in building_jobs.keys():
		var planet_id: StringName = planet_value as StringName
		var jobs: Dictionary = building_jobs[planet_id]
		for key in jobs.keys():
			var job: Dictionary = jobs[key]
			var remaining: float = float(job.get("remaining", 0.0)) - delta
			if remaining > 0.0:
				job["remaining"] = remaining
				continue
			jobs.erase(key)
			record_planet_building(planet_id, job.get("building_id", &"") as StringName, int(job.get("q", 0)), int(job.get("r", 0)))
			release_workers(planet_id, job.get("reservation_id", &"") as StringName)
		if jobs.is_empty():
			building_jobs.erase(planet_id)

func abort_building_job(planet_id: StringName, q: int, r: int) -> bool:
	var key := "%d:%d" % [q, r]
	if not building_job_in_progress(planet_id, q, r):
		return false
	var job: Dictionary = (building_jobs[planet_id] as Dictionary).get(key, {})
	(building_jobs[planet_id] as Dictionary).erase(key)
	release_workers(planet_id, job.get("reservation_id", &"") as StringName)
	var faction: StringName = job.get("faction", &"") as StringName
	var costs: Dictionary = job.get("costs", {}) as Dictionary
	for resource_id in costs.get("resources", {}).keys():
		add_faction_resource(faction, resource_id as StringName, int(costs["resources"][resource_id]))
	add_faction_credits(faction, int(costs.get("credits", 0)))
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

func can_register_trade_route(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> bool:
	if String(from_planet).is_empty() or String(to_planet).is_empty() or from_planet == to_planet or not _is_valid_resource_id(resource_id):
		return false
	var owner: StringName = _route_owner(from_planet)
	if owner == GameState.FACTION_NEUTRAL:
		return true
	# A route becomes a market connection only when at least one endpoint is
	# backed by a trade post/network upgrade. Neutral synthetic test planets
	# remain valid for deterministic local-vault tests.
	return has_planet_upgrade(from_planet, &"trade_post") or has_planet_upgrade(from_planet, &"trade_network") or has_planet_upgrade(to_planet, &"trade_post") or has_planet_upgrade(to_planet, &"trade_network")

func register_trade_route(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> StringName:
	if not can_register_trade_route(from_planet, to_planet, resource_id):
		return &""
	_next_trade_route_index += 1
	var route_id := StringName("route_%d" % _next_trade_route_index)
	trade_routes[route_id] = {
		"from": from_planet,
		"to": to_planet,
		"resource_id": resource_id,
		"flow_rate": 1,
		"active": true,
		"volume": 0,
		"last_price": market_price(from_planet, to_planet, resource_id),
		"toll_credits": 0,
	}
	return route_id

func market_price(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> float:
	if not _is_valid_resource_id(resource_id):
		return 0.0
	var source_stock: int = get_local_resource(from_planet, resource_id)
	var destination_stock: int = get_local_resource(to_planet, resource_id)
	# Scarcity at the destination raises the price, while source abundance
	# lowers it. Clamp it to keep the credit economy stable and deterministic.
	var scarcity: float = clampf(float(destination_stock - source_stock) / 20.0, -0.5, 1.5)
	var price: float = clampf(1.0 + scarcity, 0.5, 2.5)
	market_prices[StringName("%s:%s:%s" % [String(from_planet), String(to_planet), String(resource_id)])] = price
	return price

func get_market_price(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> float:
	var key := StringName("%s:%s:%s" % [String(from_planet), String(to_planet), String(resource_id)])
	return float(market_prices.get(key, market_price(from_planet, to_planet, resource_id)))

func trade_routes_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	for route_id in trade_routes:
		snapshot[route_id] = (trade_routes[route_id] as Dictionary).duplicate()
	return snapshot

func tick_trade_routes() -> int:
	_trade_tick_index += 1
	var moved := 0
	var config: EconomyConfig = economy_config if economy_config != null else DEFAULT_ECONOMY_CONFIG
	for route_id in trade_routes:
		var route: Dictionary = trade_routes[route_id]
		if not bool(route.get("active", false)):
			continue
		var resource_id: StringName = route["resource_id"] as StringName
		var amount: int = maxi(int(route.get("flow_rate", 1)), 1)
		var from_planet: StringName = route["from"] as StringName
		var to_planet: StringName = route["to"] as StringName
		var price: float = market_price(from_planet, to_planet, resource_id)
		if transfer_resources(from_planet, to_planet, resource_id, amount):
			moved += amount
			var volume: int = int(route.get("volume", 0)) + amount
			var toll: int = maxi(1, int(round(float(amount) * price * config.market_toll_rate)))
			route["volume"] = volume
			route["last_price"] = price
			route["toll_credits"] = int(route.get("toll_credits", 0)) + toll
			trade_volumes[resource_id] = int(trade_volumes.get(resource_id, 0)) + amount
			# Test fixtures use synthetic planets without ownership. In a live run,
			# the route owner receives the tariff; neutral routes simply move cargo.
			var owner: StringName = _route_owner(from_planet)
			if owner != GameState.FACTION_NEUTRAL:
				add_faction_credits(owner, toll)
		trade_routes[route_id] = route
	return moved

func _route_owner(planet_id: StringName) -> StringName:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var state: Node = tree.root.get_node_or_null("GameState") if tree != null and tree.root != null else null
	if state != null and state.has_method("faction_of"):
		return state.faction_of(planet_id)
	return GameState.FACTION_NEUTRAL

func market_snapshot() -> Dictionary:
	return {"prices": market_prices.duplicate(), "volumes": trade_volumes.duplicate(), "routes": trade_routes_snapshot()}
