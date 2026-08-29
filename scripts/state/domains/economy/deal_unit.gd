class_name EconomyDealUnit
extends RefCounted

## E2: Verhaltens-Einheit für Resource-Dealing aus EconomyDomain.
##
## Verantwortlich: deal_resources, deal_resources_for_planets, validate_resources
## und die zugehörigen Helfer (_shuffle, _build_resource_id_list,
## _least_used_resource, _homeworld_data_sort).
##
## State-Dictionarys und Signale bleiben auf der EconomyDomain-Fassade.
## Diese Einheit erhält die Fassade als `_owner` und nutzt dessen
## Methoden für State-Zugriff (set_planet_resource, resource_of, _is_valid_resource_id).

var _owner: EconomyDomain


func _init(owner: EconomyDomain) -> void:
	_owner = owner


## Deals resources for all planets in the catalog. Clears existing assignments.
## Homeworlds get distinct resource identities when the pool has ≥ 2 entries;
## remaining planets use least-used round-robin balancing.
func deal_resources(catalog: PlanetCatalog, pool: ResourcePool = null, seed_value: int = 0) -> void:
	_owner.planet_resources.clear()
	var effective_pool: ResourcePool = pool if pool != null else GameState.DEFAULT_RESOURCE_POOL
	if catalog == null or effective_pool == null or effective_pool.resources.is_empty():
		return

	# NOTE: build + shuffle with the SAME rng instance used for the later
	# homeworld/planet shuffles. The shared-rng consumption order is part of the
	# seed-deterministic deal contract; _build_resource_id_list() is only for the
	# lazy per-chunk path (deal_resources_for_planets), which has no shared rng.
	var resource_ids: Array[StringName] = []
	for resource in effective_pool.resources:
		if resource != null and not String(resource.id).is_empty():
			resource_ids.append(resource.id)
	if resource_ids.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_shuffle(resource_ids, rng)

	var homeworld_defs: Array[PlanetDefinition] = []
	var other_defs: Array[PlanetDefinition] = []
	for definition in catalog.planets:
		if definition == null:
			continue
		if definition.planet_role == &"homeworld":
			homeworld_defs.append(definition)
		else:
			other_defs.append(definition)
	_shuffle(homeworld_defs, rng)
	_shuffle(other_defs, rng)

	var all_defs: Array[PlanetDefinition] = []
	all_defs.append_array(homeworld_defs)
	all_defs.append_array(other_defs)
	if all_defs.is_empty():
		return

	# Reserve a balanced quota for the round-robin fallback. Signature hints may
	# intentionally consume a quota early; the greedy fallback restores balance
	# for the remaining planets.
	var pool_size: int = resource_ids.size()
	var base_count: int = int(float(all_defs.size()) / float(pool_size))
	var extra_count: int = all_defs.size() % pool_size
	var available_counts: Dictionary = {}
	for index in pool_size:
		var resource_id: StringName = resource_ids[index]
		available_counts[resource_id] = base_count + (1 if index < extra_count else 0)

	var used_homeworld_resources: Dictionary = {}
	for definition in all_defs:
		var chosen_resource: StringName = &""
		var is_homeworld: bool = definition.planet_role == &"homeworld"
		var signature: StringName = definition.signature_resource
		var signature_blocked: bool = is_homeworld and used_homeworld_resources.has(signature)
		if not String(signature).is_empty() and resource_ids.has(signature) and not signature_blocked and rng.randf() < definition.signature_probability:
			# A probability-one signature is a hard preference, even if its
			# nominal quota is already exhausted.
			chosen_resource = signature

		if String(chosen_resource).is_empty():
			var best_count := -1
			for resource_id in resource_ids:
				if is_homeworld and used_homeworld_resources.has(resource_id):
					continue
				var remaining: int = int(available_counts.get(resource_id, 0))
				if remaining > best_count:
					best_count = remaining
					chosen_resource = resource_id

		# If there are more homeworlds than resource identities, release the
		# distinct-homeworld constraint and continue with the best quota.
		if String(chosen_resource).is_empty():
			var best_count := -1
			for resource_id in resource_ids:
				var remaining: int = int(available_counts.get(resource_id, 0))
				if remaining > best_count:
					best_count = remaining
					chosen_resource = resource_id

		if String(chosen_resource).is_empty():
			chosen_resource = resource_ids[0]
		_owner.set_planet_resource(definition.planet_id, chosen_resource)
		available_counts[chosen_resource] = maxi(0, int(available_counts.get(chosen_resource, 0)) - 1)
		if is_homeworld:
			used_homeworld_resources[chosen_resource] = true


