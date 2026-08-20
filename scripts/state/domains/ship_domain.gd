class_name ShipDomain
extends RefCounted

## Manages ship part inventory, modular ship assembly, disassembly, fleet creation, and build jobs.

signal ship_part_purchased(planet_id: StringName, part_id: StringName)
signal ship_assembled(planet_id: StringName, ship_id: StringName)
signal ship_disassembled(planet_id: StringName, ship_id: StringName)
signal ship_launched(planet_id: StringName, ship_id: StringName, role: StringName)
@warning_ignore("unused_signal")
signal ship_lost(planet_id: StringName, ship_id: StringName)
signal ship_build_started(planet_id: StringName, ship_id: StringName, remaining: float)

var ship_part_inventory: Dictionary = {}
var ship_assemblies: Dictionary = {}
var next_ship_index: int = 0
var ship_build_jobs: Dictionary = {}

func reset() -> void:
	ship_part_inventory.clear()
	ship_assemblies.clear()
	next_ship_index = 0
	ship_build_jobs.clear()

func get_ship_part_inventory(planet_id: StringName) -> Dictionary:
	if not ship_part_inventory.has(planet_id):
		return {}
	return (ship_part_inventory[planet_id] as Dictionary).duplicate()

func add_ship_part(planet_id: StringName, part_id: StringName, count: int = 1) -> void:
	if String(planet_id).is_empty() or String(part_id).is_empty() or count <= 0:
		return
	if not ship_part_inventory.has(planet_id):
		ship_part_inventory[planet_id] = {}
	var current: int = ship_part_inventory[planet_id].get(part_id, 0)
	ship_part_inventory[planet_id][part_id] = current + count

func spend_ship_part(planet_id: StringName, part_id: StringName, count: int = 1) -> bool:
	if count <= 0 or not ship_part_inventory.has(planet_id):
		return false
	var current: int = ship_part_inventory[planet_id].get(part_id, 0)
	if current < count:
		return false
	var remaining := current - count
	if remaining == 0:
		ship_part_inventory[planet_id].erase(part_id)
	else:
		ship_part_inventory[planet_id][part_id] = remaining
	return true

func can_buy_ship_part(faction: StringName, planet_id: StringName, part_id: StringName, catalog: ShipPartCatalog, economy: EconomyDomain, tech: TechDomain) -> bool:
	if catalog == null or String(planet_id).is_empty() or String(part_id).is_empty():
		return false
	var part: ShipPartDefinition = catalog.resolve(part_id)
	if part == null:
		return false
	if not String(part.required_tech_id).is_empty() and not tech.has_technology(faction, part.required_tech_id):
		return false
	return economy.can_spend_faction_resource(faction, part.cost_resource, part.cost_amount)

func buy_ship_part(faction: StringName, planet_id: StringName, part_id: StringName, catalog: ShipPartCatalog, economy: EconomyDomain, tech: TechDomain) -> bool:
	if not can_buy_ship_part(faction, planet_id, part_id, catalog, economy, tech):
		return false
	var part: ShipPartDefinition = catalog.resolve(part_id)
	if not economy.spend_faction_resource(faction, part.cost_resource, part.cost_amount):
		return false
	add_ship_part(planet_id, part_id, 1)
	ship_part_purchased.emit(planet_id, part_id)
	return true

func get_ship_assemblies(planet_id: StringName) -> Dictionary:
	if not ship_assemblies.has(planet_id):
		return {}
	return (ship_assemblies[planet_id] as Dictionary).duplicate(true)

func has_ship_assembly(planet_id: StringName, ship_id: StringName) -> bool:
	if not ship_assemblies.has(planet_id):
		return false
	return (ship_assemblies[planet_id] as Dictionary).has(ship_id)

func get_ship_assembly(planet_id: StringName, ship_id: StringName) -> Dictionary:
	if not ship_assemblies.has(planet_id):
		return {}
	return ((ship_assemblies[planet_id] as Dictionary).get(ship_id, {}) as Dictionary).duplicate(true)

