class_name TechDomain
extends RefCounted

## Manages global and planetary technology research, prerequisites, and timed research jobs.

signal technology_researched(faction: StringName, technology_id: StringName)
signal planet_technology_researched(planet_id: StringName, technology_id: StringName)
signal research_started(faction: StringName, technology_id: StringName, remaining: float)

var researched_techs: Dictionary = {}
var planet_technologies: Dictionary = {}
var research_jobs: Dictionary = {}

func reset() -> void:
	researched_techs.clear()
	planet_technologies.clear()
	research_jobs.clear()

func has_technology(faction: StringName, technology_id: StringName) -> bool:
	if not researched_techs.has(faction):
		return false
	var list: Array = researched_techs[faction]
	return list.has(technology_id)

func get_researched_technologies(faction: StringName) -> Array[StringName]:
	if not researched_techs.has(faction):
		return []
	var typed_list: Array[StringName] = []
	for item in researched_techs[faction]:
		typed_list.append(item as StringName)
	return typed_list

func can_research_technology(faction: StringName, technology_id: StringName, catalog: TechnologyCatalog, economy: EconomyDomain, faction_domain: FactionDomain) -> bool:
	if catalog == null or String(faction).is_empty() or String(technology_id).is_empty():
		return false
	if has_technology(faction, technology_id) or research_in_progress(faction, technology_id):
		return false
	var tech: TechnologyDefinition = catalog.resolve(technology_id)
	if tech == null:
		return false
	if not catalog.can_research(get_researched_technologies(faction), technology_id):
		return false
	if tech.requires_discovery and not faction_domain.has_scanned_planet(faction):
		return false
	return economy.can_spend_cost(faction, tech.cost_resource, tech.cost_amount, tech.credit_cost)

func research_technology(faction: StringName, technology_id: StringName, catalog: TechnologyCatalog, economy: EconomyDomain, faction_domain: FactionDomain) -> bool:
	if not can_research_technology(faction, technology_id, catalog, economy, faction_domain):
		return false
	var tech: TechnologyDefinition = catalog.resolve(technology_id)
	if not economy.spend_cost(faction, tech.cost_resource, tech.cost_amount, tech.credit_cost):
		return false
	if tech.research_time <= 0.0:
		_complete_research(faction, technology_id)
	else:
		if not research_jobs.has(faction):
			research_jobs[faction] = {}
		research_jobs[faction][technology_id] = tech.research_time
		research_started.emit(faction, technology_id, tech.research_time)
	return true

func research_in_progress(faction: StringName, technology_id: StringName) -> bool:
	if not research_jobs.has(faction):
		return false
	return research_jobs[faction].has(technology_id)

func research_remaining(faction: StringName, technology_id: StringName) -> float:
	if not research_jobs.has(faction):
		return 0.0
	return float(research_jobs[faction].get(technology_id, 0.0))

func advance_research(delta: float) -> void:
	if delta <= 0.0 or research_jobs.is_empty():
		return
	for faction_value in research_jobs.keys():
		var faction: StringName = faction_value as StringName
		advance_research_faction(faction, delta)

## Advances only one faction's research jobs. The CPU ship builder uses this
## so its research progresses without speeding up the player's jobs (the
## global advance_research() would tick every faction).
func advance_research_faction(faction: StringName, delta: float) -> void:
	if delta <= 0.0 or not research_jobs.has(faction):
		return
	var jobs: Dictionary = research_jobs[faction]
	for tech_value in jobs.keys():
		var technology_id: StringName = tech_value as StringName
		var remaining: float = jobs[technology_id] - delta
		if remaining <= 0.0:
			jobs.erase(technology_id)
			_complete_research(faction, technology_id)
		else:
			jobs[technology_id] = remaining

func _complete_research(faction: StringName, technology_id: StringName) -> void:
	if not researched_techs.has(faction):
		researched_techs[faction] = []
	var list: Array = researched_techs[faction]
	if not list.has(technology_id):
		list.append(technology_id)
		researched_techs[faction] = list
		technology_researched.emit(faction, technology_id)

func has_planet_technology(planet_id: StringName, technology_id: StringName) -> bool:
	if not planet_technologies.has(planet_id):
		return false
	var list: Array = planet_technologies[planet_id]
	return list.has(technology_id)

func get_planet_technologies(planet_id: StringName) -> Array[StringName]:
	if not planet_technologies.has(planet_id):
		return []
	var typed_list: Array[StringName] = []
	for item in planet_technologies[planet_id]:
		typed_list.append(item as StringName)
	return typed_list

func can_research_planet_technology(faction: StringName, planet_id: StringName, technology_id: StringName, catalog: TechnologyCatalog, economy: EconomyDomain, faction_domain: FactionDomain) -> bool:
	if catalog == null or String(faction).is_empty() or String(planet_id).is_empty() or String(technology_id).is_empty():
		return false
	if not faction_domain.is_owned_by(planet_id, faction):
		return false
	if has_planet_technology(planet_id, technology_id):
		return false
	var tech: TechnologyDefinition = catalog.resolve(technology_id)
	if tech == null:
		return false
	if not catalog.can_research(get_planet_technologies(planet_id), technology_id):
		return false
	return economy.can_spend_cost(faction, tech.cost_resource, tech.cost_amount, tech.credit_cost)

func research_planet_technology(faction: StringName, planet_id: StringName, technology_id: StringName, catalog: TechnologyCatalog, economy: EconomyDomain, faction_domain: FactionDomain) -> bool:
	if not can_research_planet_technology(faction, planet_id, technology_id, catalog, economy, faction_domain):
		return false
	var tech: TechnologyDefinition = catalog.resolve(technology_id)
	if not economy.spend_cost(faction, tech.cost_resource, tech.cost_amount, tech.credit_cost):
		return false
	if not planet_technologies.has(planet_id):
		planet_technologies[planet_id] = []
	var list: Array = planet_technologies[planet_id]
	if not list.has(technology_id):
		list.append(technology_id)
		planet_technologies[planet_id] = list
		planet_technology_researched.emit(planet_id, technology_id)
	return true

func capture_snapshot(data: RunSaveData) -> void:
	if data == null:
		return
	data.researched_techs = researched_techs.duplicate(true)
	data.planet_technologies = planet_technologies.duplicate(true)
	data.research_jobs = research_jobs.duplicate(true)

func restore_snapshot(data: RunSaveData) -> void:
	if data == null:
		return
	reset()
	researched_techs = RunSaveData.restore_dict(data.researched_techs)
	planet_technologies = RunSaveData.restore_dict(data.planet_technologies)
	research_jobs = RunSaveData.restore_dict(data.research_jobs)