## Deals resources for a batch of new planets WITHOUT clearing existing
## assignments. Homeworlds in the origin chunk are assigned distinct resource
## identities whenever the pool has at least two entries; neutral slots then
## use least-used round-robin balancing.
func deal_resources_for_planets(planet_data: Array, pool: ResourcePool = null, seed_value: int = 0) -> void:
	var effective_pool: ResourcePool = pool if pool != null else GameState.DEFAULT_RESOURCE_POOL
	if effective_pool == null or effective_pool.resources.is_empty():
		return
	var resource_ids := _build_resource_id_list(effective_pool, seed_value)
	if resource_ids.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var counts: Dictionary = {}
	var homeworld_data: Array = []
	var neutral_data: Array = []
	for data in planet_data:
		if data == null:
			continue
		var p_id: StringName = data.planet_id
		if String(p_id).is_empty() or _owner.planet_resources.has(p_id):
			continue
		if data.planet_role == &"homeworld":
			homeworld_data.append(data)
		else:
			neutral_data.append(data)
	_homeworld_data_sort(homeworld_data)
	for data in homeworld_data:
		var home_id: StringName = data.planet_id
		var signature: StringName = data.signature_resource
		var chosen: StringName = &""
		if not String(signature).is_empty() and resource_ids.has(signature) and rng.randf() < float(data.signature_probability):
			var signature_used := false
			for other_home in homeworld_data:
				if other_home == data:
					continue
				if _owner.planet_resources.get(other_home.planet_id, &"") == signature:
					signature_used = true
					break
			if not signature_used or resource_ids.size() < 2:
				chosen = signature
		if String(chosen).is_empty():
			var best_count := 1 << 30
			for resource_id in resource_ids:
				var already_used := false
				if resource_ids.size() >= 2:
					for other_home in homeworld_data:
						if other_home == data:
							continue
						if _owner.planet_resources.get(other_home.planet_id, &"") == resource_id:
							already_used = true
							break
				if already_used:
					continue
				var remaining: int = int(counts.get(resource_id, 0))
				if remaining < best_count:
					best_count = remaining
					chosen = resource_id
		if String(chosen).is_empty():
				chosen = _least_used_resource(resource_ids, counts)
		_owner.planet_resources[home_id] = chosen
		counts[chosen] = int(counts.get(chosen, 0)) + 1
	for data in neutral_data:
		var p_id: StringName = data.planet_id
		var signature: StringName = data.signature_resource
		var chosen: StringName = &""
		if not String(signature).is_empty() and resource_ids.has(signature) and rng.randf() < float(data.signature_probability):
			chosen = signature
		if String(chosen).is_empty():
			chosen = _least_used_resource(resource_ids, counts)
		_owner.planet_resources[p_id] = chosen
		counts[chosen] = int(counts.get(chosen, 0)) + 1


func validate_resources(pool: ResourcePool = null, homeworlds: Dictionary = {}) -> PackedStringArray:
	var errors := PackedStringArray()
	var effective_pool: ResourcePool = pool if pool != null else GameState.DEFAULT_RESOURCE_POOL
	if _owner.planet_resources.is_empty():
		errors.append("resources have not been dealt")
		return errors
	if effective_pool == null or effective_pool.resources.is_empty():
		errors.append("resource pool is empty")
		return errors

	var counts: Dictionary = {}
	for planet_id in _owner.planet_resources:
		var resource_id: StringName = _owner.resource_of(planet_id as StringName)
		if String(resource_id).is_empty():
			errors.append("planet %s has no resource" % planet_id)
			continue
		counts[resource_id] = int(counts.get(resource_id, 0)) + 1

	var homeworld_resources: Dictionary = {}
	for planet_id_value in homeworlds.values():
		var planet_id: StringName = planet_id_value as StringName
		var resource_id: StringName = _owner.resource_of(planet_id)
		if String(resource_id).is_empty():
			continue
		if homeworld_resources.has(resource_id):
			errors.append("homeworlds share resource %s" % resource_id)
		homeworld_resources[resource_id] = true

	if counts.size() < effective_pool.resources.size():
		errors.append("not every pool resource is represented")
	if counts.size() > 1:
		var min_count := 1 << 30
		var max_count := 0
		for count in counts.values():
			min_count = mini(min_count, int(count))
			max_count = maxi(max_count, int(count))
		if max_count - min_count > 1:
			errors.append("resource distribution is unbalanced")
	return errors


func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = value


func _homeworld_data_sort(values: Array) -> void:
	values.sort_custom(func(first, second):
		return String(first.planet_id) < String(second.planet_id)
	)


## Builds a shuffled list of resource IDs from the pool.
func _build_resource_id_list(pool: ResourcePool, seed_value: int) -> Array[StringName]:
	var resource_ids: Array[StringName] = []
	for resource in pool.resources:
		if resource != null and not String(resource.id).is_empty():
			resource_ids.append(resource.id)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in range(resource_ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: StringName = resource_ids[i]
		resource_ids[i] = resource_ids[j]
		resource_ids[j] = tmp
	return resource_ids


func _least_used_resource(resource_ids: Array[StringName], counts: Dictionary) -> StringName:
	var best: StringName = resource_ids[0] if not resource_ids.is_empty() else &""
	var best_count: int = int(counts.get(best, 0))
	for rid in resource_ids:
		var c: int = int(counts.get(rid, 0))
		if c < best_count:
			best_count = c
			best = rid
	return best