func can_assemble_ship(planet_id: StringName, hull_id: StringName, scanner_id: StringName, module_ids: Array, weapon_id: StringName, drive_id: StringName, shield_id: StringName, catalog: ShipPartCatalog) -> bool:
	if catalog == null or String(planet_id).is_empty() or String(hull_id).is_empty():
		return false
	var hull: ShipPartDefinition = catalog.resolve(hull_id)
	if hull == null or hull.slot_type != ShipPartDefinition.SLOT_HULL:
		return false
	# The live builder always assembles a complete flyable loadout. Keep the
	# legacy façade order, but reject partial drive/shield assemblies here so a
	# build cannot consume parts into a non-flyable ship.
	if String(drive_id).is_empty() or String(shield_id).is_empty():
		return false
	var inv := get_ship_part_inventory(planet_id)
	var needed: Dictionary = {}
	_tally(needed, hull_id)
	if not String(drive_id).is_empty():
		var drive: ShipPartDefinition = catalog.resolve(drive_id)
		if drive == null or drive.slot_type != ShipPartDefinition.SLOT_DRIVE:
			return false
		_tally(needed, drive_id)
	if not String(weapon_id).is_empty():
		var weapon: ShipPartDefinition = catalog.resolve(weapon_id)
		if weapon == null or weapon.slot_type != ShipPartDefinition.SLOT_WEAPON:
			return false
		_tally(needed, weapon_id)
	if not String(shield_id).is_empty():
		var shield: ShipPartDefinition = catalog.resolve(shield_id)
		if shield == null or shield.slot_type != ShipPartDefinition.SLOT_SHIELD:
			return false
		_tally(needed, shield_id)
	if not String(scanner_id).is_empty():
		var scanner: ShipPartDefinition = catalog.resolve(scanner_id)
		if scanner == null or scanner.slot_type != ShipPartDefinition.SLOT_SCANNER:
			return false
		_tally(needed, scanner_id)
	if module_ids.size() > catalog.max_module_slots:
		return false
	for mod_val in module_ids:
		var mod_id: StringName = mod_val as StringName
		if String(mod_id).is_empty():
			continue
		var mod_part: ShipPartDefinition = catalog.resolve(mod_id)
		if mod_part == null or not ShipPartDefinition.is_utility_slot(mod_part.slot_type):
			return false
		_tally(needed, mod_id)
	for part_id_val in needed:
		var p_id: StringName = part_id_val as StringName
		if int(inv.get(p_id, 0)) < needed[p_id]:
			return false
	return true

func assemble_ship(
	planet_id: StringName,
	hull_id: StringName,
	scanner_id: StringName,
	module_ids: Array,
	weapon_id: StringName,
	drive_id: StringName,
	shield_id: StringName,
	catalog: ShipPartCatalog,
	custom_seed: int = -1,
	blueprint_id: StringName = &"",
	ship_role: StringName = &""
) -> StringName:
	if not can_assemble_ship(planet_id, hull_id, scanner_id, module_ids, weapon_id, drive_id, shield_id, catalog):
		return &""
	spend_ship_part(planet_id, hull_id, 1)
	if not String(drive_id).is_empty():
		spend_ship_part(planet_id, drive_id, 1)
	if not String(weapon_id).is_empty():
		spend_ship_part(planet_id, weapon_id, 1)
	if not String(shield_id).is_empty():
		spend_ship_part(planet_id, shield_id, 1)
	if not String(scanner_id).is_empty():
		spend_ship_part(planet_id, scanner_id, 1)
	for mod_val in module_ids:
		var mod_id: StringName = mod_val as StringName
		if not String(mod_id).is_empty():
			spend_ship_part(planet_id, mod_id, 1)

	next_ship_index += 1
	var ship_id := StringName("ship_%d" % next_ship_index)
	var instance_seed: int = custom_seed if custom_seed >= 0 else next_ship_index * 1337 + 42
	var blueprint: ShipBlueprint = catalog.resolve_blueprint(blueprint_id)
	if blueprint == null:
		return &""
	var variants: Dictionary = {
		&"hull": _select_variant_id(catalog, hull_id, blueprint, instance_seed, &"hull"),
		&"drive": _select_variant_id(catalog, drive_id, blueprint, instance_seed, &"drive"),
		&"weapon": _select_variant_id(catalog, weapon_id, blueprint, instance_seed, &"weapon"),
		&"shield": _select_variant_id(catalog, shield_id, blueprint, instance_seed, &"shield"),
		&"scanner": _select_variant_id(catalog, scanner_id, blueprint, instance_seed, &"scanner"),
		&"utility": [],
	}
	var utility_variants: Array = []
	for mod_index in range(module_ids.size()):
		var mod_id: StringName = module_ids[mod_index] as StringName
		utility_variants.append(_select_variant_id(catalog, mod_id, blueprint, instance_seed, StringName("mod_%d" % mod_index)))
	variants[&"utility"] = utility_variants

	var total_build_time: float = 0.0
	for part_id in [hull_id, drive_id, weapon_id, shield_id, scanner_id]:
		if not String(part_id).is_empty():
			var p: ShipPartDefinition = catalog.resolve(part_id)
			if p != null:
				total_build_time += p.build_time
	for mod_val in module_ids:
		var mod_id: StringName = mod_val as StringName
		if not String(mod_id).is_empty():
			var mp: ShipPartDefinition = catalog.resolve(mod_id)
			if mp != null:
				total_build_time += mp.build_time

	var assembly := {
		"id": ship_id,
		"hull": hull_id,
		"drive": drive_id,
		"weapon": weapon_id,
		"shield": shield_id,
		"scanner": scanner_id,
		"modules": module_ids.duplicate(),
		"role": ship_role if not String(ship_role).is_empty() else (&"military" if not String(weapon_id).is_empty() else &"colony"),
		"blueprint": blueprint.id,
		"instance_seed": instance_seed,
		"variants": variants,
	}

	if total_build_time <= 0.0:
		_complete_ship_assembly(planet_id, ship_id, assembly)
	else:
		if not ship_build_jobs.has(planet_id):
			ship_build_jobs[planet_id] = {}
		ship_build_jobs[planet_id][ship_id] = {
			"remaining": total_build_time,
			"assembly": assembly,
		}
		ship_build_started.emit(planet_id, ship_id, total_build_time)
	return ship_id

