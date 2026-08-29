class_name EconomyUpgradeUnit
extends RefCounted

## E2: Verhaltens-Einheit für Planeten-Upgrades aus EconomyDomain.
##
## Verantwortlich: has_planet_upgrade, get_planet_upgrades, add_planet_upgrade,
## can_purchase_upgrade, purchase_upgrade, can_purchase_upgrade_with_domains,
## purchase_upgrade_with_domains, upgrade_build_in_progress,
## upgrade_build_remaining, advance_upgrade_builds, abort_upgrade_build.
##
## State-Dictionarys und Signale bleiben auf der EconomyDomain-Fassade.
## Diese Einheit erhält die Fassade als `_owner` und nutzt dessen
## Methoden für Vault-/Worker-Operationen.

var _owner: EconomyDomain


func _init(owner: EconomyDomain) -> void:
	_owner = owner


func has_planet_upgrade(planet_id: StringName, upgrade_id: StringName) -> bool:
	if not _owner.planet_upgrades.has(planet_id):
		return false
	var list: Array = _owner.planet_upgrades[planet_id]
	return list.has(upgrade_id)


func get_planet_upgrades(planet_id: StringName) -> Array[StringName]:
	if not _owner.planet_upgrades.has(planet_id):
		return []
	var typed_list: Array[StringName] = []
	for item in _owner.planet_upgrades[planet_id]:
		typed_list.append(item as StringName)
	return typed_list


func add_planet_upgrade(planet_id: StringName, upgrade_id: StringName) -> void:
	if String(planet_id).is_empty() or String(upgrade_id).is_empty():
		return
	if not _owner.planet_upgrades.has(planet_id):
		_owner.planet_upgrades[planet_id] = []
	var list: Array = _owner.planet_upgrades[planet_id]
	if not list.has(upgrade_id):
		list.append(upgrade_id)
		_owner.planet_upgrades[planet_id] = list
		_owner.planet_upgraded.emit(planet_id, upgrade_id)


func can_purchase_upgrade(faction: StringName, planet_id: StringName, upgrade_id: StringName, available_worker_count: int = -1, catalog: PlanetUpgradeCatalog = null) -> bool:
	var effective_catalog: PlanetUpgradeCatalog = catalog if catalog != null else GameState.DEFAULT_UPGRADE_CATALOG
	if effective_catalog == null or faction == GameState.FACTION_NEUTRAL or not _owner.faction_vaults.has(faction):
		return false
	var upgrade: PlanetUpgradeDefinition = effective_catalog.resolve(upgrade_id)
	if upgrade == null or has_planet_upgrade(planet_id, upgrade_id):
		return false
	if _owner.upgrade_build_jobs.has(planet_id) and (_owner.upgrade_build_jobs[planet_id] as Dictionary).has(upgrade_id):
		return false
	if not effective_catalog.can_unlock(get_planet_upgrades(planet_id), upgrade_id):
		return false
	if available_worker_count >= 0 and available_worker_count < upgrade.workers_required:
		return false
	return _owner.can_spend_cost(faction, upgrade.cost_resource, upgrade.cost_amount, upgrade.credit_cost)


