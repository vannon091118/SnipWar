class_name ShipDomain
extends RefCounted

class ResearchMission extends RefCounted:
	var mission_id: StringName = &""
	var target_planet_id: StringName = &""
	var task_type: StringName = &"scan"
	var duration: float = 1.0
	var remaining: float = 1.0
	var status: StringName = &"queued"

class PersistentShipRecord extends RefCounted:
	var ship_id: StringName = &""
	var faction: StringName = &""
	var mission_role: StringName = &""
	var current_planet_id: StringName = &""
	var status: StringName = &"idle"
	var fleet: FleetSnapshot
	var active_mission_id: StringName = &""

## Manages ship part inventory, typed modular ship assemblies, disassembly,
## fleet creation, and build jobs.

signal ship_part_purchased(planet_id: StringName, part_id: StringName)
signal ship_assembled(planet_id: StringName, ship_id: StringName)
signal ship_disassembled(planet_id: StringName, ship_id: StringName)
signal ship_launched(planet_id: StringName, ship_id: StringName, role: StringName)
@warning_ignore("unused_signal")
signal ship_lost(planet_id: StringName, ship_id: StringName)
signal ship_build_started(planet_id: StringName, ship_id: StringName, remaining: float)
signal research_ship_task_completed(mission_id: StringName, target_planet_id: StringName, task_type: StringName)
signal research_ship_idle(ship_id: StringName, planet_id: StringName)
signal persistent_ship_changed(ship_id: StringName, status: StringName)

var ship_part_inventory: Dictionary = {}
# Planet ID -> Dictionary[ship ID, ShipAssembly]. The outer dictionaries are
# indexes; the loadout itself is never represented as an untyped Dictionary.
var ship_assemblies: Dictionary = {}
var next_ship_index: int = 0
# Planet ID -> Dictionary[ship ID, {remaining: float, assembly: ShipAssembly}].
var ship_build_jobs: Dictionary = {}
var persistent_ships: Dictionary = {}
var research_missions: Array[ResearchMission] = []
var next_research_mission_index: int = 0

func reset() -> void:
	ship_part_inventory.clear()
	ship_assemblies.clear()
	next_ship_index = 0
	ship_build_jobs.clear()
	persistent_ships.clear()
	research_missions.clear()
	next_research_mission_index = 0

func ensure_starter_research_ship(faction: StringName, planet_id: StringName, catalog: ShipPartCatalog) -> StringName:
	for ship_id in persistent_ships:
		var existing: PersistentShipRecord = persistent_ships[ship_id] as PersistentShipRecord
		if existing != null and existing.faction == faction and existing.mission_role == &"research":
			return existing.ship_id
	var record := PersistentShipRecord.new()
	record.ship_id = StringName("research_ship_%s" % String(faction))
	record.faction = faction
	record.mission_role = &"research"
	record.current_planet_id = planet_id
	record.status = &"idle"
	var assembly := ShipAssembly.new()
	assembly.ship_id = record.ship_id
	assembly.role = &"research"
	assembly.hull_id = &"hull_t1"
	assembly.drive_id = &"drive_t1"
	assembly.scanner_id = &"scanner_t1"
	assembly.shield_id = &"shield_t1"
	record.fleet = FleetSnapshot.new()
	record.fleet.fleet_id = StringName("fleet_%s" % record.ship_id)
	record.fleet.faction = faction
	record.fleet.source_planet_id = planet_id
	record.fleet.mission_role = &"research"
	record.fleet.ships = [assembly]
	record.fleet.calculate_stats(catalog)
	persistent_ships[record.ship_id] = record
	persistent_ship_changed.emit(record.ship_id, record.status)
	return record.ship_id

func get_research_ship_records(faction: StringName = &"") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for ship_value in persistent_ships.values():
		var record: PersistentShipRecord = ship_value as PersistentShipRecord
		if record == null or record.mission_role != &"research" or (not String(faction).is_empty() and record.faction != faction):
			continue
		result.append({"ship_id": record.ship_id, "faction": record.faction, "current_planet_id": record.current_planet_id, "status": record.status, "active_mission_id": record.active_mission_id})
	return result

