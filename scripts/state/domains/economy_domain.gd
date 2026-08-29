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
signal worker_transport_started(transport_id: StringName, faction: StringName, amount: int)
signal worker_transport_phase_changed(transport_id: StringName, phase: StringName)


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

## R-007 (E1): Verhaltens-Einheit für Vaults/Credits/Local-Vaults/Reservierungen.
## Der State bleibt auf dieser Fassade; die Einheit mutiert ihn über _owner,
## damit Dictionary-Referenzsemantik und Signal-Identität erhalten bleiben.
var _vault_core: EconomyVaultCore

## E2: Verhaltens-Einheiten für Resource-Dealing und Planeten-Upgrades.
var _deal_unit: EconomyDealUnit
var _upgrade_unit: EconomyUpgradeUnit


func _init() -> void:
	_vault_core = EconomyVaultCore.new(self)
	_deal_unit = EconomyDealUnit.new(self)
	_upgrade_unit = EconomyUpgradeUnit.new(self)


func reset_vaults() -> void:
	_vault_core.reset_vaults()

func reset() -> void:
	_vault_core.reset()

func credit_transport_resources(faction: StringName, resource_id: StringName, amount: int) -> bool:
	return _vault_core.credit_transport_resources(faction, resource_id, amount)

func get_faction_credits(faction: StringName) -> int:
	return _vault_core.get_faction_credits(faction)

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
	worker_transport_started.emit(transport_id, faction, amount)
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
	worker_transport_phase_changed.emit(transport_id, phase)
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
	worker_transport_phase_changed.emit(transport_id, record["phase"])
	worker_transport_records.erase(transport_id)
	return true

func add_faction_credits(faction: StringName, amount: int) -> int:
	return _vault_core.add_faction_credits(faction, amount)

func can_spend_faction_credits(faction: StringName, amount: int) -> bool:
	return _vault_core.can_spend_faction_credits(faction, amount)

func spend_faction_credits(faction: StringName, amount: int) -> bool:
	return _vault_core.spend_faction_credits(faction, amount)

func can_spend_cost(faction: StringName, resource_id: StringName, resource_amount: int, credit_amount: int) -> bool:
	return _vault_core.can_spend_cost(faction, resource_id, resource_amount, credit_amount)

func spend_cost(faction: StringName, resource_id: StringName, resource_amount: int, credit_amount: int) -> bool:
	return _vault_core.spend_cost(faction, resource_id, resource_amount, credit_amount)

func get_faction_resource(faction: StringName, resource_id: StringName) -> int:
	return _vault_core.get_faction_resource(faction, resource_id)

func get_faction_vault_snapshot(faction: StringName) -> Dictionary:
	return _vault_core.get_faction_vault_snapshot(faction)

func add_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> int:
	return _vault_core.add_faction_resource(faction, resource_id, amount)

func can_spend_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> bool:
	return _vault_core.can_spend_faction_resource(faction, resource_id, amount)

func spend_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> bool:
	return _vault_core.spend_faction_resource(faction, resource_id, amount)

func set_planet_resource(planet_id: StringName, resource_id: StringName) -> void:
	_vault_core.set_planet_resource(planet_id, resource_id)

func resource_of(planet_id: StringName) -> StringName:
	return _vault_core.resource_of(planet_id)

## E2: Delegation an EconomyDealUnit.
func deal_resources(catalog: PlanetCatalog, pool: ResourcePool = null, seed_value: int = 0) -> void:
	_deal_unit.deal_resources(catalog, pool, seed_value)

## E2: Delegation an EconomyDealUnit.
func deal_resources_for_planets(planet_data: Array, pool: ResourcePool = null, seed_value: int = 0) -> void:
	_deal_unit.deal_resources_for_planets(planet_data, pool, seed_value)

## E2: Delegation an EconomyDealUnit.
func validate_resources(pool: ResourcePool = null, homeworlds: Dictionary = {}) -> PackedStringArray:
	return _deal_unit.validate_resources(pool, homeworlds)

func resource_snapshot() -> Dictionary:
	return _vault_core.resource_snapshot()

func available_workers(planet_id: StringName, total_workers: int) -> int:
	return _vault_core.available_workers(planet_id, total_workers)

func reserve_workers(planet_id: StringName, job_id: StringName, amount: int, total_workers: int) -> bool:
	return _vault_core.reserve_workers(planet_id, job_id, amount, total_workers)

