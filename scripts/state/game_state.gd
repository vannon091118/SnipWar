extends Node

const FACTION_PLAYER := &"a"
const FACTION_CPU := &"b"
const FACTION_NEUTRAL := &"neutral"

const MISSION_MILITARY := &"military"
const MISSION_CARGO := &"cargo"
const MISSION_COLONY := &"colony"
const MISSION_COLLECT := &"collect"
const TECH_WORKER_AUTOMATION := &"worker_automation"

## Canonical resource IDs. These are the single source of truth for vault
## keys, refinery inputs/outputs, upgrade costs and technology costs.
## Use GameState.RES_* instead of typed-out "&"energy"/&"biomass"/... literals
## anywhere else -- a typo like &"energi" would otherwise silently miss.
const RES_ENERGY: StringName = &"energy"
const RES_BIOMASS: StringName = &"biomass"
const RES_RARE: StringName = &"rare"
const RES_MATERIAL: StringName = &"material"
const RES_VOLATILE: StringName = &"volatile"

const ALL_RESOURCES: Array[StringName] = [
	RES_ENERGY,
	RES_BIOMASS,
	RES_RARE,
	RES_MATERIAL,
	RES_VOLATILE,
]

static func is_valid_resource(resource_id: StringName) -> bool:
	return resource_id == RES_ENERGY or resource_id == RES_BIOMASS or resource_id == RES_RARE or resource_id == RES_MATERIAL or resource_id == RES_VOLATILE

const DEFAULT_RESOURCE_POOL: ResourcePool = preload("res://resources/config/resource_pool_default.tres")
const DEFAULT_UPGRADE_CATALOG: PlanetUpgradeCatalog = preload("res://resources/config/planet_upgrade_catalog_default.tres")
const DEFAULT_TECHNOLOGY_CATALOG: TechnologyCatalog = preload("res://resources/config/technology_catalog_default.tres")
const DEFAULT_SHIP_PART_CATALOG: ShipPartCatalog = preload("res://resources/config/ship_part_catalog_default.tres")

signal faction_changed(planet_id: StringName, old_faction: StringName, new_faction: StringName)
signal catalog_reset(catalog: PlanetCatalog)
signal faction_resources_changed(faction: StringName, resource_id: StringName, new_amount: int)
signal planet_upgraded(planet_id: StringName, upgrade_id: StringName)
signal resource_generated(planet_id: StringName, resource_id: StringName, amount: int)
signal planet_discovered(faction: StringName, planet_id: StringName)
signal planet_scanned(faction: StringName, planet_id: StringName, resource_id: StringName, size_id: StringName, build_slots: int)
signal technology_researched(faction: StringName, technology_id: StringName)
signal planet_technology_researched(planet_id: StringName, technology_id: StringName)
signal resources_collected(faction: StringName, planet_id: StringName, resource_id: StringName, amount: int)
signal gathering_started(faction: StringName, planet_id: StringName, workers: int)
signal gathering_withdrawn(faction: StringName, planet_id: StringName, workers: int)
signal worker_factory_built(planet_id: StringName)
signal ship_part_purchased(planet_id: StringName, part_id: StringName)
signal ship_assembled(planet_id: StringName, ship_id: StringName)
signal ship_disassembled(planet_id: StringName, ship_id: StringName)
signal refinery_converted(planet_id: StringName, faction: StringName, consumed: Dictionary, produced: Dictionary)
signal research_started(faction: StringName, technology_id: StringName, remaining: float)
signal ship_build_started(planet_id: StringName, ship_id: StringName, remaining: float)

var _ownership: Dictionary = {}
var _starting_workers: Dictionary = {}
var _homeworlds: Dictionary = {}
var _planet_resources: Dictionary = {}
var _planet_upgrades: Dictionary = {}
var _known_planets: Dictionary = {}
var _scanned_planets: Dictionary = {}
var _scan_intel: Dictionary = {}
var _researched_techs: Dictionary = {}
var _planet_technologies: Dictionary = {}
var _worker_factories: Dictionary = {}
var _gathering_workers: Dictionary = {}
var _gathering_sources: Dictionary = {}
var _ship_part_inventory: Dictionary = {}
var _ship_assemblies: Dictionary = {}
var _next_ship_index: int = 0
var _research_jobs: Dictionary = {}
var _ship_build_jobs: Dictionary = {}
var _jobs_auto_advance := true
var _faction_vaults: Dictionary = {
	FACTION_PLAYER: {
		GameState.RES_ENERGY: 50,
		GameState.RES_BIOMASS: 50,
		GameState.RES_RARE: 30,
		GameState.RES_MATERIAL: 30,
		GameState.RES_VOLATILE: 30
	},
	FACTION_CPU: {
		GameState.RES_ENERGY: 50,
		GameState.RES_BIOMASS: 50,
		GameState.RES_RARE: 30,
		GameState.RES_MATERIAL: 30,
		GameState.RES_VOLATILE: 30
	}
}

func reset_from_catalog(catalog: PlanetCatalog) -> void:
	_ownership.clear()
	_starting_workers.clear()
	_homeworlds.clear()
	_planet_resources.clear()
	_planet_upgrades.clear()
	_known_planets.clear()
	_scanned_planets.clear()
	_scan_intel.clear()
	_researched_techs.clear()
	_planet_technologies.clear()
	_worker_factories.clear()
	_gathering_workers.clear()
	_gathering_sources.clear()
	_ship_part_inventory.clear()
	_ship_assemblies.clear()
	_next_ship_index = 0
	_research_jobs.clear()
	_ship_build_jobs.clear()
	_reset_vaults()
	if catalog != null:
		for definition in catalog.planets:
			if definition == null:
				continue
			_ownership[definition.planet_id] = definition.faction
			if definition.planet_role == &"homeworld" and (definition.faction == FACTION_PLAYER or definition.faction == FACTION_CPU):
				_homeworlds[definition.faction] = definition.planet_id
	for planet_id in _ownership:
		_remember_planet(_ownership[planet_id] as StringName, planet_id as StringName)
	catalog_reset.emit(catalog)