func disassemble_ship(planet_id: StringName, ship_id: StringName) -> bool:
	if not has_ship_assembly(planet_id, ship_id):
		return false
	var assembly: Dictionary = get_ship_assembly(planet_id, ship_id)
	ship_assemblies[planet_id].erase(ship_id)
	for slot in ["hull", "drive", "weapon", "shield", "scanner"]:
		var part_id: StringName = assembly.get(slot, &"") as StringName
		if not String(part_id).is_empty():
			add_ship_part(planet_id, part_id, 1)
	for mod_val in assembly.get("modules", []):
		var mod_id: StringName = mod_val as StringName
		if not String(mod_id).is_empty():
			add_ship_part(planet_id, mod_id, 1)
	ship_disassembled.emit(planet_id, ship_id)
	return true

func launch_ship(planet_id: StringName, ship_id: StringName) -> Dictionary:
	if not has_ship_assembly(planet_id, ship_id):
		return {}
	var assembly: Dictionary = get_ship_assembly(planet_id, ship_id)
	ship_assemblies[planet_id].erase(ship_id)
	var role: StringName = assembly.get("role", &"colony") as StringName
	ship_launched.emit(planet_id, ship_id, role)
	return assembly

func get_ship_build_jobs(planet_id: StringName) -> Dictionary:
	if not ship_build_jobs.has(planet_id):
		return {}
	var result: Dictionary = {}
	var jobs: Dictionary = ship_build_jobs[planet_id]
	for ship_id_value in jobs:
		var ship_id: StringName = ship_id_value as StringName
		result[ship_id] = (jobs[ship_id].get("assembly", {}) as Dictionary).duplicate(true)
	return result

func ship_build_in_progress(planet_id: StringName, ship_id: StringName = &"") -> bool:
	if String(ship_id).is_empty():
		return ship_build_jobs.has(planet_id) and not (ship_build_jobs[planet_id] as Dictionary).is_empty()
	if not ship_build_jobs.has(planet_id):
		return false
	return (ship_build_jobs[planet_id] as Dictionary).has(ship_id)

func ship_build_remaining(planet_id: StringName, ship_id: StringName) -> float:
	if not ship_build_jobs.has(planet_id) or not ship_build_jobs[planet_id].has(ship_id):
		return 0.0
	return float(ship_build_jobs[planet_id][ship_id].get("remaining", 0.0))

func advance_builds(delta: float) -> void:
	if delta <= 0.0 or ship_build_jobs.is_empty():
		return
	for planet_value in ship_build_jobs.keys():
		var planet_id: StringName = planet_value as StringName
		var jobs: Dictionary = ship_build_jobs[planet_id]
		for ship_value in jobs.keys():
			var ship_id: StringName = ship_value as StringName
			var job: Dictionary = jobs[ship_id]
			var remaining: float = float(job.get("remaining", 0.0)) - delta
			if remaining <= 0.0:
				var assembly: Dictionary = job.get("assembly", {}) as Dictionary
				jobs.erase(ship_id)
				_complete_ship_assembly(planet_id, ship_id, assembly)
			else:
				job["remaining"] = remaining

