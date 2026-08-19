extends Node

const FACTION_PLAYER := &"a"
const FACTION_CPU := &"b"
const FACTION_NEUTRAL := &"neutral"

signal faction_changed(planet_id: StringName, old_faction: StringName, new_faction: StringName)

var _ownership: Dictionary = {}
var _starting_workers: Dictionary = {}
var _homeworlds: Dictionary = {}

func reset_from_catalog(catalog: PlanetCatalog) -> void:
	_ownership.clear()
	_starting_workers.clear()
	_homeworlds.clear()
	if catalog == null:
		return
	for definition in catalog.planets:
		if definition == null:
			continue
		_ownership[definition.planet_id] = definition.faction
		if definition.planet_role == &"homeworld" and (definition.faction == FACTION_PLAYER or definition.faction == FACTION_CPU):
			_homeworlds[definition.faction] = definition.planet_id

func register_planet(planet_id: StringName, initial_faction: StringName) -> void:
	if String(planet_id).is_empty():
		return
	if not _ownership.has(planet_id):
		_ownership[planet_id] = initial_faction

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

func is_homeworld(planet_id: StringName) -> bool:
	return _homeworlds.values().has(planet_id)

func homeworld_for(faction: StringName) -> StringName:
	var value: Variant = _homeworlds.get(faction, &"")
	return value as StringName

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