func _reset_vaults() -> void:
	_faction_vaults = {
		FACTION_PLAYER: {
			GameState.RES_ENERGY: 50,
			GameState.RES_BIOMASS: 50,
			GameState.RES_RARE: 30,
			GameState.RES_MATERIAL: 30,
			GameState.RES_VOLATILE: 30
		},
		FACTION_CPU: {
			GameState.RES_ENERGY: 50,
			GameState.RES_BIOMASS: 50,
			GameState.RES_RARE: 30,
			GameState.RES_MATERIAL: 30,
			GameState.RES_VOLATILE: 30
		}
	}

func register_planet(planet_id: StringName, initial_faction: StringName) -> void:
	if String(planet_id).is_empty():
		return
	if not _ownership.has(planet_id):
		_ownership[planet_id] = initial_faction
	if not _planet_upgrades.has(planet_id):
		_planet_upgrades[planet_id] = []

func seed_starting_workers(planet_id: StringName, profile: PlanetSizeProfile) -> void:
	if String(planet_id).is_empty() or _starting_workers.has(planet_id):
		return
	_starting_workers[planet_id] = profile.starting_workers if profile != null else 0

func faction_of(planet_id: StringName) -> StringName:
	var value: Variant = _ownership.get(planet_id, FACTION_NEUTRAL)
	return value as StringName

func owns(planet_id: StringName, faction: StringName) -> bool:
	return faction_of(planet_id) == faction

func is_owned(planet_id: StringName) -> bool:
	return faction_of(planet_id) != FACTION_NEUTRAL

func set_faction(planet_id: StringName, faction: StringName) -> void:
	if String(planet_id).is_empty():
		return
	var old_faction: StringName = faction_of(planet_id)
	if old_faction == faction:
		return
	_ownership[planet_id] = faction
	_remember_planet(faction, planet_id)
	faction_changed.emit(planet_id, old_faction, faction)

