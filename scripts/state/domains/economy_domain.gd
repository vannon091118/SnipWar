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

var faction_vaults: Dictionary = {}
var planet_resources: Dictionary = {}
var planet_upgrades: Dictionary = {}
var worker_factories: Dictionary = {}
var gathering_workers: Dictionary = {}
var gathering_sources: Dictionary = {}

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
	if catalog == null or effective_pool == null:
		return
	var catalog_size := catalog.planets.size()
	if catalog_size == 0:
		return
	var dealt: Array[GameResource] = effective_pool.deal_for_catalog(catalog_size, seed_value)
	for i in range(mini(catalog_size, dealt.size())):
		var def: PlanetDefinition = catalog.planets[i]
		if def != null and dealt[i] != null:
			set_planet_resource(def.planet_id, dealt[i].id)

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

func can_purchase_upgrade(faction: StringName, planet_id: StringName, upgrade_id: StringName, available_workers: int, catalog: PlanetUpgradeCatalog = null) -> bool:
	var effective_catalog: PlanetUpgradeCatalog = catalog if catalog != null else GameState.DEFAULT_UPGRADE_CATALOG
	if effective_catalog == null:
		return false
	var upgrade: PlanetUpgradeDefinition = effective_catalog.resolve(upgrade_id)
	if upgrade == null:
		return false
	if has_planet_upgrade(planet_id, upgrade_id):
		return false
	if not String(upgrade.parent_upgrade_id).is_empty() and not has_planet_upgrade(planet_id, upgrade.parent_upgrade_id):
		return false
	if not String(upgrade.exclusive_with).is_empty() and has_planet_upgrade(planet_id, upgrade.exclusive_with):
		return false
	if available_workers < upgrade.cost_workers:
		return false
	if not can_spend_faction_resource(faction, upgrade.cost_resource, upgrade.cost_amount):
		return false
	return true

func purchase_upgrade(faction: StringName, planet_id: StringName, upgrade_id: StringName, available_workers: int, catalog: PlanetUpgradeCatalog = null) -> bool:
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

func can_build_worker_factory(faction: StringName, planet_id: StringName, has_shipyard: bool, first_scan_done: bool, has_automation_tech: bool, available_slots: int) -> bool:
	if has_worker_factory(planet_id):
		return false
	if not has_shipyard or not first_scan_done or not has_automation_tech:
		return false
	if available_slots <= 0:
		return false
	return can_spend_faction_resource(faction, GameState.RES_BIOMASS, 10) and can_spend_faction_resource(faction, GameState.RES_MATERIAL, 10)

func build_worker_factory(faction: StringName, planet_id: StringName, has_shipyard: bool, first_scan_done: bool, has_automation_tech: bool, available_slots: int) -> bool:
	if not can_build_worker_factory(faction, planet_id, has_shipyard, first_scan_done, has_automation_tech, available_slots):
		return false
	if not spend_faction_resource(faction, GameState.RES_BIOMASS, 10):
		return false
	if not spend_faction_resource(faction, GameState.RES_MATERIAL, 10):
		add_faction_resource(faction, GameState.RES_BIOMASS, 10)
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

func withdraw_gathering_workers(faction: StringName, planet_id: StringName) -> Dictionary:
	if not gathering_workers.has(faction) or not gathering_workers[faction].has(planet_id):
		return {"count": 0, "source_planet_id": &""}
	var count: int = gathering_workers[faction].get(planet_id, 0)
	var source_planet_id: StringName = gathering_sources.get(faction, {}).get(planet_id, &"") as StringName
	gathering_workers[faction].erase(planet_id)
	if gathering_sources.has(faction):
		gathering_sources[faction].erase(planet_id)
	if count > 0:
		gathering_withdrawn.emit(faction, planet_id, count)
	return {"count": count, "source_planet_id": source_planet_id}

func gathering_workers_on(faction: StringName, planet_id: StringName) -> int:
	if not gathering_workers.has(faction):
		return 0
	return int(gathering_workers[faction].get(planet_id, 0))

func gather_income_tick(base_amounts: Dictionary) -> int:
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
			var base_amt: int = base_amounts.get(planet_id, 1)
			var earned := count * base_amt
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
