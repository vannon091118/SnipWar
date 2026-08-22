class_name FactionDomain
extends RefCounted

## Manages planet ownership, homeworlds, factions, scan/discovery intel, and milestones.

signal faction_changed(planet_id: StringName, old_faction: StringName, new_faction: StringName)
signal planet_discovered(faction: StringName, planet_id: StringName)
signal planet_scanned(faction: StringName, planet_id: StringName, resource_id: StringName, size_id: StringName, build_slots: int)
signal milestone_reached(faction: StringName, milestone_id: StringName)

var ownership: Dictionary = {}
var starting_workers: Dictionary = {}
var homeworlds: Dictionary = {}
var known_planets: Dictionary = {}
var scanned_planets: Dictionary = {}
var scan_intel: Dictionary = {}
var milestones: Dictionary = {}

func reset(catalog: PlanetCatalog) -> void:
	_reset_state()

	if catalog != null:
		for definition in catalog.planets:
			if definition == null:
				continue
			ownership[definition.planet_id] = definition.faction
			if definition.planet_role == &"homeworld" and (definition.faction == GameState.FACTION_PLAYER or definition.faction == GameState.FACTION_CPU):
				homeworlds[definition.faction] = definition.planet_id
	for planet_id in ownership:
		remember_planet(ownership[planet_id] as StringName, planet_id as StringName)

func reset_infinite() -> void:
	_reset_state()

func _reset_state() -> void:
	ownership.clear()
	starting_workers.clear()
	homeworlds.clear()
	known_planets.clear()
	scanned_planets.clear()
	scan_intel.clear()
	milestones.clear()

func remember_planet(faction: StringName, planet_id: StringName) -> void:
	if String(faction).is_empty() or faction == GameState.FACTION_NEUTRAL or String(planet_id).is_empty():
		return
	# Keep the legacy dictionary shape so compatibility callers can remove a
	# frontier entry directly while the domain split remains the SSOT.
	var known_list: Dictionary = known_planets.get(faction, {}) as Dictionary
	known_list[planet_id] = true
	known_planets[faction] = known_list

func register_homeworld(faction: StringName, planet_id: StringName) -> void:
	if (faction != GameState.FACTION_PLAYER and faction != GameState.FACTION_CPU) or String(planet_id).is_empty():
		return
	ownership[planet_id] = faction
	homeworlds[faction] = planet_id
	remember_planet(faction, planet_id)

func set_faction(planet_id: StringName, faction: StringName) -> void:
	if String(planet_id).is_empty():
		return
	var old_faction: StringName = faction_of(planet_id)
	if old_faction == faction:
		return
	ownership[planet_id] = faction
	remember_planet(faction, planet_id)
	faction_changed.emit(planet_id, old_faction, faction)

# Adds a planet to the ownership registry at runtime (callers: Planet._enter_tree).
# Idempotent — re-registering keeps the existing faction so reset_from_catalog wins
# later without surprise flips when the catalog was already seeded.
func register_planet(planet_id: StringName, initial_faction: StringName) -> void:
	if String(planet_id).is_empty():
		return
	if not ownership.has(planet_id):
		ownership[planet_id] = initial_faction
		remember_planet(initial_faction, planet_id)

# Seeds the size-profile starting worker count for a planet post-catalog.
# Used by SeededLayout AFTER the layout profiles are assigned.
func seed_starting_workers(planet_id: StringName, profile: PlanetSizeProfile) -> void:
	if String(planet_id).is_empty() or starting_workers.has(planet_id):
		return
	starting_workers[planet_id] = profile.starting_workers if profile != null else 0

func add_starting_workers(planet_id: StringName, amount: int) -> void:
	if String(planet_id).is_empty() or amount <= 0:
		return
	starting_workers[planet_id] = int(starting_workers.get(planet_id, 0)) + amount

func faction_of(planet_id: StringName) -> StringName:
	return ownership.get(planet_id, GameState.FACTION_NEUTRAL) as StringName

