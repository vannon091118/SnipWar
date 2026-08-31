class_name EconomyGatheringTransportUnit
extends RefCounted

## R-007 (E4a): Verhaltens-Einheit für Gathering und Worker-Transport aus
## EconomyDomain.
##
## Verantwortlich: register_gathering_workers(_with_domains), withdraw,
## gathering_workers_on, gather_income_tick, generate_resources_for_planet,
## begin/update/set_escorted/get/complete_worker_transport.
##
## State-Dictionarys und Signale bleiben auf der EconomyDomain-Fassade.
## Diese Einheit erhält die Fassade als `_owner` und nutzt dessen Methoden
## für Vault-/Resource-/Signal-Operationen. Der Route-Owner wird über einen
## injizierten Callable-Resolver aufgelöst (kein GameState-SceneTree-Zugriff);
## ohne injizierten Resolver darf ausschließlich FACTION_NEUTRAL geliefert
## werden, damit Headless-/Preflight-Tests ohne GameState identisch bleiben.

var _owner: Variant
var _route_owner_resolver: Callable


func _init(owner: Variant, route_owner_resolver: Callable = Callable()) -> void:
	_owner = owner
	_route_owner_resolver = route_owner_resolver


## Injiziert den Route-Owner-Resolver nachträglich (GameState->_init).
## Ein leerer Callable gilt als nicht injiziert → _route_owner liefert NEUTRAL.
func set_route_owner_resolver(resolver: Callable) -> void:
	if resolver.is_valid():
		_route_owner_resolver = resolver


## Liefert den Fraktions-Owner eines Planeten über den injizierten Resolver.
## Ohne Resolver (nackte EconomyDomain in Tests) → FACTION_NEUTRAL,
## damit synthetische Planeten weiterhin als unowned behandelt werden.
func _route_owner(planet_id: StringName) -> StringName:
	if _route_owner_resolver.is_valid():
		var result: Variant = _route_owner_resolver.call(planet_id)
		if result is StringName:
			return result
		if result is String:
			return StringName(result)
	return GameState.FACTION_NEUTRAL


# --- GATHERING ---


func register_gathering_workers(faction: StringName, planet_id: StringName, source_planet_id: StringName, count: int) -> void:
	if String(faction).is_empty() or String(planet_id).is_empty() or count <= 0:
		return
	if not _owner.gathering_workers.has(faction):
		_owner.gathering_workers[faction] = {}
	if not _owner.gathering_sources.has(faction):
		_owner.gathering_sources[faction] = {}
	var current: int = _owner.gathering_workers[faction].get(planet_id, 0)
	_owner.gathering_workers[faction][planet_id] = current + count
	_owner.gathering_sources[faction][planet_id] = source_planet_id
	_owner.gathering_started.emit(faction, planet_id, count)


## Domain-ref overload: guards (faction validity, planet ownership, scan) run
## inside the unit so GameState.register_gathering_workers() becomes a pure
## delegation call. Returns the new worker count on the target planet.
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
	if not _owner.gathering_sources.has(faction):
		return &""
	return _owner.gathering_sources[faction].get(planet_id, &"") as StringName


func withdraw_gathering_workers(faction: StringName, planet_id: StringName, amount: int = -1) -> Dictionary:
	if not _owner.gathering_workers.has(faction) or not _owner.gathering_workers[faction].has(planet_id):
		return {"count": 0, "source_planet_id": &""}
	var current: int = _owner.gathering_workers[faction].get(planet_id, 0)
	var count: int = current if amount < 0 else mini(current, maxi(amount, 0))
	var source_planet_id: StringName = get_gathering_source(faction, planet_id)
	if count <= 0:
		return {"count": 0, "source_planet_id": source_planet_id}
	var remaining := current - count
	if remaining <= 0:
		_owner.gathering_workers[faction].erase(planet_id)
		if _owner.gathering_sources.has(faction):
			_owner.gathering_sources[faction].erase(planet_id)
	else:
		_owner.gathering_workers[faction][planet_id] = remaining
	if count > 0:
		_owner.gathering_withdrawn.emit(faction, planet_id, count)
	return {"count": count, "source_planet_id": source_planet_id}


func gathering_workers_on(faction: StringName, planet_id: StringName) -> int:
	if not _owner.gathering_workers.has(faction):
		return 0
	return int(_owner.gathering_workers[faction].get(planet_id, 0))