func release_workers(planet_id: StringName, job_id: StringName) -> int:
	return _vault_core.release_workers(planet_id, job_id)

## E2: Delegation an EconomyUpgradeUnit.
func can_purchase_upgrade(faction: StringName, planet_id: StringName, upgrade_id: StringName, available_worker_count: int = -1, catalog: PlanetUpgradeCatalog = null) -> bool:
	return _upgrade_unit.can_purchase_upgrade(faction, planet_id, upgrade_id, available_worker_count, catalog)

## E2: Delegation an EconomyUpgradeUnit.
func purchase_upgrade(faction: StringName, planet_id: StringName, upgrade_id: StringName, available_worker_count: int = -1, catalog: PlanetUpgradeCatalog = null) -> bool:
	return _upgrade_unit.purchase_upgrade(faction, planet_id, upgrade_id, available_worker_count, catalog)

## E2: Delegation an EconomyUpgradeUnit.
func can_purchase_upgrade_with_domains(
	planet_id: StringName,
	upgrade_id: StringName,
	faction_domain: FactionDomain,
	tech_domain: TechDomain,
	catalog: PlanetUpgradeCatalog = null,
	available_worker_count: int = -1
) -> bool:
	return _upgrade_unit.can_purchase_upgrade_with_domains(planet_id, upgrade_id, faction_domain, tech_domain, catalog, available_worker_count)

## E2: Delegation an EconomyUpgradeUnit.
func purchase_upgrade_with_domains(
	planet_id: StringName,
	upgrade_id: StringName,
	faction_domain: FactionDomain,
	tech_domain: TechDomain,
	catalog: PlanetUpgradeCatalog = null,
	available_worker_count: int = -1
) -> bool:
	return _upgrade_unit.purchase_upgrade_with_domains(planet_id, upgrade_id, faction_domain, tech_domain, catalog, available_worker_count)

## E2: Delegation an EconomyUpgradeUnit.
func upgrade_build_in_progress(planet_id: StringName, upgrade_id: StringName = &"") -> bool:
	return _upgrade_unit.upgrade_build_in_progress(planet_id, upgrade_id)

## E2: Delegation an EconomyUpgradeUnit.
func upgrade_build_remaining(planet_id: StringName, upgrade_id: StringName) -> float:
	return _upgrade_unit.upgrade_build_remaining(planet_id, upgrade_id)

## E2: Delegation an EconomyUpgradeUnit.
func advance_upgrade_builds(delta: float) -> void:
	_upgrade_unit.advance_upgrade_builds(delta)

## E2: Delegation an EconomyUpgradeUnit.
func abort_upgrade_build(planet_id: StringName, upgrade_id: StringName) -> bool:
	return _upgrade_unit.abort_upgrade_build(planet_id, upgrade_id)

## E2: Delegation an EconomyUpgradeUnit.
func has_planet_upgrade(planet_id: StringName, upgrade_id: StringName) -> bool:
	return _upgrade_unit.has_planet_upgrade(planet_id, upgrade_id)

## E2: Delegation an EconomyUpgradeUnit.
func get_planet_upgrades(planet_id: StringName) -> Array[StringName]:
	return _upgrade_unit.get_planet_upgrades(planet_id)

## E2: Delegation an EconomyUpgradeUnit.
func add_planet_upgrade(planet_id: StringName, upgrade_id: StringName) -> void:
	_upgrade_unit.add_planet_upgrade(planet_id, upgrade_id)

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

## Domain-ref overload: queries faction + tech requirements via the domain
## objects so GameState.can_build_worker_factory() becomes a one-liner.
func can_build_worker_factory_with_domains(
	planet_id: StringName,
	faction_domain: FactionDomain,
	tech_domain: TechDomain,
	cost_resource: StringName = GameState.RES_MATERIAL,
	cost_amount: int = 5,
	credit_cost: int = 5
) -> bool:
	var faction: StringName = faction_domain.faction_of(planet_id)
	return can_build_worker_factory(
		faction,
		planet_id,
		has_planet_upgrade(planet_id, &"shipyard"),
		faction_domain.has_scanned_planet(faction),
		tech_domain.has_technology(faction, GameState.TECH_WORKER_AUTOMATION),
		-1,
		cost_resource,
		cost_amount,
		credit_cost
	)