func get_persistent_ship(ship_id: StringName) -> PersistentShipRecord:
	return persistent_ships.get(ship_id) as PersistentShipRecord

func register_persistent_fleet(fleet: FleetSnapshot, status: StringName = &"in_transit") -> void:
	if fleet == null:
		return
	for assembly in fleet.ships:
		if assembly == null or String(assembly.ship_id).is_empty() or assembly.role == &"research":
			continue
		var record := PersistentShipRecord.new()
		record.ship_id = assembly.ship_id
		record.faction = fleet.faction
		record.mission_role = assembly.role
		record.current_planet_id = fleet.source_planet_id
		record.status = status
		record.fleet = fleet.copy()
		record.fleet.ships = [assembly.copy()]
		persistent_ships[record.ship_id] = record
		persistent_ship_changed.emit(record.ship_id, record.status)

func get_persistent_ship_records(faction: StringName = &"") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value in persistent_ships.values():
		var record: PersistentShipRecord = value as PersistentShipRecord
		if record == null or (not String(faction).is_empty() and record.faction != faction):
			continue
		result.append({"ship_id": record.ship_id, "faction": record.faction, "mission_role": record.mission_role, "current_planet_id": record.current_planet_id, "status": record.status})
	return result

func mark_persistent_ship_arrived(ship_id: StringName, planet_id: StringName, status: StringName = &"idle") -> bool:
	var record: PersistentShipRecord = persistent_ships.get(ship_id) as PersistentShipRecord
	if record == null:
		return false
	record.current_planet_id = planet_id
	record.status = status
	persistent_ship_changed.emit(ship_id, status)
	return true

func mark_persistent_ship_lost(ship_id: StringName) -> bool:
	if not persistent_ships.has(ship_id):
		return false
	persistent_ships.erase(ship_id)
	ship_lost.emit(&"", ship_id)
	return true

func queue_research_mission(faction: StringName, target_planet_id: StringName, task_type: StringName, duration: float = 2.0) -> StringName:
	if String(faction).is_empty() or String(target_planet_id).is_empty():
		return &""
	var ship: PersistentShipRecord = null
	for candidate_value in persistent_ships.values():
		var candidate: PersistentShipRecord = candidate_value as PersistentShipRecord
		if candidate != null and candidate.faction == faction and candidate.mission_role == &"research":
			ship = candidate
			break
	if ship == null:
		return &""
	next_research_mission_index += 1
	var mission := ResearchMission.new()
	mission.mission_id = StringName("research_mission_%d" % next_research_mission_index)
	mission.target_planet_id = target_planet_id
	mission.task_type = task_type
	mission.duration = maxf(duration, 0.01)
	mission.remaining = mission.duration
	mission.status = &"queued"
	research_missions.append(mission)
	if String(ship.active_mission_id).is_empty() and ship.status == &"idle" and ship.current_planet_id == target_planet_id:
		mission.status = &"active"
		ship.active_mission_id = mission.mission_id
	return mission.mission_id

func get_research_missions(faction: StringName = &"") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for mission in research_missions:
		if mission == null:
			continue
		var ship: PersistentShipRecord = _research_ship_for_mission(mission.mission_id)
		if ship != null and (String(faction).is_empty() or ship.faction == faction):
			result.append({"mission_id": mission.mission_id, "target_planet_id": mission.target_planet_id, "task_type": mission.task_type, "duration": mission.duration, "remaining": mission.remaining, "status": mission.status})
	return result

func cancel_research_mission(mission_id: StringName) -> bool:
	for index in research_missions.size():
		var mission: ResearchMission = research_missions[index]
		if mission == null or mission.mission_id != mission_id:
			continue
		var ship := _research_ship_for_mission(mission_id)
		if ship != null and ship.active_mission_id == mission_id:
			ship.active_mission_id = &""
		research_missions.remove_at(index)
		return true
	return false