func gather_income_tick(base_amounts: Dictionary, catalog: PlanetUpgradeCatalog = null) -> int:
	var effective_catalog: PlanetUpgradeCatalog = catalog if catalog != null else GameState.DEFAULT_UPGRADE_CATALOG
	var total_earned := 0
	for faction in _owner.gathering_workers:
		var faction_name := faction as StringName
		var planets: Dictionary = _owner.gathering_workers[faction]
		for p_id in planets:
			var planet_id := p_id as StringName
			var count: int = planets[p_id]
			if count <= 0:
				continue
			var res_id: StringName = _owner.resource_of(planet_id)
			if not _owner._is_valid_resource_id(res_id):
				continue
			var base_amt: int = maxi(int(base_amounts.get(planet_id, 1)), 1)
			var gather_multiplier := 1.0
			if effective_catalog != null:
				for upgrade_id in _owner.get_planet_upgrades(planet_id):
					var upgrade: PlanetUpgradeDefinition = effective_catalog.resolve(upgrade_id)
					if upgrade != null and upgrade.trait_definition != null:
						gather_multiplier *= upgrade.trait_definition.gather_income_multiplier
			var earned: int = maxi(1, int(round(float(count * base_amt) * gather_multiplier)))
			_owner.add_faction_resource(faction_name, res_id, earned)
			total_earned += earned
			_owner.resources_collected.emit(faction_name, planet_id, res_id, earned)

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
	if faction == GameState.FACTION_NEUTRAL or not _owner.faction_vaults.has(faction):
		return 0
	var resource_id: StringName = _owner.resource_of(planet_id)
	if String(resource_id).is_empty() or not _owner._is_valid_resource_id(resource_id):
		return 0
	var multiplier := 1.0
	for up_id in _owner.get_planet_upgrades(planet_id):
		var def: PlanetUpgradeDefinition = catalog.resolve(up_id) if catalog != null else null
		if def != null and def.trait_definition != null:
			multiplier += def.trait_definition.production_boost
			var maintenance_resource: StringName = def.trait_definition.maintenance_cost_resource
			if not String(maintenance_resource).is_empty() and def.trait_definition.maintenance_cost_amount > 0:
				_owner.spend_faction_resource(faction, maintenance_resource, def.trait_definition.maintenance_cost_amount)
			if def.trait_definition.maintenance_credit_cost > 0:
				_owner.spend_faction_credits(faction, def.trait_definition.maintenance_credit_cost)
	for planet_technology_id in tech.get_planet_technologies(planet_id):
		var planet_technology: TechnologyDefinition = GameState.DEFAULT_TECHNOLOGY_CATALOG.resolve(planet_technology_id)
		if planet_technology != null:
			multiplier *= planet_technology.production_multiplier
	var final_amount: int = maxi(1, int(round(float(maxi(base_amount, 1)) * multiplier)))
	_owner.add_faction_resource(faction, resource_id, final_amount)
	_owner.resource_generated.emit(planet_id, resource_id, final_amount)
	return final_amount


# --- WORKER TRANSPORT ---


## Creates the data-side record for a physical worker round-trip. The visible
## WorkerCluster is disposable; this record is the source of truth across
## chunk cycling and scene rebuilds.
func begin_worker_transport(faction: StringName, source_planet_id: StringName, destination_planet_id: StringName, amount: int, duration: float, route_path: Array[Vector2]) -> StringName:
	if faction == GameState.FACTION_NEUTRAL or String(source_planet_id).is_empty() or String(destination_planet_id).is_empty() or amount <= 0:
		return &""
	_owner._next_worker_transport_index += 1
	var transport_id := StringName("worker_transport_%d" % _owner._next_worker_transport_index)
	_owner.worker_transport_records[transport_id] = {
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
	_owner.worker_transport_started.emit(transport_id, faction, amount)
	return transport_id


func update_worker_transport(transport_id: StringName, phase: StringName, cargo_resource_id: StringName = &"", cargo_amount: int = 0) -> bool:
	if not _owner.worker_transport_records.has(transport_id):
		return false
	var record: Dictionary = _owner.worker_transport_records[transport_id]
	record["phase"] = phase
	if not String(cargo_resource_id).is_empty():
		record["cargo_resource_id"] = cargo_resource_id
	record["cargo_amount"] = maxi(cargo_amount, 0)
	_owner.worker_transport_records[transport_id] = record
	_owner.worker_transport_phase_changed.emit(transport_id, phase)
	return true


func set_worker_transport_escorted(transport_id: StringName, escorted: bool = true) -> bool:
	if not _owner.worker_transport_records.has(transport_id):
		return false
	var record: Dictionary = _owner.worker_transport_records[transport_id]
	record["escorted"] = escorted
	_owner.worker_transport_records[transport_id] = record
	return true


func get_worker_transport_records(faction: StringName = &"") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in _owner.worker_transport_records.values():
		var record: Dictionary = value as Dictionary
		if record != null and (String(faction).is_empty() or record.get("faction", &"") == faction):
			result.append(record.duplicate(true))
	return result


func complete_worker_transport(transport_id: StringName, delivered: bool = true) -> bool:
	if not _owner.worker_transport_records.has(transport_id):
		return false
	var record: Dictionary = _owner.worker_transport_records[transport_id]
	record["phase"] = &"delivered" if delivered else &"cancelled"
	_owner.worker_transport_phase_changed.emit(transport_id, record["phase"])
	_owner.worker_transport_records.erase(transport_id)
	return true