## Domain-ref overload: same as can_build_worker_factory_with_domains but also
## executes the build so GameState.build_worker_factory() becomes a one-liner.
func build_worker_factory_with_domains(
	planet_id: StringName,
	faction_domain: FactionDomain,
	tech_domain: TechDomain,
	cost_resource: StringName = GameState.RES_MATERIAL,
	cost_amount: int = 5,
	credit_cost: int = 5
) -> bool:
	var faction: StringName = faction_domain.faction_of(planet_id)
	return build_worker_factory(
		faction,
		planet_id,
		has_planet_upgrade(planet_id, &"shipyard"),
		faction_domain.has_scanned_planet(faction),
		tech_domain.has_technology(faction, GameState.TECH_WORKER_AUTOMATION),
		-1,
		cost_resource,
		cost_amount,
		credit_cost
	)

## Encapsulates resource looting so GameState.steal_resources() becomes a
## one-liner delegation. Transfers a fraction of the planet's local stock to
## the attacker's faction vault.
func steal_resources(planet_id: StringName, attacker_faction: StringName, percentage: float = 0.5) -> Dictionary:
	var stolen: Dictionary = {}
	var vault := local_vault(planet_id).duplicate()
	for resource_id in vault:
		var amount: int = int(vault[resource_id])
		if amount <= 0:
			continue
		var take: int = maxi(1, int(round(float(amount) * clampf(percentage, 0.0, 1.0))))
		if take <= 0:
			continue
		spend_local_resource(planet_id, resource_id as StringName, take)
		add_faction_resource(attacker_faction, resource_id as StringName, take)
		stolen[resource_id] = take
	return stolen


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

## Domain-ref overload: guards (faction validity, planet ownership, scan) run
## inside EconomyDomain so GameState.register_gathering_workers() becomes a
## pure delegation call. Returns the new worker count on the target planet.
func register_gathering_workers_with_domains(
	faction: StringName,
	planet_id: StringName,
	worker_amount: int,
	faction_domain: FactionDomain,
	source_planet_id: StringName = &""
) -> int:
	if faction == GameState.FACTION_NEUTRAL or faction.is_empty():
		return 0
	if faction_domain.faction_of(planet_id) != GameState.FACTION_NEUTRAL:
		return 0
	if not faction_domain.has_scanned_planet(faction, planet_id):
		return 0
	register_gathering_workers(faction, planet_id, source_planet_id, worker_amount)
	return gathering_workers_on(faction, planet_id)

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
	return _vault_core.is_valid_resource_id(resource_id)

# --- LOCAL VAULTS (per-planet) ---

func local_vault(planet_id: StringName) -> Dictionary:
	return _vault_core.local_vault(planet_id)

func get_local_resource(planet_id: StringName, resource_id: StringName) -> int:
	return _vault_core.get_local_resource(planet_id, resource_id)

func add_local_resource(planet_id: StringName, resource_id: StringName, amount: int) -> int:
	return _vault_core.add_local_resource(planet_id, resource_id, amount)

func spend_local_resource(planet_id: StringName, resource_id: StringName, amount: int) -> bool:
	return _vault_core.spend_local_resource(planet_id, resource_id, amount)

func transfer_resources(from_planet: StringName, to_planet: StringName, resource_id: StringName, amount: int) -> bool:
	return _vault_core.transfer_resources(from_planet, to_planet, resource_id, amount)

## Seeds a small deterministic starting stock of each planet's own resource.
func seed_local_resources(planet_ids: Array, pool: ResourcePool = null, seed_value: int = 0) -> void:
	_vault_core.seed_local_resources(planet_ids, pool, seed_value)

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

func can_place_building(planet_id: StringName, building_id: StringName, faction_domain: FactionDomain, tech_domain: TechDomain, catalog: BuildingCatalog = null) -> bool:
	var faction: StringName = faction_domain.faction_of(planet_id)
	if faction == GameState.FACTION_NEUTRAL:
		return false
	var cat: BuildingCatalog = catalog if catalog != null else GameState.DEFAULT_BUILDING_CATALOG
	if cat == null:
		return false
	var building: BuildingDefinition = cat.resolve(building_id)
	if building == null:
		return false
	if not String(building.required_tech_id).is_empty() and not tech_domain.has_technology(faction, building.required_tech_id):
		return false
	return can_spend_building_cost(faction, building)