func mark_research_ship_departed(ship_id: StringName) -> bool:
	var ship: PersistentShipRecord = persistent_ships.get(ship_id) as PersistentShipRecord
	if ship == null:
		return false
	ship.status = &"in_transit"
	persistent_ship_changed.emit(ship.ship_id, ship.status)
	return true

func mark_research_ship_arrived(ship_id: StringName, planet_id: StringName) -> bool:
	var ship: PersistentShipRecord = persistent_ships.get(ship_id) as PersistentShipRecord
	if ship == null:
		return false
	ship.current_planet_id = planet_id
	ship.status = &"idle"
	for mission in research_missions:
		if mission != null and mission.status == &"queued" and mission.target_planet_id == planet_id and String(ship.active_mission_id).is_empty():
			mission.status = &"active"
			ship.active_mission_id = mission.mission_id
			break
	persistent_ship_changed.emit(ship.ship_id, ship.status)
	if String(ship.active_mission_id).is_empty():
		research_ship_idle.emit(ship.ship_id, planet_id)
	return true

func advance_research_ship_tasks(delta: float) -> void:
	if delta <= 0.0:
		return
	for mission in research_missions:
		if mission == null or mission.status != &"active":
			continue
		mission.remaining -= delta
		if mission.remaining > 0.0:
			continue
		mission.remaining = 0.0
		mission.status = &"completed"
		var ship := _research_ship_for_mission(mission.mission_id)
		if ship != null:
			ship.active_mission_id = &""
			research_ship_task_completed.emit(mission.mission_id, mission.target_planet_id, mission.task_type)
			persistent_ship_changed.emit(ship.ship_id, ship.status)
		# Keep completed missions in the queue for UI history only briefly; remove
		# them now so the next queued task can become active deterministically.
		research_missions.erase(mission)
		if ship != null:
			for next_mission in research_missions:
				if next_mission.status == &"queued" and next_mission.target_planet_id == ship.current_planet_id:
					next_mission.status = &"active"
					ship.active_mission_id = next_mission.mission_id
					break
			if String(ship.active_mission_id).is_empty() and ship.status == &"idle":
				research_ship_idle.emit(ship.ship_id, ship.current_planet_id)

func _research_ship_for_mission(mission_id: StringName) -> PersistentShipRecord:
	for ship_value in persistent_ships.values():
		var ship: PersistentShipRecord = ship_value as PersistentShipRecord
		if ship != null and ship.active_mission_id == mission_id:
			return ship
	return null

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
	return economy.can_spend_cost(faction, part.cost_resource, part.cost_amount, part.credit_cost)

func buy_ship_part(faction: StringName, planet_id: StringName, part_id: StringName, catalog: ShipPartCatalog, economy: EconomyDomain, tech: TechDomain) -> bool:
	if not can_buy_ship_part(faction, planet_id, part_id, catalog, economy, tech):
		return false
	var part: ShipPartDefinition = catalog.resolve(part_id)
	if not economy.spend_cost(faction, part.cost_resource, part.cost_amount, part.credit_cost):
		return false
	add_ship_part(planet_id, part_id, 1)
	ship_part_purchased.emit(planet_id, part_id)
	return true

func get_ship_assemblies(planet_id: StringName) -> Dictionary:
	if not ship_assemblies.has(planet_id):
		return {}
	var result: Dictionary = {}
	var assemblies: Dictionary = ship_assemblies[planet_id] as Dictionary
	for ship_id_value in assemblies:
		var ship_id: StringName = ship_id_value as StringName
		var assembly: ShipAssembly = assemblies[ship_id] as ShipAssembly
		if assembly != null:
			result[ship_id] = assembly.copy()
	return result

func has_ship_assembly(planet_id: StringName, ship_id: StringName) -> bool:
	if not ship_assemblies.has(planet_id):
		return false
	return (ship_assemblies[planet_id] as Dictionary).has(ship_id)