func create_fleet_from_planet(planet_id: StringName, ship_ids: Array, faction: StringName, catalog: ShipPartCatalog) -> FleetSnapshot:
	var fleet := FleetSnapshot.new()
	fleet.fleet_id = StringName("fleet_%s_%d" % [String(planet_id), next_ship_index])
	fleet.faction = faction
	fleet.source_planet_id = planet_id
	var gathered_ships: Array[Dictionary] = []
	for ship_id_value in ship_ids:
		var ship_id: StringName = ship_id_value as StringName
		if has_ship_assembly(planet_id, ship_id):
			gathered_ships.append(launch_ship(planet_id, ship_id))
	fleet.ships = gathered_ships
	fleet.calculate_stats(catalog)
	return fleet

## Non-destructive fleet snapshot for travel-time preview / dry-run. The source
## assemblies stay registered so the caller can dispatch the same ships later.
func preview_fleet_from_planet(planet_id: StringName, ship_ids: Array, faction: StringName, catalog: ShipPartCatalog) -> FleetSnapshot:
	var fleets_root: Dictionary = ship_assemblies.get(planet_id, {})
	var fleet := FleetSnapshot.new()
	fleet.fleet_id = StringName("preview_%s_%d" % [String(planet_id), next_ship_index])
	fleet.faction = faction
	fleet.source_planet_id = planet_id
	var previewed: Array[Dictionary] = []
	for ship_id_value in ship_ids:
		var ship_id: StringName = ship_id_value as StringName
		if not fleets_root.has(ship_id):
			continue
		var ship: Dictionary = (fleets_root[ship_id] as Dictionary).duplicate(true)
		ship["id"] = ship_id
		previewed.append(ship)
	fleet.ships = previewed
	fleet.calculate_stats(catalog)
	return fleet

# Re-stores a flying fleet (after repelled / friendly arrival) into the
# destination planet's assembly list.
func disband_fleet_to_planet(fleet: FleetSnapshot, planet_id: StringName) -> void:
	if fleet == null or String(planet_id).is_empty():
		return
	if not ship_assemblies.has(planet_id):
		ship_assemblies[planet_id] = {}
	var assemblies: Dictionary = ship_assemblies[planet_id]
	for ship_data in fleet.ships:
		var ship_id: StringName = ship_data.get("id", _next_ship_id()) as StringName
		var clean_data: Dictionary = ship_data.duplicate()
		clean_data.erase("id")
		assemblies[ship_id] = clean_data

func _next_ship_id() -> StringName:
	next_ship_index += 1
	return StringName("ship_%d" % next_ship_index)

# Reconciles the planet's ship_assemblies against the surviving defenders
# from a FleetBattleSimulator output. `surviving` carries the IDs that stayed
# alive; everything else in assemblies is dropped. Used by Planet after the
# battle deserialises back into the world.
func reconcile_defender_fleet(planet_id: StringName, defender_fleet: FleetSnapshot, surviving: Array) -> void:
	if String(planet_id).is_empty() or defender_fleet == null:
		return
	if not ship_assemblies.has(planet_id):
		return
	var assemblies: Dictionary = ship_assemblies[planet_id]
	var survivor_ids: Dictionary = {}
	for ship_id in surviving:
		survivor_ids[ship_id] = true
	var kept: Dictionary = {}
	for ship_id in assemblies.keys():
		if survivor_ids.has(ship_id):
			kept[ship_id] = assemblies[ship_id]
	if kept.is_empty():
		ship_assemblies.erase(planet_id)
	else:
		ship_assemblies[planet_id] = kept

func _complete_ship_assembly(planet_id: StringName, ship_id: StringName, assembly: Dictionary) -> void:
	if not ship_assemblies.has(planet_id):
		ship_assemblies[planet_id] = {}
	ship_assemblies[planet_id][ship_id] = assembly
	ship_assembled.emit(planet_id, ship_id)

func _select_variant_id(catalog: ShipPartCatalog, part_id: StringName, blueprint: ShipBlueprint, instance_seed: int, salt: StringName) -> StringName:
	if catalog == null or String(part_id).is_empty() or blueprint == null:
		return &""
	var part: ShipPartDefinition = catalog.resolve(part_id)
	if part == null:
		return &""
	var variant: ShipComponentVariant = catalog.select_variant(part, blueprint, instance_seed, -1, salt)
	return variant.id if variant != null else &""

func _tally(dict: Dictionary, key: StringName) -> void:
	dict[key] = dict.get(key, 0) + 1