func place_building(planet_id: StringName, building_id: StringName, q: int, r: int, faction_domain: FactionDomain, tech_domain: TechDomain, catalog: BuildingCatalog = null) -> bool:
	if not can_place_building(planet_id, building_id, faction_domain, tech_domain, catalog):
		return false
	var cat: BuildingCatalog = catalog if catalog != null else GameState.DEFAULT_BUILDING_CATALOG
	var building: BuildingDefinition = cat.resolve(building_id)
	var faction: StringName = faction_domain.faction_of(planet_id)
	var job_id := StringName("building_%s_%d_%d" % [String(building_id), q, r])
	if building_job_in_progress(planet_id, q, r) or planet_building_at(planet_id, q, r) != &"":
		return false
	var total_workers: int = maxi(int(faction_domain.starting_workers.get(planet_id, 0)), building.workers_required)
	if building.workers_required > 0 and not reserve_workers(planet_id, job_id, building.workers_required, total_workers):
		return false
	if not spend_building_cost(faction, building):
		release_workers(planet_id, job_id)
		return false
	if building.build_time > 0.0:
		var queued: bool = queue_planet_building(
			planet_id, building_id, q, r, faction, job_id, building.build_time,
			{"resources": building.cost_resources, "credits": building.credit_cost}
		)
		if queued:
			return true
		# Roll back an impossible queue without leaking costs or labor.
		release_workers(planet_id, job_id)
		for resource_id in building.cost_resources:
			add_faction_resource(faction, resource_id as StringName, int(building.cost_resources[resource_id]))
		add_faction_credits(faction, building.credit_cost)
		return false
	release_workers(planet_id, job_id)
	record_planet_building(planet_id, building_id, q, r)
	return true

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

func capture_snapshot(data: RunSaveData) -> void:
	if data == null:
		return
	data.faction_vaults = faction_vaults.duplicate(true)
	data.faction_credits = faction_credits.duplicate(true)
	data.worker_reservations = worker_reservations.duplicate(true)
	data.upgrade_build_jobs = upgrade_build_jobs.duplicate(true)
	data.planet_resources = planet_resources.duplicate(true)
	data.planet_upgrades = planet_upgrades.duplicate(true)
	data.worker_factories = worker_factories.duplicate(true)
	data.gathering_workers = gathering_workers.duplicate(true)
	data.gathering_sources = gathering_sources.duplicate(true)
	data.local_vaults = local_vaults.duplicate(true)
	data.trade_routes = trade_routes.duplicate(true)
	data.planet_buildings = planet_buildings.duplicate(true)
	data.building_jobs = building_jobs.duplicate(true)
	data.local_seeded_planets = _local_seeded_planets.duplicate(true)
	data.worker_transport_records = worker_transport_records.duplicate(true)
	data.next_trade_route_index = _next_trade_route_index
	data.next_worker_transport_index = _next_worker_transport_index

func restore_snapshot(data: RunSaveData) -> void:
	if data == null:
		return
	reset()
	faction_vaults = RunSaveData.restore_dict(data.faction_vaults)
	faction_credits = RunSaveData.restore_dict(data.faction_credits)
	worker_reservations = RunSaveData.restore_dict(data.worker_reservations)
	upgrade_build_jobs = RunSaveData.restore_dict(data.upgrade_build_jobs)
	planet_resources = RunSaveData.restore_dict(data.planet_resources)
	planet_upgrades = RunSaveData.restore_dict(data.planet_upgrades)
	worker_factories = RunSaveData.restore_dict(data.worker_factories)
	gathering_workers = RunSaveData.restore_dict(data.gathering_workers)
	gathering_sources = RunSaveData.restore_dict(data.gathering_sources)
	local_vaults = RunSaveData.restore_dict(data.local_vaults)
	trade_routes = RunSaveData.restore_dict(data.trade_routes)
	planet_buildings = RunSaveData.restore_dict(data.planet_buildings)
	building_jobs = RunSaveData.restore_dict(data.building_jobs)
	_local_seeded_planets = RunSaveData.restore_dict(data.local_seeded_planets)
	worker_transport_records = RunSaveData.restore_dict(data.worker_transport_records)
	_next_trade_route_index = data.next_trade_route_index
	_next_worker_transport_index = data.next_worker_transport_index
