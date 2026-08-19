extends Node

const FACTION_PLAYER := &"a"
const FACTION_CPU := &"b"
const FACTION_NEUTRAL := &"neutral"

const MISSION_MILITARY := &"military"
const MISSION_CARGO := &"cargo"
const MISSION_COLONY := &"colony"
const MISSION_COLLECT := &"collect"
const TECH_WORKER_AUTOMATION := &"worker_automation"

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
var _faction_vaults: Dictionary = {
	FACTION_PLAYER: {
		&"energy": 50,
		&"biomass": 50,
		&"rare": 30,
		&"material": 30,
		&"volatile": 30
	},
	FACTION_CPU: {
		&"energy": 50,
		&"biomass": 50,
		&"rare": 30,
		&"material": 30,
		&"volatile": 30
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
			&"energy": 50,
			&"biomass": 50,
			&"rare": 30,
			&"material": 30,
			&"volatile": 30
		},
		FACTION_CPU: {
			&"energy": 50,
			&"biomass": 50,
			&"rare": 30,
			&"material": 30,
			&"volatile": 30
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
		if resource != null:
			resource_ids.append(resource.id)
	if resource_ids.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = deal_seed
	_shuffle(resource_ids, rng)

	var homeworld_ids: Array[StringName] = []
	var planet_ids: Array[StringName] = []
	for definition in catalog.planets:
		if definition == null:
			continue
		planet_ids.append(definition.planet_id)
		if definition.planet_role == &"homeworld":
			homeworld_ids.append(definition.planet_id)
	_shuffle(homeworld_ids, rng)

	var assigned: Dictionary = {}
	var cursor := 0
	for planet_id in homeworld_ids:
		assigned[planet_id] = resource_ids[cursor % resource_ids.size()]
		cursor += 1
	var remaining: Array[StringName] = []
	for planet_id in planet_ids:
		if not assigned.has(planet_id):
			remaining.append(planet_id)
	_shuffle(remaining, rng)
	for planet_id in remaining:
		assigned[planet_id] = resource_ids[cursor % resource_ids.size()]
		cursor += 1
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

func signature_resource_for_planet_type(planet_type: StringName) -> StringName:
	match planet_type:
		&"ember", &"volcanic":
			return &"energy"
		&"ocean", &"ice":
			return &"biomass"
		&"violet", &"golden":
			return &"rare"
		&"toxic", &"toxic_red":
			return &"material"
		&"storm", &"paper", &"desert":
			return &"volatile"
		_:
			return &"energy"

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

func can_assemble_ship(planet_id: StringName, hull_id: StringName, scanner_id: StringName, module_ids: Array, catalog: ShipPartCatalog = null) -> bool:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	if cat == null:
		return false
	var hull := cat.resolve(hull_id)
	var scanner := cat.resolve(scanner_id)
	if hull == null or hull.slot_type != ShipPartDefinition.SLOT_HULL:
		return false
	if scanner == null or scanner.slot_type != ShipPartDefinition.SLOT_SCANNER:
		return false
	if module_ids.size() > cat.max_module_slots:
		return false
	var required: Dictionary = {hull_id: 1, scanner_id: 1}
	for module_value in module_ids:
		var module_id: StringName = module_value as StringName
		var module := cat.resolve(module_id)
		if module == null or module.slot_type != ShipPartDefinition.SLOT_MODULE:
			return false
		if module_id == hull_id or module_id == scanner_id:
			return false
		required[module_id] = int(required.get(module_id, 0)) + 1
	for part_id in required:
		if get_ship_part_count(planet_id, part_id as StringName) < int(required[part_id]):
			return false
	return true

func assemble_ship(planet_id: StringName, hull_id: StringName, scanner_id: StringName, module_ids: Array, catalog: ShipPartCatalog = null) -> StringName:
	if not can_assemble_ship(planet_id, hull_id, scanner_id, module_ids, catalog):
		return &""
	_remove_ship_part(planet_id, hull_id, 1)
	_remove_ship_part(planet_id, scanner_id, 1)
	for module_value in module_ids:
		_remove_ship_part(planet_id, module_value as StringName, 1)
	var ship_id := _next_ship_id()
	var assembly: Dictionary = {
		"hull": hull_id,
		"scanner": scanner_id,
		"modules": module_ids.duplicate(),
	}
	var assemblies: Dictionary = _ship_assemblies.get(planet_id, {})
	assemblies[ship_id] = assembly
	_ship_assemblies[planet_id] = assemblies
	ship_assembled.emit(planet_id, ship_id)
	return ship_id

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
	_add_ship_part(planet_id, assembly.get("scanner", &"") as StringName, 1)
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
	if not _researched_techs.has(faction):
		_researched_techs[faction] = {}
	(_researched_techs[faction] as Dictionary)[technology_id] = true
	technology_researched.emit(faction, technology_id)
	return true

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