func get_ship_assembly(planet_id: StringName, ship_id: StringName) -> ShipAssembly:
	if not ship_assemblies.has(planet_id):
		return null
	var assembly: ShipAssembly = (ship_assemblies[planet_id] as Dictionary).get(ship_id) as ShipAssembly
	return assembly.copy() if assembly != null else null

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

	var assembly := ShipAssembly.new()
	assembly.ship_id = ship_id
	assembly.hull_id = hull_id
	assembly.drive_id = drive_id
	assembly.weapon_id = weapon_id
	assembly.shield_id = shield_id
	assembly.scanner_id = scanner_id
	assembly.set_module_ids(module_ids)
	assembly.role = &"research" if ship_role == &"research" else ShipAssembly.derive_role_from_modules(assembly, catalog)
	assembly.blueprint_id = blueprint.id
	assembly.instance_seed = instance_seed
	assembly.hull_variant_id = _select_variant_id(catalog, hull_id, blueprint, instance_seed, &"hull")
	assembly.drive_variant_id = _select_variant_id(catalog, drive_id, blueprint, instance_seed, &"drive")
	assembly.weapon_variant_id = _select_variant_id(catalog, weapon_id, blueprint, instance_seed, &"weapon")
	assembly.shield_variant_id = _select_variant_id(catalog, shield_id, blueprint, instance_seed, &"shield")
	assembly.scanner_variant_id = _select_variant_id(catalog, scanner_id, blueprint, instance_seed, &"scanner")
	var utility_variant_ids: Array[StringName] = []
	for mod_index in range(assembly.module_ids.size()):
		utility_variant_ids.append(_select_variant_id(catalog, assembly.module_ids[mod_index], blueprint, instance_seed, StringName("mod_%d" % mod_index)))
	assembly.set_utility_variant_ids(utility_variant_ids)

	var total_build_time: float = 0.0
	for part_id in [hull_id, drive_id, weapon_id, shield_id, scanner_id]:
		if not String(part_id).is_empty():
			var p: ShipPartDefinition = catalog.resolve(part_id)
			if p != null:
				total_build_time += p.build_time
	for mod_id in assembly.module_ids:
		if not String(mod_id).is_empty():
			var mp: ShipPartDefinition = catalog.resolve(mod_id)
			if mp != null:
				total_build_time += mp.build_time

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
	var assembly: ShipAssembly = get_ship_assembly(planet_id, ship_id)
	ship_assemblies[planet_id].erase(ship_id)
	if assembly == null:
		return false
	for part_id in [assembly.hull_id, assembly.drive_id, assembly.weapon_id, assembly.shield_id, assembly.scanner_id]:
		if not String(part_id).is_empty():
			add_ship_part(planet_id, part_id, 1)
	for mod_id in assembly.module_ids:
		if not String(mod_id).is_empty():
			add_ship_part(planet_id, mod_id, 1)
	ship_disassembled.emit(planet_id, ship_id)
	return true

func launch_ship(planet_id: StringName, ship_id: StringName) -> ShipAssembly:
	if not has_ship_assembly(planet_id, ship_id):
		return null
	var assembly: ShipAssembly = get_ship_assembly(planet_id, ship_id)
	ship_assemblies[planet_id].erase(ship_id)
	if assembly == null:
		return null
	ship_launched.emit(planet_id, ship_id, assembly.role)
	return assembly

func get_ship_build_jobs(planet_id: StringName) -> Dictionary:
	if not ship_build_jobs.has(planet_id):
		return {}
	var result: Dictionary = {}
	var jobs: Dictionary = ship_build_jobs[planet_id]
	for ship_id_value in jobs:
		var ship_id: StringName = ship_id_value as StringName
		var job: Dictionary = jobs[ship_id] as Dictionary
		var assembly: ShipAssembly = job.get("assembly") as ShipAssembly
		if assembly != null:
			result[ship_id] = assembly.copy()
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
			var job: Dictionary = jobs[ship_id] as Dictionary
			var remaining: float = float(job.get("remaining", 0.0)) - delta
			if remaining <= 0.0:
				var assembly: ShipAssembly = job.get("assembly") as ShipAssembly
				jobs.erase(ship_id)
				_complete_ship_assembly(planet_id, ship_id, assembly)
			else:
				job["remaining"] = remaining