func purchase_upgrade(faction: StringName, planet_id: StringName, upgrade_id: StringName, available_worker_count: int = -1, catalog: PlanetUpgradeCatalog = null) -> bool:
	if not can_purchase_upgrade(faction, planet_id, upgrade_id, available_worker_count, catalog):
		return false
	var effective_catalog: PlanetUpgradeCatalog = catalog if catalog != null else GameState.DEFAULT_UPGRADE_CATALOG
	var upgrade: PlanetUpgradeDefinition = effective_catalog.resolve(upgrade_id)
	var reservation_id := StringName("upgrade_%s_%s" % [String(planet_id), String(upgrade_id)])
	if upgrade.workers_required > 0 and available_worker_count >= 0 and not _owner.reserve_workers(planet_id, reservation_id, upgrade.workers_required, available_worker_count):
		return false
	if not _owner.spend_cost(faction, upgrade.cost_resource, upgrade.cost_amount, upgrade.credit_cost):
		_owner.release_workers(planet_id, reservation_id)
		return false
	if upgrade.build_time > 0.0:
		if not _owner.upgrade_build_jobs.has(planet_id):
			_owner.upgrade_build_jobs[planet_id] = {}
		_owner.upgrade_build_jobs[planet_id][upgrade_id] = {
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
		_owner.release_workers(planet_id, reservation_id)
	return true


## Domain-ref overload: tech-requirement check and starting-worker lookup run
## inside EconomyDomain so GameState.can_purchase_upgrade() becomes a one-liner.
## Priority (highest→lowest):
##   1. available_worker_count >= 0  — explicit caller cap (e.g. test with 1 worker)
##   2. faction_domain.starting_workers[planet_id] — known worker pool for planet
##   3. -1 — planet not yet registered; worker check skipped (original behaviour)
func can_purchase_upgrade_with_domains(
	planet_id: StringName,
	upgrade_id: StringName,
	faction_domain: FactionDomain,
	tech_domain: TechDomain,
	catalog: PlanetUpgradeCatalog = null,
	available_worker_count: int = -1
) -> bool:
	var faction: StringName = faction_domain.faction_of(planet_id)
	var effective_catalog: PlanetUpgradeCatalog = catalog if catalog != null else GameState.DEFAULT_UPGRADE_CATALOG
	var upgrade: PlanetUpgradeDefinition = effective_catalog.resolve(upgrade_id) if effective_catalog != null else null
	if upgrade == null:
		return false
	if not String(upgrade.required_technology_id).is_empty() and not tech_domain.has_technology(faction, upgrade.required_technology_id):
		return false
	# Explicit cap takes priority. If absent, use the registered starting-worker
	# pool. If the planet is unknown (e.g. after reset before seed_starting_workers),
	# pass -1 so the flat can_purchase_upgrade skips the worker check entirely.
	var workforce: int
	if available_worker_count >= 0:
		workforce = available_worker_count
	elif faction_domain.starting_workers.has(planet_id):
		workforce = int(faction_domain.starting_workers.get(planet_id, 0))
	else:
		workforce = -1
	return can_purchase_upgrade(faction, planet_id, upgrade_id, workforce, effective_catalog)


## Domain-ref overload: combines the tech/worker checks and the purchase in one
## call so GameState.purchase_upgrade() becomes a one-liner delegation.
## Same priority rules as can_purchase_upgrade_with_domains.
func purchase_upgrade_with_domains(
	planet_id: StringName,
	upgrade_id: StringName,
	faction_domain: FactionDomain,
	tech_domain: TechDomain,
	catalog: PlanetUpgradeCatalog = null,
	available_worker_count: int = -1
) -> bool:
	if not can_purchase_upgrade_with_domains(planet_id, upgrade_id, faction_domain, tech_domain, catalog, available_worker_count):
		return false
	var faction: StringName = faction_domain.faction_of(planet_id)
	var effective_catalog: PlanetUpgradeCatalog = catalog if catalog != null else GameState.DEFAULT_UPGRADE_CATALOG
	# Same priority logic for the purchase call.
	var workforce: int
	if available_worker_count >= 0:
		workforce = available_worker_count
	elif faction_domain.starting_workers.has(planet_id):
		workforce = int(faction_domain.starting_workers.get(planet_id, 0))
	else:
		workforce = -1
	return purchase_upgrade(faction, planet_id, upgrade_id, workforce, effective_catalog)


func upgrade_build_in_progress(planet_id: StringName, upgrade_id: StringName = &"") -> bool:
	if not _owner.upgrade_build_jobs.has(planet_id):
		return false
	if String(upgrade_id).is_empty():
		return not (_owner.upgrade_build_jobs[planet_id] as Dictionary).is_empty()
	return (_owner.upgrade_build_jobs[planet_id] as Dictionary).has(upgrade_id)


func upgrade_build_remaining(planet_id: StringName, upgrade_id: StringName) -> float:
	if not upgrade_build_in_progress(planet_id, upgrade_id):
		return 0.0
	return float((_owner.upgrade_build_jobs[planet_id] as Dictionary)[upgrade_id].get("remaining", 0.0))


func advance_upgrade_builds(delta: float) -> void:
	if delta <= 0.0:
		return
	for planet_value in _owner.upgrade_build_jobs.keys():
		var planet_id: StringName = planet_value as StringName
		var jobs: Dictionary = _owner.upgrade_build_jobs[planet_id]
		for upgrade_value in jobs.keys():
			var upgrade_id: StringName = upgrade_value as StringName
			var job: Dictionary = jobs[upgrade_id]
			var remaining: float = float(job.get("remaining", 0.0)) - delta
			if remaining > 0.0:
				job["remaining"] = remaining
				continue
			jobs.erase(upgrade_id)
			add_planet_upgrade(planet_id, upgrade_id)
			_owner.release_workers(planet_id, job.get("reservation_id", &"") as StringName)
		if jobs.is_empty():
			_owner.upgrade_build_jobs.erase(planet_id)


func abort_upgrade_build(planet_id: StringName, upgrade_id: StringName) -> bool:
	if not upgrade_build_in_progress(planet_id, upgrade_id):
		return false
	var job: Dictionary = (_owner.upgrade_build_jobs[planet_id] as Dictionary).get(upgrade_id, {})
	(_owner.upgrade_build_jobs[planet_id] as Dictionary).erase(upgrade_id)
	_owner.release_workers(planet_id, job.get("reservation_id", &"") as StringName)
	_owner.add_faction_resource(job.get("faction", &"") as StringName, job.get("cost_resource", &"") as StringName, int(job.get("cost_amount", 0)))
	_owner.add_faction_credits(job.get("faction", &"") as StringName, int(job.get("credit_cost", 0)))
	return true
