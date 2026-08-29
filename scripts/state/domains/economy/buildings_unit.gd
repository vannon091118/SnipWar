class_name EconomyBuildingsUnit
extends RefCounted

## R-007 (E4b): Verhaltens-Einheit für Planeten-Gebäude auf dem Grid aus
## EconomyDomain.
##
## Verantwortlich: can_spend_building_cost, spend_building_cost,
## queue_planet_building, building_job_in_progress, advance_building_jobs,
## abort_building_job, record_planet_building, remove_planet_building,
## can_place_building, place_building, planet_building_at, planet_buildings_of.
##
## State-Dictionarys (planet_buildings, building_jobs) und Signale
## (building_placed, building_removed) bleiben auf der EconomyDomain-Fassade.
## Diese Einheit erhält die Fassade als `_owner` und nutzt deren Vault-,
## Worker-Reservierungs- und Signal-Methoden. Die Baustellen-Queue ist
## dieser Einheit die Zustandsverantwortung zugeordnet; Rollback-Reihenfolge
## (release → refund; un-queue → refund + release) ist Vertragsbestandteil und
## darf nicht verändert werden.

var _owner: Variant


func _init(owner: Variant) -> void:
	_owner = owner


func can_spend_building_cost(faction: StringName, building: BuildingDefinition) -> bool:
	if building == null or not _owner.can_spend_faction_credits(faction, building.credit_cost):
		return false
	for resource_id in building.cost_resources:
		var amount: int = int(building.cost_resources[resource_id])
		if amount > 0 and not _owner.can_spend_faction_resource(faction, resource_id as StringName, amount):
			return false
	return true


func spend_building_cost(faction: StringName, building: BuildingDefinition) -> bool:
	if not can_spend_building_cost(faction, building):
		return false
	for resource_id in building.cost_resources:
		var amount: int = int(building.cost_resources[resource_id])
		if amount > 0:
			_owner.spend_faction_resource(faction, resource_id as StringName, amount)
	return _owner.spend_faction_credits(faction, building.credit_cost)


func queue_planet_building(planet_id: StringName, building_id: StringName, q: int, r: int, faction: StringName, reservation_id: StringName, build_time: float, costs: Dictionary) -> bool:
	var key := "%d:%d" % [q, r]
	if _owner.planet_building_at(planet_id, q, r) != &"" or _owner.building_jobs.get(planet_id, {}).has(key):
		return false
	if not _owner.building_jobs.has(planet_id):
		_owner.building_jobs[planet_id] = {}
	_owner.building_jobs[planet_id][key] = {
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
	return _owner.building_jobs.has(planet_id) and (_owner.building_jobs[planet_id] as Dictionary).has("%d:%d" % [q, r])


func advance_building_jobs(delta: float) -> void:
	if delta <= 0.0:
		return
	for planet_value in _owner.building_jobs.keys():
		var planet_id: StringName = planet_value as StringName
		var jobs: Dictionary = _owner.building_jobs[planet_id]
		for key in jobs.keys():
			var job: Dictionary = jobs[key]
			var remaining: float = float(job.get("remaining", 0.0)) - delta
			if remaining > 0.0:
				job["remaining"] = remaining
				continue
			jobs.erase(key)
			record_planet_building(planet_id, job.get("building_id", &"") as StringName, int(job.get("q", 0)), int(job.get("r", 0)))
			_owner.release_workers(planet_id, job.get("reservation_id", &"") as StringName)
		if jobs.is_empty():
			_owner.building_jobs.erase(planet_id)


func abort_building_job(planet_id: StringName, q: int, r: int) -> bool:
	var key := "%d:%d" % [q, r]
	if not building_job_in_progress(planet_id, q, r):
		return false
	var job: Dictionary = (_owner.building_jobs[planet_id] as Dictionary).get(key, {})
	(_owner.building_jobs[planet_id] as Dictionary).erase(key)
	_owner.release_workers(planet_id, job.get("reservation_id", &"") as StringName)
	var faction: StringName = job.get("faction", &"") as StringName
	var costs: Dictionary = job.get("costs", {}) as Dictionary
	for resource_id in costs.get("resources", {}).keys():
		_owner.add_faction_resource(faction, resource_id as StringName, int(costs["resources"][resource_id]))
	_owner.add_faction_credits(faction, int(costs.get("credits", 0)))
	return true


func record_planet_building(planet_id: StringName, building_id: StringName, q: int, r: int) -> void:
	if String(planet_id).is_empty() or String(building_id).is_empty():
		return
	if not _owner.planet_buildings.has(planet_id):
		_owner.planet_buildings[planet_id] = {}
	_owner.planet_buildings[planet_id]["%d:%d" % [q, r]] = building_id
	_owner.building_placed.emit(planet_id, building_id, q, r)


func remove_planet_building(planet_id: StringName, q: int, r: int) -> StringName:
	if not _owner.planet_buildings.has(planet_id):
		return &""
	var key := "%d:%d" % [q, r]
	var removed: StringName = _owner.planet_buildings[planet_id].get(key, &"") as StringName
	if String(removed).is_empty():
		return &""
	_owner.planet_buildings[planet_id].erase(key)
	_owner.building_removed.emit(planet_id, q, r)
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
	if building_job_in_progress(planet_id, q, r) or _owner.planet_building_at(planet_id, q, r) != &"":
		return false
	var total_workers: int = maxi(int(faction_domain.starting_workers.get(planet_id, 0)), building.workers_required)
	if building.workers_required > 0 and not _owner.reserve_workers(planet_id, job_id, building.workers_required, total_workers):
		return false
	if not spend_building_cost(faction, building):
		_owner.release_workers(planet_id, job_id)
		return false
	if building.build_time > 0.0:
		var queued: bool = queue_planet_building(
			planet_id, building_id, q, r, faction, job_id, building.build_time,
			{"resources": building.cost_resources, "credits": building.credit_cost}
		)
		if queued:
			return true
		# Roll back an impossible queue without leaking costs or labor.
		_owner.release_workers(planet_id, job_id)
		for resource_id in building.cost_resources:
			_owner.add_faction_resource(faction, resource_id as StringName, int(building.cost_resources[resource_id]))
		_owner.add_faction_credits(faction, building.credit_cost)
		return false
	_owner.release_workers(planet_id, job_id)
	record_planet_building(planet_id, building_id, q, r)
	return true


func planet_building_at(planet_id: StringName, q: int, r: int) -> StringName:
	if not _owner.planet_buildings.has(planet_id):
		return &""
	return _owner.planet_buildings[planet_id].get("%d:%d" % [q, r], &"") as StringName


func planet_buildings_of(planet_id: StringName) -> Dictionary:
	return _owner.planet_buildings.get(planet_id, {}).duplicate()
