extends Node

const FACTION_PLAYER := &"a"
const FACTION_CPU := &"b"
const FACTION_NEUTRAL := &"neutral"
const DEFAULT_RESOURCE_POOL: ResourcePool = preload("res://resources/config/resource_pool_default.tres")

signal faction_changed(planet_id: StringName, old_faction: StringName, new_faction: StringName)

var _ownership: Dictionary = {}
var _starting_workers: Dictionary = {}
var _homeworlds: Dictionary = {}
var _planet_resources: Dictionary = {}

func reset_from_catalog(catalog: PlanetCatalog) -> void:
	_ownership.clear()
	_starting_workers.clear()
	_homeworlds.clear()
	_planet_resources.clear()
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