func create_fleet_from_planet(planet_id: StringName, ship_ids: Array, faction: StringName, catalog: ShipPartCatalog) -> FleetSnapshot:
	var fleet := FleetSnapshot.new()
	fleet.fleet_id = StringName("fleet_%s_%d" % [String(planet_id), next_ship_index])
	fleet.faction = faction
	fleet.source_planet_id = planet_id
	var gathered_ships: Array[ShipAssembly] = []
	for ship_id_value in ship_ids:
		var ship_id: StringName = ship_id_value as StringName
		if has_ship_assembly(planet_id, ship_id):
			var assembly: ShipAssembly = launch_ship(planet_id, ship_id)
			if assembly != null:
				gathered_ships.append(assembly)
	fleet.ships = gathered_ships
	fleet.calculate_stats(catalog)
	return fleet

## Non-destructive fleet snapshot for travel-time preview / dry-run. The source
## assemblies stay registered so the caller can dispatch the same ships later.
func preview_fleet_from_planet(planet_id: StringName, ship_ids: Array, faction: StringName, catalog: ShipPartCatalog) -> FleetSnapshot:
	var fleets_root: Dictionary = ship_assemblies.get(planet_id, {}) as Dictionary
	var fleet := FleetSnapshot.new()
	fleet.fleet_id = StringName("preview_%s_%d" % [String(planet_id), next_ship_index])
	fleet.faction = faction
	fleet.source_planet_id = planet_id
	var previewed: Array[ShipAssembly] = []
	for ship_id_value in ship_ids:
		var ship_id: StringName = ship_id_value as StringName
		if not fleets_root.has(ship_id):
			continue
		var assembly: ShipAssembly = fleets_root[ship_id] as ShipAssembly
		if assembly != null:
			previewed.append(assembly.copy())
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
		if ship_data == null:
			continue
		var restored: ShipAssembly = ship_data.copy()
		var ship_id: StringName = restored.ship_id
		if String(ship_id).is_empty():
			ship_id = _next_ship_id()
		restored.ship_id = ship_id
		assemblies[ship_id] = restored

func _next_ship_id() -> StringName:
	next_ship_index += 1
	return StringName("ship_%d" % next_ship_index)

# Reconciles the planet's ship_assemblies against the surviving defenders
# from a FleetBattleSimulator output. `surviving` carries typed assemblies
# whose ship_id identifies the entries that stayed alive.
func reconcile_defender_fleet(planet_id: StringName, defender_fleet: FleetSnapshot, surviving: Array[ShipAssembly]) -> void:
	if String(planet_id).is_empty() or defender_fleet == null:
		return
	if not ship_assemblies.has(planet_id):
		return
	var assemblies: Dictionary = ship_assemblies[planet_id]
	var survivor_ids: Dictionary = {}
	for survivor in surviving:
		if survivor != null and not String(survivor.ship_id).is_empty():
			survivor_ids[survivor.ship_id] = true
	var kept: Dictionary = {}
	for ship_id in assemblies.keys():
		if survivor_ids.has(ship_id):
			kept[ship_id] = assemblies[ship_id]
	if kept.is_empty():
		ship_assemblies.erase(planet_id)
	else:
		ship_assemblies[planet_id] = kept

func _complete_ship_assembly(planet_id: StringName, ship_id: StringName, assembly: ShipAssembly) -> void:
	if assembly == null:
		return
	if not ship_assemblies.has(planet_id):
		ship_assemblies[planet_id] = {}
	assembly.ship_id = ship_id
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