func is_owned_by(planet_id: StringName, faction: StringName) -> bool:
	return faction_of(planet_id) == faction

func homeworld_for(faction: StringName) -> StringName:
	return homeworlds.get(faction, &"") as StringName

func get_ownership_count(faction: StringName) -> int:
	var count := 0
	for p_id in ownership:
		if ownership[p_id] == faction:
			count += 1
	return count

func all_owned_planets(faction: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for p_id in ownership:
		if ownership[p_id] == faction:
			result.append(p_id as StringName)
	return result

func discover_planet(faction: StringName, planet_id: StringName) -> bool:
	if String(faction).is_empty() or String(planet_id).is_empty():
		return false
	var known_list: Dictionary = known_planets.get(faction, {}) as Dictionary
	if known_list.has(planet_id):
		return false
	known_list[planet_id] = true
	known_planets[faction] = known_list
	planet_discovered.emit(faction, planet_id)
	return true

func scan_planet(faction: StringName, planet_id: StringName, resource_id: StringName, size_id: StringName, build_slots: int) -> bool:
	if String(faction).is_empty() or String(planet_id).is_empty():
		return false
	discover_planet(faction, planet_id)
	var scanned_list: Array[StringName] = []
	if scanned_planets.has(faction):
		scanned_list = scanned_planets[faction]
	var was_scanned := scanned_list.has(planet_id)
	if not was_scanned:
		scanned_list.append(planet_id)
		scanned_planets[faction] = scanned_list
	if not scan_intel.has(faction):
		scan_intel[faction] = {}
	var intel: Dictionary = scan_intel[faction]
	intel[planet_id] = {
		"resource_id": resource_id,
		"size_id": size_id,
		"build_slots": build_slots,
	}
	scan_intel[faction] = intel
	planet_scanned.emit(faction, planet_id, resource_id, size_id, build_slots)
	return not was_scanned

func is_known(planet_id: StringName, faction: StringName) -> bool:
	if is_owned_by(planet_id, faction):
		return true
	if not known_planets.has(faction):
		return false
	var list: Dictionary = known_planets[faction] as Dictionary
	return list.has(planet_id)

func has_scanned_planet(faction: StringName, planet_id: StringName = &"") -> bool:
	if not scanned_planets.has(faction):
		return false
	var list: Array = scanned_planets[faction]
	if String(planet_id).is_empty():
		return not list.is_empty()
	return list.has(planet_id)

func scan_info_for(faction: StringName, planet_id: StringName) -> Dictionary:
	if not scan_intel.has(faction):
		return {}
	var intel: Dictionary = scan_intel[faction]
	return intel.get(planet_id, {}).duplicate()

func known_planets_of(faction: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for p_id in ownership:
		if is_known(p_id as StringName, faction):
			result.append(p_id as StringName)
	return result

func record_milestone(faction: StringName, milestone_id: StringName) -> bool:
	if String(faction).is_empty() or String(milestone_id).is_empty():
		return false
	if not milestones.has(faction):
		milestones[faction] = {}
	var faction_milestones: Dictionary = milestones[faction]
	if faction_milestones.has(milestone_id):
		return false
	faction_milestones[milestone_id] = Time.get_unix_time_from_system()
	milestones[faction] = faction_milestones
	milestone_reached.emit(faction, milestone_id)
	return true

# Public alias used by island callers (conflict_manager, constraint_colony_milestone).
# `mark_milestone` is the only public entry point; `record_milestone` above is
# the domain implementation it delegates to.
func mark_milestone(faction: StringName, milestone_id: StringName) -> bool:
	return record_milestone(faction, milestone_id)

func has_milestone(faction: StringName, milestone_id: StringName) -> bool:
	if not milestones.has(faction):
		return false
	var faction_milestones: Dictionary = milestones[faction]
	return faction_milestones.has(milestone_id)

func get_milestones(faction: StringName) -> Dictionary:
	if not milestones.has(faction):
		return {}
	return (milestones[faction] as Dictionary).duplicate()