func get_planet_ids_for_faction(faction: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for planet_id in _ownership:
		if _ownership[planet_id] == faction:
			result.append(planet_id as StringName)
	return result

func get_ownership_count(faction: StringName) -> int:
	return get_planet_ids_for_faction(faction).size()

func starting_workers_of(planet_id: StringName) -> int:
	var value: Variant = _starting_workers.get(planet_id, 0)
	return int(value)

func deal_resources(catalog: PlanetCatalog, pool: ResourcePool = null, deal_seed: int = 0) -> void:
	_planet_resources.clear()
	var resource_pool: ResourcePool = pool if pool != null else DEFAULT_RESOURCE_POOL
	if catalog == null or resource_pool == null or resource_pool.resources.is_empty():
		return
	var resource_ids: Array[StringName] = []
	for resource in resource_pool.resources:
		if resource != null and not String(resource.id).is_empty():
			resource_ids.append(resource.id)
	if resource_ids.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = deal_seed
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

	var total_planets: int = homeworld_defs.size() + other_defs.size()
	if total_planets == 0:
		return

	var pool_size: int = resource_ids.size()
	var base_count: int = total_planets / pool_size
	var extra_count: int = total_planets % pool_size
	var available_counts: Dictionary = {}
	for i in range(pool_size):
		var r_id: StringName = resource_ids[i]
		available_counts[r_id] = base_count + (1 if i < extra_count else 0)

	# Assign all planets — homeworlds first, then others
	var all_defs: Array[PlanetDefinition] = homeworld_defs.duplicate()
	all_defs.append_array(other_defs)

	# Tracks resources already used by a homeworld planet, so faction HWs get distinct resources.
	# Once all pool resources are used, the constraint is released and balance takes over.
	var used_homeworld_resources: Dictionary = {}

	var assigned: Dictionary = {}
	for def in all_defs:
		var chosen_res: StringName = &""
		var is_homeworld: bool = def.planet_role == &"homeworld"

		# Signature hint — accepted only when quota remains, and (for homeworlds) when not yet used
		var sig: StringName = def.signature_resource
		var prob: float = def.signature_probability
		var hw_blocks_sig: bool = is_homeworld and used_homeworld_resources.has(sig)
		# Signature: accepted regardless of remaining quota so prob=1.0 is always honoured.
		# Balance is restored by the greedy fallback on subsequent planets.
		if not String(sig).is_empty() and resource_ids.has(sig) and not hw_blocks_sig:
			if rng.randf() < prob:
				chosen_res = sig

		# Greedy fallback: pick resource with most remaining quota
		# For homeworlds: skip resources already assigned to a prior homeworld
		if String(chosen_res).is_empty():
			var best_count := -1
			for r_id in resource_ids:
				if is_homeworld and used_homeworld_resources.has(r_id):
					continue
				var cnt: int = int(available_counts.get(r_id, 0))
				if cnt > best_count:
					best_count = cnt
					chosen_res = r_id

		# Second fallback: homeworld "distinct" constraint fully saturated — pick best remaining
		if String(chosen_res).is_empty():
			var best_count := -1
			for r_id in resource_ids:
				var cnt: int = int(available_counts.get(r_id, 0))
				if cnt > best_count:
					best_count = cnt
					chosen_res = r_id

		if String(chosen_res).is_empty():
			chosen_res = resource_ids[0]

		assigned[def.planet_id] = chosen_res
		available_counts[chosen_res] = maxi(0, int(available_counts.get(chosen_res, 0)) - 1)
		if is_homeworld:
			used_homeworld_resources[chosen_res] = true

	_planet_resources = assigned

func resource_of(planet_id: StringName) -> StringName:
	var value: Variant = _planet_resources.get(planet_id, &"")
	return value as StringName

func resource_snapshot() -> Dictionary:
	return _planet_resources.duplicate()

func get_faction_resource(faction: StringName, resource_id: StringName) -> int:
	if not _faction_vaults.has(faction):
		return 0
	var vault: Dictionary = _faction_vaults[faction]
	return int(vault.get(resource_id, 0))

func add_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> void:
	if amount <= 0 or not _faction_vaults.has(faction):
		return
	var vault: Dictionary = _faction_vaults[faction]
	var current: int = int(vault.get(resource_id, 0))
	var new_amount := current + amount
	vault[resource_id] = new_amount
	faction_resources_changed.emit(faction, resource_id, new_amount)

func spend_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> bool:
	if amount < 0 or not _faction_vaults.has(faction):
		return false
	if amount == 0:
		return true
	var vault: Dictionary = _faction_vaults[faction]
	var current: int = int(vault.get(resource_id, 0))
	if current < amount:
		return false
	var new_amount := current - amount
	vault[resource_id] = new_amount
	faction_resources_changed.emit(faction, resource_id, new_amount)
	return true

func get_faction_vault_snapshot(faction: StringName) -> Dictionary:
	if not _faction_vaults.has(faction):
		return {}
	return (_faction_vaults[faction] as Dictionary).duplicate()

func get_planet_upgrades(planet_id: StringName) -> Array[StringName]:
	var list: Array = _planet_upgrades.get(planet_id, [])
	var result: Array[StringName] = []
	for item in list:
		result.append(item as StringName)
	return result

func has_planet_upgrade(planet_id: StringName, upgrade_id: StringName) -> bool:
	var upgrades: Array = _planet_upgrades.get(planet_id, [])
	return upgrades.has(upgrade_id)

func can_purchase_upgrade(planet_id: StringName, upgrade_id: StringName, catalog: PlanetUpgradeCatalog = null, available_workers: int = -1) -> bool:
	var cat: PlanetUpgradeCatalog = catalog if catalog != null else DEFAULT_UPGRADE_CATALOG
	if cat == null:
		return false
	var upgrade := cat.resolve(upgrade_id)
	if upgrade == null:
		return false
	var faction := faction_of(planet_id)
	if faction == FACTION_NEUTRAL or not _faction_vaults.has(faction):
		return false
	if not String(upgrade.required_technology_id).is_empty() and not has_technology(faction, upgrade.required_technology_id):
		return false
	var current_upgrades := get_planet_upgrades(planet_id)
	if not cat.can_unlock(current_upgrades, upgrade_id):
		return false
	if get_faction_resource(faction, upgrade.cost_resource) < upgrade.cost_amount:
		return false
	if available_workers >= 0 and available_workers < upgrade.cost_workers:
		return false
	return true

func purchase_upgrade(planet_id: StringName, upgrade_id: StringName, catalog: PlanetUpgradeCatalog = null, available_workers: int = -1) -> bool:
	if not can_purchase_upgrade(planet_id, upgrade_id, catalog, available_workers):
		return false
	var cat: PlanetUpgradeCatalog = catalog if catalog != null else DEFAULT_UPGRADE_CATALOG
	var upgrade := cat.resolve(upgrade_id)
	var faction := faction_of(planet_id)
	if not spend_faction_resource(faction, upgrade.cost_resource, upgrade.cost_amount):
		return false
	if not _planet_upgrades.has(planet_id):
		_planet_upgrades[planet_id] = []
	(_planet_upgrades[planet_id] as Array).append(upgrade_id)
	planet_upgraded.emit(planet_id, upgrade_id)
	return true

func generate_resources_for_planet(planet_id: StringName, catalog: PlanetUpgradeCatalog = null, base_amount: int = 1) -> int:
	var faction := faction_of(planet_id)
	if faction == FACTION_NEUTRAL or not _faction_vaults.has(faction):
		return 0
	var resource_id := resource_of(planet_id)
	if String(resource_id).is_empty():
		return 0
	var resolved_base := maxi(base_amount, 1)
	var upgrades := get_planet_upgrades(planet_id)
	var cat: PlanetUpgradeCatalog = catalog if catalog != null else DEFAULT_UPGRADE_CATALOG
	var multiplier := 1.0
	if cat != null:
		for up_id in upgrades:
			var def := cat.resolve(up_id)
			if def != null and def.trait_definition != null:
				multiplier += def.trait_definition.production_boost
				if not String(def.trait_definition.maintenance_cost_resource).is_empty() and def.trait_definition.maintenance_cost_amount > 0:
					spend_faction_resource(faction, def.trait_definition.maintenance_cost_resource, def.trait_definition.maintenance_cost_amount)
	for planet_technology_id in get_planet_technologies(planet_id):
		var planet_technology: TechnologyDefinition = DEFAULT_TECHNOLOGY_CATALOG.resolve(planet_technology_id)
		if planet_technology != null:
			multiplier *= planet_technology.production_multiplier
	var final_amount: int = maxi(1, int(float(resolved_base) * multiplier))
	add_faction_resource(faction, resource_id, final_amount)
	resource_generated.emit(planet_id, resource_id, final_amount)
	return final_amount

func convert_refinery_resources(planet_id: StringName, _upgrade_catalog: PlanetUpgradeCatalog = null) -> Dictionary:
	var faction: StringName = faction_of(planet_id)
	if faction == FACTION_NEUTRAL or not _faction_vaults.has(faction):
		return {"converted": false}
	if not has_planet_upgrade(planet_id, &"refinery"):
		return {"converted": false}
	var mat_amount: int = get_faction_resource(faction, GameState.RES_MATERIAL)
	var energy_amount: int = get_faction_resource(faction, GameState.RES_ENERGY)
	if mat_amount < 2 or energy_amount < 1:
		return {"converted": false}
	if not spend_faction_resource(faction, GameState.RES_MATERIAL, 2):
		return {"converted": false}
	if not spend_faction_resource(faction, GameState.RES_ENERGY, 1):
		add_faction_resource(faction, GameState.RES_MATERIAL, 2)
		return {"converted": false}
	var produced_resource: StringName = GameState.RES_RARE
	add_faction_resource(faction, produced_resource, 1)
	var consumed: Dictionary = {GameState.RES_MATERIAL: 2, GameState.RES_ENERGY: 1}
	var produced: Dictionary = {produced_resource: 1}
	refinery_converted.emit(planet_id, faction, consumed, produced)
	return {
		"converted": true,
		"consumed": consumed,
		"produced": produced,
	}

func signature_resource_for_planet_type(planet_type: StringName) -> StringName:
	match planet_type:
		&"ember", &"volcanic":
			return GameState.RES_ENERGY
		&"ocean", &"ice":
			return GameState.RES_BIOMASS
		&"violet", &"golden":
			return GameState.RES_RARE
		&"toxic", &"toxic_red":
			return GameState.RES_MATERIAL
		&"storm", &"paper", &"desert":
			return GameState.RES_VOLATILE
		_:
			return GameState.RES_ENERGY

func validate_resources(pool: ResourcePool = null) -> PackedStringArray:
	var errors := PackedStringArray()
	var resource_pool: ResourcePool = pool if pool != null else DEFAULT_RESOURCE_POOL
	if _planet_resources.is_empty():
		errors.append("resources have not been dealt")
		return errors
	if resource_pool == null or resource_pool.resources.is_empty():
		errors.append("resource pool is empty")
		return errors

	var counts: Dictionary = {}
	for planet_id in _planet_resources:
		var resource_id: StringName = resource_of(planet_id as StringName)
		if String(resource_id).is_empty():
			errors.append("planet %s has no resource" % planet_id)
			continue
		counts[resource_id] = int(counts.get(resource_id, 0)) + 1

	var homeworld_resources: Dictionary = {}
	for planet_id in _homeworlds.values():
		var resource_id: StringName = resource_of(planet_id as StringName)
		if String(resource_id).is_empty():
			continue
		if homeworld_resources.has(resource_id):
			errors.append("homeworlds share resource %s" % resource_id)
		homeworld_resources[resource_id] = true

	if counts.size() < resource_pool.resources.size():
		errors.append("not every pool resource is represented")
	var min_count := 1 << 30
	var max_count := 0
	for count in counts.values():
		min_count = mini(min_count, int(count))
		max_count = maxi(max_count, int(count))
	if counts.size() > 1 and max_count - min_count > 1:
		errors.append("resource distribution is unbalanced")
	return errors

func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = value

func is_homeworld(planet_id: StringName) -> bool:
	return _homeworlds.values().has(planet_id)

func homeworld_for(faction: StringName) -> StringName:
	var value: Variant = _homeworlds.get(faction, &"")
	return value as StringName

func _remember_planet(faction: StringName, planet_id: StringName) -> void:
	if String(faction).is_empty() or String(planet_id).is_empty() or faction == FACTION_NEUTRAL:
		return
	if not _known_planets.has(faction):
		_known_planets[faction] = {}
	(_known_planets[faction] as Dictionary)[planet_id] = true

func discover_planet(faction: StringName, planet_id: StringName) -> bool:
	if String(faction).is_empty() or String(planet_id).is_empty() or faction == FACTION_NEUTRAL:
		return false
	if is_known(planet_id, faction):
		return false
	_remember_planet(faction, planet_id)
	planet_discovered.emit(faction, planet_id)
	return true

func scan_planet(faction: StringName, planet_id: StringName, resource_id: StringName = &"", size_id: StringName = &"", build_slots: int = 0) -> bool:
	if String(faction).is_empty() or String(planet_id).is_empty() or faction == FACTION_NEUTRAL:
		return false
	if is_known(planet_id, faction):
		return false
	if not discover_planet(faction, planet_id):
		return false
	if not _scanned_planets.has(faction):
		_scanned_planets[faction] = {}
	if not _scan_intel.has(faction):
		_scan_intel[faction] = {}
	(_scanned_planets[faction] as Dictionary)[planet_id] = true
	(_scan_intel[faction] as Dictionary)[planet_id] = {
		"resource_id": resource_id,
		"size_id": size_id,
		"build_slots": maxi(build_slots, 0),
	}
	planet_scanned.emit(faction, planet_id, resource_id, size_id, maxi(build_slots, 0))
	return true

func has_scanned_planet(faction: StringName, planet_id: StringName = &"") -> bool:
	var scanned: Dictionary = _scanned_planets.get(faction, {})
	if not String(planet_id).is_empty():
		return scanned.has(planet_id)
	return not scanned.is_empty()

func scan_info_for(faction: StringName, planet_id: StringName) -> Dictionary:
	var faction_intel: Dictionary = _scan_intel.get(faction, {})
	var value: Variant = faction_intel.get(planet_id, {})
	return value.duplicate() if value is Dictionary else {}

func is_known(planet_id: StringName, faction: StringName) -> bool:
	if faction != FACTION_NEUTRAL and faction_of(planet_id) == faction:
		return true
	var known: Dictionary = _known_planets.get(faction, {})
	return known.has(planet_id)

func known_planets_of(faction: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for planet_id in _ownership:
		var planet_owner: StringName = _ownership[planet_id] as StringName
		if planet_owner == faction and faction != FACTION_NEUTRAL:
			result.append(planet_id as StringName)
	var known: Dictionary = _known_planets.get(faction, {})
	for planet_id in known:
		if not result.has(planet_id):
			result.append(planet_id as StringName)
	return result

func has_technology(faction: StringName, technology_id: StringName) -> bool:
	var researched: Dictionary = _researched_techs.get(faction, {})
	return researched.has(technology_id)

func has_worker_factory(planet_id: StringName) -> bool:
	return _worker_factories.has(planet_id)

func can_build_worker_factory(planet_id: StringName, cost_resource: StringName, cost_amount: int) -> bool:
	var faction: StringName = faction_of(planet_id)
	if faction == FACTION_NEUTRAL or not _faction_vaults.has(faction):
		return false
	if not has_planet_upgrade(planet_id, &"shipyard") or has_worker_factory(planet_id):
		return false
	if not has_scanned_planet(faction):
		return false
	if not has_technology(faction, TECH_WORKER_AUTOMATION):
		return false
	return get_faction_resource(faction, cost_resource) >= cost_amount

func build_worker_factory(planet_id: StringName, cost_resource: StringName, cost_amount: int) -> bool:
	if not can_build_worker_factory(planet_id, cost_resource, cost_amount):
		return false
	var faction: StringName = faction_of(planet_id)
	if not spend_faction_resource(faction, cost_resource, cost_amount):
		return false
	_worker_factories[planet_id] = true
	worker_factory_built.emit(planet_id)
	return true

func register_gathering_workers(faction: StringName, planet_id: StringName, worker_amount: int, source_planet_id: StringName = &"") -> int:
	if faction == FACTION_NEUTRAL or faction.is_empty() or faction_of(planet_id) != FACTION_NEUTRAL:
		return 0
	if not has_scanned_planet(faction, planet_id):
		return 0
	var faction_gathers: Dictionary = _gathering_workers.get(faction, {})
	var total: int = int(faction_gathers.get(planet_id, 0)) + maxi(worker_amount, 0)
	faction_gathers[planet_id] = total
	_gathering_workers[faction] = faction_gathers
	if not String(source_planet_id).is_empty():
		var faction_sources: Dictionary = _gathering_sources.get(faction, {})
		faction_sources[planet_id] = source_planet_id
		_gathering_sources[faction] = faction_sources
	gathering_started.emit(faction, planet_id, maxi(worker_amount, 0))
	return total

func get_gathering_workers(faction: StringName, planet_id: StringName) -> int:
	return int(_gathering_workers.get(faction, {}).get(planet_id, 0))

func get_gathering_source(faction: StringName, planet_id: StringName) -> StringName:
	var source: Variant = _gathering_sources.get(faction, {}).get(planet_id, &"")
	return source as StringName if source != null else &""

func withdraw_gathering_workers(faction: StringName, planet_id: StringName, amount: int) -> int:
	var faction_gathers: Dictionary = _gathering_workers.get(faction, {})
	if not faction_gathers.has(planet_id):
		return 0
	var current: int = int(faction_gathers.get(planet_id, 0))
	var withdrawn: int = mini(current, maxi(amount, 0))
	if withdrawn <= 0:
		return 0
	var remaining: int = current - withdrawn
	if remaining <= 0:
		faction_gathers.erase(planet_id)
		var faction_sources: Dictionary = _gathering_sources.get(faction, {})
		faction_sources.erase(planet_id)
		if faction_sources.is_empty():
			_gathering_sources.erase(faction)
		else:
			_gathering_sources[faction] = faction_sources
	else:
		faction_gathers[planet_id] = remaining
	if faction_gathers.is_empty():
		_gathering_workers.erase(faction)
	else:
		_gathering_workers[faction] = faction_gathers
	gathering_withdrawn.emit(faction, planet_id, withdrawn)
	return withdrawn

func gather_income_tick(base_amounts: Dictionary) -> int:
	var total := 0
	for faction_value in _gathering_workers:
		var faction: StringName = faction_value as StringName
		var per_planet: Dictionary = _gathering_workers[faction]
		for planet_id_value in per_planet:
			var planet_id: StringName = planet_id_value as StringName
			var count: int = int(per_planet[planet_id])
			if count <= 0:
				continue
			var resource_id: StringName = resource_of(planet_id)
			if String(resource_id).is_empty():
				continue
			var amount: int = count * maxi(int(base_amounts.get(planet_id, 1)), 1)
			add_faction_resource(faction, resource_id, amount)
			resources_collected.emit(faction, planet_id, resource_id, amount)
			total += amount
	return total

func get_ship_part_inventory(planet_id: StringName) -> Dictionary:
	return (_ship_part_inventory.get(planet_id, {}) as Dictionary).duplicate()

func get_ship_part_count(planet_id: StringName, part_id: StringName) -> int:
	return int(_ship_part_inventory.get(planet_id, {}).get(part_id, 0))

func can_buy_ship_part(planet_id: StringName, part_id: StringName, catalog: ShipPartCatalog = null) -> bool:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	if cat == null:
		return false
	var part := cat.resolve(part_id)
	if part == null:
		return false
	var faction: StringName = faction_of(planet_id)
	if faction == FACTION_NEUTRAL:
		return false
	if not String(part.required_tech_id).is_empty() and not has_technology(faction, part.required_tech_id):
		return false
	return get_faction_resource(faction, part.cost_resource) >= part.cost_amount

func buy_ship_part(planet_id: StringName, part_id: StringName, catalog: ShipPartCatalog = null) -> bool:
	if not can_buy_ship_part(planet_id, part_id, catalog):
		return false
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	var part := cat.resolve(part_id)
	var faction: StringName = faction_of(planet_id)
	if not spend_faction_resource(faction, part.cost_resource, part.cost_amount):
		return false
	_add_ship_part(planet_id, part_id, 1)
	ship_part_purchased.emit(planet_id, part_id)
	return true

func can_assemble_ship(planet_id: StringName, hull_id: StringName, scanner_id: StringName, module_ids: Array, catalog: ShipPartCatalog = null, weapon_id: StringName = &"", drive_id: StringName = &"", shield_id: StringName = &"") -> bool:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	if cat == null:
		return false
	var faction: StringName = faction_of(planet_id)
	if faction == FACTION_NEUTRAL:
		return false
	var hull := cat.resolve(hull_id)
	var scanner := cat.resolve(scanner_id)
	if hull == null or hull.slot_type != ShipPartDefinition.SLOT_HULL:
		return false
	if scanner == null or scanner.slot_type != ShipPartDefinition.SLOT_SCANNER:
		return false
	if module_ids.size() > cat.max_module_slots:
		return false
	if not _part_tech_unlocked(faction, hull):
		return false
	if not _part_tech_unlocked(faction, scanner):
		return false
	var required: Dictionary = {hull_id: 1, scanner_id: 1}
	for slot_value in [[drive_id, ShipPartDefinition.SLOT_DRIVE], [shield_id, ShipPartDefinition.SLOT_SHIELD]]:
		var slot_id: StringName = slot_value[0] as StringName
		var expected_slot: StringName = slot_value[1] as StringName
		if String(slot_id).is_empty():
			continue
		var slot_part: ShipPartDefinition = cat.resolve(slot_id)
		if slot_part == null or slot_part.slot_type != expected_slot:
			return false
		if slot_id == hull_id or slot_id == scanner_id:
			return false
		if not _part_tech_unlocked(faction, slot_part):
			return false
		required[slot_id] = int(required.get(slot_id, 0)) + 1
	if not String(weapon_id).is_empty():
		var weapon := cat.resolve(weapon_id)
		if weapon == null or weapon.slot_type != ShipPartDefinition.SLOT_WEAPON:
			return false
		if weapon_id == hull_id or weapon_id == scanner_id:
			return false
		if not _part_tech_unlocked(faction, weapon):
			return false
		required[weapon_id] = 1
	for module_value in module_ids:
		var module_id: StringName = module_value as StringName
		var module := cat.resolve(module_id)
		if module == null or not ShipPartDefinition.is_utility_slot(module.slot_type):
			return false
		if module_id == hull_id or module_id == scanner_id or module_id == weapon_id:
			return false
		if not _part_tech_unlocked(faction, module):
			return false
		required[module_id] = int(required.get(module_id, 0)) + 1
	for part_id in required:
		if get_ship_part_count(planet_id, part_id as StringName) < int(required[part_id]):
			return false
	return true

func _part_tech_unlocked(faction: StringName, part: ShipPartDefinition) -> bool:
	if part == null or String(part.required_tech_id).is_empty():
		return true
	return has_technology(faction, part.required_tech_id)

func assemble_ship(planet_id: StringName, hull_id: StringName, scanner_id: StringName, module_ids: Array, catalog: ShipPartCatalog = null, weapon_id: StringName = &"", drive_id: StringName = &"", shield_id: StringName = &"", blueprint_id: StringName = &"", instance_seed: int = -1) -> StringName:
	if not can_assemble_ship(planet_id, hull_id, scanner_id, module_ids, catalog, weapon_id, drive_id, shield_id):
		return &""
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	var blueprint: ShipBlueprint = cat.resolve_blueprint(blueprint_id)
	if not String(blueprint_id).is_empty() and blueprint == null:
		return &""
	_remove_ship_part(planet_id, hull_id, 1)
	_remove_ship_part(planet_id, scanner_id, 1)
	if not String(drive_id).is_empty():
		_remove_ship_part(planet_id, drive_id, 1)
	if not String(shield_id).is_empty():
		_remove_ship_part(planet_id, shield_id, 1)
	for module_value in module_ids:
		_remove_ship_part(planet_id, module_value as StringName, 1)
	if not String(weapon_id).is_empty():
		_remove_ship_part(planet_id, weapon_id, 1)
	var ship_id: StringName = _next_ship_id()
	var resolved_instance_seed: int = _next_ship_index if instance_seed < 0 else instance_seed
	var variant_ids: Dictionary = _select_variant_ids(cat, blueprint, resolved_instance_seed, hull_id, drive_id, weapon_id, shield_id, scanner_id, module_ids)
	var total_time := _ship_build_time(cat, hull_id, scanner_id, weapon_id, module_ids, drive_id, shield_id)
	if total_time > 0.0:
		var jobs: Dictionary = _ship_build_jobs.get(planet_id, {})
		jobs[ship_id] = {
			"hull": hull_id,
			"drive": drive_id,
			"blueprint": blueprint.id if blueprint != null else &"",
			"instance_seed": resolved_instance_seed,
			"variants": variant_ids,
			"weapon": weapon_id,
			"shield": shield_id,
			"scanner": scanner_id,
			"modules": module_ids.duplicate(),
			"remaining": total_time
		}
		_ship_build_jobs[planet_id] = jobs
		ship_build_started.emit(planet_id, ship_id, total_time)
		return ship_id
	var assembly: Dictionary = {
		"hull": hull_id,
		"drive": drive_id,
		"blueprint": blueprint.id if blueprint != null else &"",
		"instance_seed": resolved_instance_seed,
		"variants": variant_ids,
		"weapon": weapon_id,
		"shield": shield_id,
		"scanner": scanner_id,
		"modules": module_ids.duplicate(),
	}
	var assemblies: Dictionary = _ship_assemblies.get(planet_id, {})
	assemblies[ship_id] = assembly
	_ship_assemblies[planet_id] = assemblies
	ship_assembled.emit(planet_id, ship_id)
	return ship_id

func _select_variant_ids(cat: ShipPartCatalog, blueprint: ShipBlueprint, instance_seed: int, hull_id: StringName, drive_id: StringName, weapon_id: StringName, shield_id: StringName, scanner_id: StringName, module_ids: Array) -> Dictionary:
	var result: Dictionary = {}
	if cat == null or blueprint == null:
		return result
	var slot_ids: Dictionary = {
		&"hull": hull_id,
		&"drive": drive_id,
		&"weapon": weapon_id,
		&"shield": shield_id,
		&"scanner": scanner_id,
	}
	for slot_name in slot_ids:
		var part_id: StringName = slot_ids[slot_name] as StringName
		if String(part_id).is_empty():
			continue
		var part: ShipPartDefinition = cat.resolve(part_id)
		var variant: ShipComponentVariant = cat.select_variant(part, blueprint, instance_seed, -1, slot_name as StringName)
		result[slot_name] = variant.id if variant != null else &""
	var utility_variants: Array[StringName] = []
	for index in range(module_ids.size()):
		var utility_part: ShipPartDefinition = cat.resolve(module_ids[index] as StringName)
		var utility_variant: ShipComponentVariant = cat.select_variant(utility_part, blueprint, instance_seed, -1, StringName("utility_%d" % index))
		utility_variants.append(utility_variant.id if utility_variant != null else &"")
	result[&"utility"] = utility_variants
	return result

func _ship_build_time(cat: ShipPartCatalog, hull_id: StringName, scanner_id: StringName, weapon_id: StringName, module_ids: Array, drive_id: StringName = &"", shield_id: StringName = &"") -> float:
	var total := 0.0
	for part_value in [hull_id, drive_id, weapon_id, shield_id, scanner_id]:
		var part := cat.resolve(part_value as StringName)
		if part != null:
			total += part.build_time
	for module_value in module_ids:
		var module := cat.resolve(module_value as StringName)
		if module != null:
			total += module.build_time
	return total

func ship_build_in_progress(planet_id: StringName, ship_id: StringName = &"") -> bool:
	var jobs: Dictionary = _ship_build_jobs.get(planet_id, {})
	if String(ship_id).is_empty():
		return not jobs.is_empty()
	return jobs.has(ship_id)

func ship_build_remaining(planet_id: StringName, ship_id: StringName) -> float:
	return float(_ship_build_jobs.get(planet_id, {}).get(ship_id, {}).get("remaining", 0.0))

func get_ship_build_jobs(planet_id: StringName) -> Dictionary:
	return (_ship_build_jobs.get(planet_id, {}) as Dictionary).duplicate()

func advance_builds(seconds: float) -> void:
	if seconds <= 0.0 or _ship_build_jobs.is_empty():
		return
	for planet_value in _ship_build_jobs.keys():
		var planet_id: StringName = planet_value as StringName
		var jobs: Dictionary = _ship_build_jobs[planet_id]
		var completed: Array[StringName] = []
		for ship_value in jobs.keys():
			var ship_id: StringName = ship_value as StringName
			var job: Dictionary = jobs[ship_id]
			job["remaining"] = float(job["remaining"]) - seconds
			if float(job["remaining"]) <= 0.0:
				completed.append(ship_id)
		for ship_id in completed:
			var job: Dictionary = jobs[ship_id]
			jobs.erase(ship_id)
			var assembly: Dictionary = {
				"hull": job.get("hull", &""),
				"drive": job.get("drive", &""),
				"blueprint": job.get("blueprint", &""),
				"instance_seed": int(job.get("instance_seed", 0)),
				"variants": (job.get("variants", {}) as Dictionary).duplicate(true),
				"weapon": job.get("weapon", &""),
				"shield": job.get("shield", &""),
				"scanner": job.get("scanner", &""),
				"modules": (job.get("modules", []) as Array).duplicate(),
			}
			var assemblies: Dictionary = _ship_assemblies.get(planet_id, {})
			assemblies[ship_id] = assembly
			_ship_assemblies[planet_id] = assemblies
			ship_assembled.emit(planet_id, ship_id)
		if jobs.is_empty():
			_ship_build_jobs.erase(planet_id)
		else:
			_ship_build_jobs[planet_id] = jobs

func get_ship_assemblies(planet_id: StringName) -> Dictionary:
	return (_ship_assemblies.get(planet_id, {}) as Dictionary).duplicate()

func has_ship_assembly(planet_id: StringName, ship_id: StringName) -> bool:
	return _ship_assemblies.get(planet_id, {}).has(ship_id)

func get_ship_assembly(planet_id: StringName, ship_id: StringName) -> Dictionary:
	var assembly: Variant = _ship_assemblies.get(planet_id, {}).get(ship_id, {})
	return assembly as Dictionary if assembly != null else {}

func disassemble_ship(planet_id: StringName, ship_id: StringName) -> bool:
	var assemblies: Dictionary = _ship_assemblies.get(planet_id, {})
	if not assemblies.has(ship_id):
		return false
	var assembly: Dictionary = assemblies[ship_id]
	_add_ship_part(planet_id, assembly.get("hull", &"") as StringName, 1)
	var drive_id: StringName = assembly.get("drive", &"") as StringName
	if not String(drive_id).is_empty():
		_add_ship_part(planet_id, drive_id, 1)
	_add_ship_part(planet_id, assembly.get("scanner", &"") as StringName, 1)
	if not String(assembly.get("weapon", &"")).is_empty():
		_add_ship_part(planet_id, assembly.get("weapon", &"") as StringName, 1)
	var shield_id: StringName = assembly.get("shield", &"") as StringName
	if not String(shield_id).is_empty():
		_add_ship_part(planet_id, shield_id, 1)
	for module_value in assembly.get("modules", []):
		_add_ship_part(planet_id, module_value as StringName, 1)
	assemblies.erase(ship_id)
	if assemblies.is_empty():
		_ship_assemblies.erase(planet_id)
	else:
		_ship_assemblies[planet_id] = assemblies
	ship_disassembled.emit(planet_id, ship_id)
	return true

func _add_ship_part(planet_id: StringName, part_id: StringName, amount: int) -> void:
	var inventory: Dictionary = _ship_part_inventory.get(planet_id, {})
	inventory[part_id] = int(inventory.get(part_id, 0)) + maxi(amount, 0)
	_ship_part_inventory[planet_id] = inventory

func _remove_ship_part(planet_id: StringName, part_id: StringName, amount: int) -> int:
	var inventory: Dictionary = _ship_part_inventory.get(planet_id, {})
	var current: int = int(inventory.get(part_id, 0))
	var removed: int = mini(current, maxi(amount, 0))
	if removed <= 0:
		return 0
	var remaining: int = current - removed
	if remaining <= 0:
		inventory.erase(part_id)
	else:
		inventory[part_id] = remaining
	if inventory.is_empty():
		_ship_part_inventory.erase(planet_id)
	else:
		_ship_part_inventory[planet_id] = inventory
	return removed

func _next_ship_id() -> StringName:
	_next_ship_index += 1
	return StringName("ship_%d" % _next_ship_index)

func get_technologies(faction: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for technology_id in _researched_techs.get(faction, {}):
		result.append(technology_id as StringName)
	return result

func can_research_technology(faction: StringName, technology_id: StringName, catalog: TechnologyCatalog = null) -> bool:
	var cat: TechnologyCatalog = catalog if catalog != null else DEFAULT_TECHNOLOGY_CATALOG
	if cat == null:
		return false
	var technology := cat.resolve(technology_id)
	if technology == null:
		return false
	if faction == FACTION_NEUTRAL or not _faction_vaults.has(faction):
		return false
	if has_technology(faction, technology_id):
		return false
	if research_in_progress(faction, technology_id):
		return false
	if technology.requires_discovery and not has_scanned_planet(faction):
		return false
	if not cat.can_research(get_technologies(faction), technology_id):
		return false
	if get_faction_resource(faction, technology.cost_resource) < technology.cost_amount:
		return false
	return true

func research_technology(faction: StringName, technology_id: StringName, catalog: TechnologyCatalog = null) -> bool:
	if not can_research_technology(faction, technology_id, catalog):
		return false
	var cat: TechnologyCatalog = catalog if catalog != null else DEFAULT_TECHNOLOGY_CATALOG
	var technology := cat.resolve(technology_id)
	if not spend_faction_resource(faction, technology.cost_resource, technology.cost_amount):
		return false
	if technology.research_time > 0.0:
		var jobs: Dictionary = _research_jobs.get(faction, {})
		jobs[technology_id] = technology.research_time
		_research_jobs[faction] = jobs
		research_started.emit(faction, technology_id, technology.research_time)
		return true
	if not _researched_techs.has(faction):
		_researched_techs[faction] = {}
	(_researched_techs[faction] as Dictionary)[technology_id] = true
	technology_researched.emit(faction, technology_id)
	return true

func set_jobs_auto_advance(enabled: bool) -> void:
	_jobs_auto_advance = enabled

func _process(delta: float) -> void:
	if _jobs_auto_advance:
		advance_research(delta)
		advance_builds(delta)

func research_in_progress(faction: StringName, technology_id: StringName) -> bool:
	return (_research_jobs.get(faction, {}) as Dictionary).has(technology_id)

func research_remaining(faction: StringName, technology_id: StringName) -> float:
	return float(_research_jobs.get(faction, {}).get(technology_id, 0.0))

func get_research_jobs(faction: StringName) -> Dictionary:
	return (_research_jobs.get(faction, {}) as Dictionary).duplicate()

func advance_research(seconds: float) -> void:
	if seconds <= 0.0 or _research_jobs.is_empty():
		return
	for faction_value in _research_jobs.keys():
		var faction: StringName = faction_value as StringName
		var jobs: Dictionary = _research_jobs[faction]
		var completed: Array[StringName] = []
		for technology_value in jobs.keys():
			var technology_id: StringName = technology_value as StringName
			jobs[technology_id] = float(jobs[technology_id]) - seconds
			if float(jobs[technology_id]) <= 0.0:
				completed.append(technology_id)
		for technology_id in completed:
			jobs.erase(technology_id)
			if not _researched_techs.has(faction):
				_researched_techs[faction] = {}
			(_researched_techs[faction] as Dictionary)[technology_id] = true
			technology_researched.emit(faction, technology_id)
		if jobs.is_empty():
			_research_jobs.erase(faction)
		else:
			_research_jobs[faction] = jobs

func get_planet_technologies(planet_id: StringName) -> Array[StringName]:
	var researched: Array = _planet_technologies.get(planet_id, [])
	var result: Array[StringName] = []
	for technology_id in researched:
		result.append(technology_id as StringName)
	return result

func has_planet_technology(planet_id: StringName, technology_id: StringName) -> bool:
	return get_planet_technologies(planet_id).has(technology_id)

func can_research_planet_technology(faction: StringName, planet_id: StringName, technology_id: StringName, catalog: TechnologyCatalog = null) -> bool:
	var cat: TechnologyCatalog = catalog if catalog != null else DEFAULT_TECHNOLOGY_CATALOG
	if cat == null or faction == FACTION_NEUTRAL or faction_of(planet_id) != faction:
		return false
	if not is_known(planet_id, faction):
		return false
	var technology: TechnologyDefinition = cat.resolve(technology_id)
	if technology == null or technology.category != TechnologyDefinition.CATEGORY_PLANET:
		return false
	if has_planet_technology(planet_id, technology_id):
		return false
	if not cat.can_research(get_planet_technologies(planet_id), technology_id):
		return false
	return get_faction_resource(faction, technology.cost_resource) >= technology.cost_amount

func research_planet_technology(faction: StringName, planet_id: StringName, technology_id: StringName, catalog: TechnologyCatalog = null) -> bool:
	if not can_research_planet_technology(faction, planet_id, technology_id, catalog):
		return false
	var cat: TechnologyCatalog = catalog if catalog != null else DEFAULT_TECHNOLOGY_CATALOG
	var technology: TechnologyDefinition = cat.resolve(technology_id)
	if not spend_faction_resource(faction, technology.cost_resource, technology.cost_amount):
		return false
	if not _planet_technologies.has(planet_id):
		_planet_technologies[planet_id] = []
	(_planet_technologies[planet_id] as Array).append(technology_id)
	planet_technology_researched.emit(planet_id, technology_id)
	return true

func validate_starting_setup() -> PackedStringArray:
	var errors := PackedStringArray()
	if get_ownership_count(FACTION_PLAYER) != 1:
		errors.append("starting setup must contain exactly one player planet")
	if get_ownership_count(FACTION_CPU) != 1:
		errors.append("starting setup must contain exactly one CPU planet")
	if homeworld_for(FACTION_PLAYER).is_empty():
		errors.append("starting setup is missing the player homeworld")
	if homeworld_for(FACTION_CPU).is_empty():
		errors.append("starting setup is missing the CPU homeworld")
	return errors

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for planet_id in _ownership:
		var faction: StringName = faction_of(planet_id as StringName)
		if faction != FACTION_PLAYER and faction != FACTION_CPU and faction != FACTION_NEUTRAL:
			errors.append("planet %s has an invalid faction %s" % [planet_id, faction])
	return errors

func create_fleet_from_planet(planet_id: StringName, ship_ids: Array, catalog: ShipPartCatalog = null) -> FleetSnapshot:
	var faction: StringName = faction_of(planet_id)
	var assemblies: Dictionary = _ship_assemblies.get(planet_id, {})
	var fleet := FleetSnapshot.new()
	fleet.fleet_id = StringName("fleet_%s_%d" % [String(planet_id), Time.get_ticks_msec()])
	fleet.faction = faction
	fleet.source_planet_id = planet_id

	var valid_ships: Array[Dictionary] = []
	for ship_id_val in ship_ids:
		var ship_id: StringName = ship_id_val as StringName
		if assemblies.has(ship_id):
			var ship_data: Dictionary = (assemblies[ship_id] as Dictionary).duplicate()
			ship_data["id"] = ship_id
			valid_ships.append(ship_data)
			assemblies.erase(ship_id)

	if assemblies.is_empty():
		_ship_assemblies.erase(planet_id)
	else:
		_ship_assemblies[planet_id] = assemblies

	fleet.ships = valid_ships
	fleet.calculate_stats(catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG)
	return fleet

func disband_fleet_to_planet(fleet: FleetSnapshot, planet_id: StringName) -> void:
	if fleet == null:
		return
	var assemblies: Dictionary = _ship_assemblies.get(planet_id, {})
	for ship_data in fleet.ships:
		var ship_id: StringName = ship_data.get("id", _next_ship_id()) as StringName
		var clean_data: Dictionary = ship_data.duplicate()
		clean_data.erase("id")
		assemblies[ship_id] = clean_data
	_ship_assemblies[planet_id] = assemblies
