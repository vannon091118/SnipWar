extends Node

## Centralized GameState Facade for SnipWar.
## Composes modular domain managers (FactionDomain, EconomyDomain, TechDomain, ShipDomain)
## while maintaining full backward compatibility for public API, signals, and preflight tests.

const FACTION_PLAYER := &"a"
const FACTION_CPU := &"b"
const FACTION_NEUTRAL := &"neutral"
## Uninhabited planets: no garrison, no workers, no buildings — colonizable
## via MISSION_COLONY. Kept separate from neutral so the player can tell an
## empty rock from a settled foreign world (Sprint 6, S5).
const FACTION_UNINHABITED := &"uninhabited"

const MISSION_MILITARY := &"military"
const MISSION_CARGO := &"cargo"
const MISSION_COLONY := &"colony"
const MISSION_COLLECT := &"collect"
const TECH_WORKER_AUTOMATION := &"worker_automation"

const RES_ENERGY: StringName = &"energy"
const RES_BIOMASS: StringName = &"biomass"
const RES_RARE: StringName = &"rare"
const RES_MATERIAL: StringName = &"material"
const RES_VOLATILE: StringName = &"volatile"

const ALL_RESOURCES: Array[StringName] = [
	RES_ENERGY,
	RES_BIOMASS,
	RES_RARE,
	RES_MATERIAL,
	RES_VOLATILE,
]

static func is_valid_resource(resource_id: StringName) -> bool:
	return resource_id == RES_ENERGY or resource_id == RES_BIOMASS or resource_id == RES_RARE or resource_id == RES_MATERIAL or resource_id == RES_VOLATILE

const DEFAULT_RESOURCE_POOL: ResourcePool = preload("res://resources/config/resource_pool_default.tres")
const DEFAULT_UPGRADE_CATALOG: PlanetUpgradeCatalog = preload("res://resources/config/planet_upgrade_catalog_default.tres")
const DEFAULT_TECHNOLOGY_CATALOG: TechnologyCatalog = preload("res://resources/config/technology_catalog_default.tres")
const DEFAULT_SHIP_PART_CATALOG: ShipPartCatalog = preload("res://resources/config/ship_part_catalog_default.tres")
const DEFAULT_BUILDING_CATALOG: BuildingCatalog = preload("res://resources/config/building_catalog_default.tres")

signal faction_changed(planet_id: StringName, old_faction: StringName, new_faction: StringName)
signal catalog_reset(catalog: PlanetCatalog)
signal faction_resources_changed(faction: StringName, resource_id: StringName, new_amount: int)
signal credits_changed(faction: StringName, new_amount: int)
signal workers_reserved(planet_id: StringName, job_id: StringName, amount: int)
signal workers_released(planet_id: StringName, job_id: StringName, amount: int)
signal planet_upgraded(planet_id: StringName, upgrade_id: StringName)
signal resource_generated(planet_id: StringName, resource_id: StringName, amount: int)
signal planet_discovered(faction: StringName, planet_id: StringName)
signal planet_scanned(faction: StringName, planet_id: StringName, resource_id: StringName, size_id: StringName, build_slots: int)
signal technology_researched(faction: StringName, technology_id: StringName)
signal planet_technology_researched(planet_id: StringName, technology_id: StringName)
signal resources_collected(faction: StringName, planet_id: StringName, resource_id: StringName, amount: int)
signal gathering_started(faction: StringName, planet_id: StringName, workers: int)
signal gathering_withdrawn(faction: StringName, planet_id: StringName, workers: int)
signal worker_factory_built(planet_id: StringName)
signal ship_part_purchased(planet_id: StringName, part_id: StringName)
signal ship_assembled(planet_id: StringName, ship_id: StringName)
signal ship_disassembled(planet_id: StringName, ship_id: StringName)
signal ship_launched(planet_id: StringName, ship_id: StringName, role: StringName)
signal ship_lost(planet_id: StringName, ship_id: StringName)
signal milestone_reached(faction: StringName, milestone_id: StringName)
signal mid_game_started(faction: StringName)
signal refinery_converted(planet_id: StringName, faction: StringName, consumed: Dictionary, produced: Dictionary)
signal research_started(faction: StringName, technology_id: StringName, remaining: float)
signal ship_build_started(planet_id: StringName, ship_id: StringName, remaining: float)
signal research_ship_task_completed(mission_id: StringName, target_planet_id: StringName, task_type: StringName)
signal research_ship_idle(ship_id: StringName, planet_id: StringName)
signal persistent_ship_changed(ship_id: StringName, status: StringName)
signal battle_context_changed(context: BattleContext)
signal transit_changed(record: TransitRecord)
signal run_started(run_id: StringName, layout_seed: int)
signal planet_building_placed(planet_id: StringName, q: int, r: int, building_id: StringName)
signal planet_building_destroyed(planet_id: StringName, q: int, r: int)
signal resource_transferred(from_planet: StringName, to_planet: StringName, resource_id: StringName, amount: int)
signal worker_transport_started(transport_id: StringName, faction: StringName, amount: int)
signal worker_transport_phase_changed(transport_id: StringName, phase: StringName)
signal local_resources_changed(planet_id: StringName, resource_id: StringName, new_amount: int)

var faction_domain := FactionDomain.new()
var economy_domain := EconomyDomain.new()
var tech_domain := TechDomain.new()
var ship_domain := ShipDomain.new()

# Compatibility views retained while the state implementation is split into
# domains. Older UI/preflight callers inspect these dictionaries through Node.get().
@warning_ignore("unused_private_class_variable")
var _ownership: Dictionary:
	get:
		return faction_domain.ownership
@warning_ignore("unused_private_class_variable")
var _starting_workers: Dictionary:
	get:
		return faction_domain.starting_workers
@warning_ignore("unused_private_class_variable")
var _homeworlds: Dictionary:
	get:
		return faction_domain.homeworlds
@warning_ignore("unused_private_class_variable")
var _known_planets: Dictionary:
	get:
		return faction_domain.known_planets
@warning_ignore("unused_private_class_variable")
var _faction_vaults: Dictionary:
	get:
		return economy_domain.faction_vaults
@warning_ignore("unused_private_class_variable")
var _planet_resources: Dictionary:
	get:
		return economy_domain.planet_resources
@warning_ignore("unused_private_class_variable")
var _planet_upgrades: Dictionary:
	get:
		return economy_domain.planet_upgrades
@warning_ignore("unused_private_class_variable")
var _gathering_workers: Dictionary:
	get:
		return economy_domain.gathering_workers
@warning_ignore("unused_private_class_variable")
var _ship_part_inventory: Dictionary:
	get:
		return ship_domain.ship_part_inventory

var _jobs_auto_advance: bool = true
var _player_name: String = ""
var _stickman_profile: String = "FORSCHER"
var _run_active: bool = false
var _run_id: StringName = &""
var _run_scenario_id: StringName = &""
var _run_layout_seed: int = 0
var _run_infinite_world: bool = false
var _pending_battle: BattleContext
var _transit_records: Dictionary = {}
var _next_transit_index: int = 0
var _reconnect_requested: bool = false
# Typed context bridge between scenes (world session + save/load handover).
var _session: RunSession
# Pending chunk/timer payload handed to the world scene after a save restore.
var _pending_chunk_data: ChunkSaveData
var _pending_timers: Dictionary = {}

func _init() -> void:
	_connect_domain_signals()
	economy_domain.reset_vaults()
	_session = RunSession.new()

func _dispatch_event(type: StringName, data: Dictionary) -> void:
	var root: Node = Engine.get_main_loop().root if Engine.get_main_loop() else null
	if root != null:
		var bus: Node = root.get_node_or_null("EventBus")
		if bus != null and bus.has_method("emit_event"):
			bus.emit_event(type, data)

func _connect_domain_signals() -> void:
	# Connect domain signals to named callbacks to avoid anonymous lambda allocations.
	faction_domain.faction_changed.connect(_on_domain_faction_changed)
	faction_domain.planet_discovered.connect(_on_domain_planet_discovered)
	faction_domain.planet_scanned.connect(_on_domain_planet_scanned)
	faction_domain.milestone_reached.connect(_on_domain_milestone_reached)

	economy_domain.faction_resources_changed.connect(_on_domain_faction_resources_changed)
	economy_domain.credits_changed.connect(_on_domain_credits_changed)
	economy_domain.workers_reserved.connect(_on_domain_workers_reserved)
	economy_domain.workers_released.connect(_on_domain_workers_released)
	economy_domain.planet_upgraded.connect(_on_domain_planet_upgraded)
	economy_domain.resource_generated.connect(_on_domain_resource_generated)
	economy_domain.resources_collected.connect(_on_domain_resources_collected)
	economy_domain.gathering_started.connect(_on_domain_gathering_started)
	economy_domain.gathering_withdrawn.connect(_on_domain_gathering_withdrawn)
	economy_domain.worker_factory_built.connect(_on_domain_worker_factory_built)
	economy_domain.refinery_converted.connect(_on_domain_refinery_converted)
	economy_domain.local_resources_changed.connect(_on_domain_local_resources_changed)
	economy_domain.resource_transferred.connect(_on_domain_resource_transferred)
	economy_domain.building_placed.connect(_on_domain_building_placed)
	economy_domain.building_removed.connect(_on_domain_building_removed)
	economy_domain.worker_transport_started.connect(_on_domain_worker_transport_started)
	economy_domain.worker_transport_phase_changed.connect(_on_domain_worker_transport_phase_changed)

	tech_domain.technology_researched.connect(_on_domain_technology_researched)
	tech_domain.planet_technology_researched.connect(_on_domain_planet_technology_researched)
	tech_domain.research_started.connect(_on_domain_research_started)

	ship_domain.ship_part_purchased.connect(_on_domain_ship_part_purchased)
	ship_domain.ship_assembled.connect(_on_ship_assembled_domain)
	ship_domain.ship_disassembled.connect(_on_domain_ship_disassembled)
	ship_domain.ship_launched.connect(_on_domain_ship_launched)
	ship_domain.ship_lost.connect(_on_domain_ship_lost)
	ship_domain.ship_build_started.connect(_on_domain_ship_build_started)
	ship_domain.research_ship_task_completed.connect(_on_domain_research_ship_task_completed)
	ship_domain.research_ship_idle.connect(_on_domain_research_ship_idle)
	ship_domain.persistent_ship_changed.connect(_on_domain_persistent_ship_changed)

func _on_domain_planet_discovered(faction: StringName, planet_id: StringName) -> void:
	planet_discovered.emit(faction, planet_id)
	_dispatch_event(&"planet_discovered", {"faction": faction, "planet_id": planet_id})

func _on_domain_planet_scanned(faction: StringName, planet_id: StringName, resource_id: StringName, size_id: StringName, build_slots: int) -> void:
	planet_scanned.emit(faction, planet_id, resource_id, size_id, build_slots)
	_dispatch_event(&"planet_scanned", {"faction": faction, "planet_id": planet_id, "resource_id": resource_id, "size_id": size_id, "build_slots": build_slots})

func _on_domain_faction_resources_changed(faction: StringName, resource_id: StringName, new_amount: int) -> void:
	faction_resources_changed.emit(faction, resource_id, new_amount)
	_dispatch_event(&"faction_resources_changed", {"faction": faction, "resource_id": resource_id, "new_amount": new_amount})

func _on_domain_credits_changed(faction: StringName, new_amount: int) -> void:
	credits_changed.emit(faction, new_amount)
	_dispatch_event(&"credits_changed", {"faction": faction, "new_amount": new_amount})

func _on_domain_workers_reserved(planet_id: StringName, job_id: StringName, amount: int) -> void:
	workers_reserved.emit(planet_id, job_id, amount)
	_dispatch_event(&"workers_reserved", {"planet_id": planet_id, "job_id": job_id, "amount": amount})

func _on_domain_workers_released(planet_id: StringName, job_id: StringName, amount: int) -> void:
	workers_released.emit(planet_id, job_id, amount)
	_dispatch_event(&"workers_released", {"planet_id": planet_id, "job_id": job_id, "amount": amount})

func _on_domain_planet_upgraded(planet_id: StringName, upgrade_id: StringName) -> void:
	planet_upgraded.emit(planet_id, upgrade_id)
	_dispatch_event(&"planet_upgraded", {"planet_id": planet_id, "upgrade_id": upgrade_id})

func _on_domain_resource_generated(planet_id: StringName, resource_id: StringName, amount: int) -> void:
	resource_generated.emit(planet_id, resource_id, amount)
	_dispatch_event(&"resource_generated", {"planet_id": planet_id, "resource_id": resource_id, "amount": amount})

func _on_domain_resources_collected(faction: StringName, planet_id: StringName, resource_id: StringName, amount: int) -> void:
	resources_collected.emit(faction, planet_id, resource_id, amount)
	_dispatch_event(&"resources_collected", {"faction": faction, "planet_id": planet_id, "resource_id": resource_id, "amount": amount})

func _on_domain_gathering_started(faction: StringName, planet_id: StringName, workers: int) -> void:
	gathering_started.emit(faction, planet_id, workers)
	_dispatch_event(&"gathering_started", {"faction": faction, "planet_id": planet_id, "workers": workers})

func _on_domain_gathering_withdrawn(faction: StringName, planet_id: StringName, workers: int) -> void:
	gathering_withdrawn.emit(faction, planet_id, workers)
	_dispatch_event(&"gathering_withdrawn", {"faction": faction, "planet_id": planet_id, "workers": workers})

func _on_domain_worker_factory_built(planet_id: StringName) -> void:
	worker_factory_built.emit(planet_id)
	_dispatch_event(&"worker_factory_built", {"planet_id": planet_id})

func _on_domain_refinery_converted(planet_id: StringName, faction: StringName, consumed: Dictionary, produced: Dictionary) -> void:
	refinery_converted.emit(planet_id, faction, consumed, produced)
	_dispatch_event(&"refinery_converted", {"planet_id": planet_id, "faction": faction, "consumed": consumed, "produced": produced})

func _on_domain_local_resources_changed(planet_id: StringName, resource_id: StringName, new_amount: int) -> void:
	local_resources_changed.emit(planet_id, resource_id, new_amount)
	_dispatch_event(&"local_resources_changed", {"planet_id": planet_id, "resource_id": resource_id, "new_amount": new_amount})

func _on_domain_resource_transferred(from_planet: StringName, to_planet: StringName, resource_id: StringName, amount: int) -> void:
	resource_transferred.emit(from_planet, to_planet, resource_id, amount)
	_dispatch_event(&"resource_transferred", {"from_planet": from_planet, "to_planet": to_planet, "resource_id": resource_id, "amount": amount})

func _on_domain_building_placed(planet_id: StringName, building_id: StringName, q: int, r: int) -> void:
	planet_building_placed.emit(planet_id, q, r, building_id)
	_dispatch_event(&"planet_building_placed", {"planet_id": planet_id, "building_id": building_id, "q": q, "r": r})

func _on_domain_building_removed(planet_id: StringName, q: int, r: int) -> void:
	planet_building_destroyed.emit(planet_id, q, r)
	_dispatch_event(&"planet_building_destroyed", {"planet_id": planet_id, "q": q, "r": r})

func _on_domain_worker_transport_started(transport_id: StringName, faction: StringName, amount: int) -> void:
	worker_transport_started.emit(transport_id, faction, amount)
	_dispatch_event(&"worker_transport_started", {"transport_id": transport_id, "faction": faction, "amount": amount})

func _on_domain_worker_transport_phase_changed(transport_id: StringName, phase: StringName) -> void:
	worker_transport_phase_changed.emit(transport_id, phase)
	_dispatch_event(&"worker_transport_phase_changed", {"transport_id": transport_id, "phase": phase})

func _on_domain_technology_researched(faction: StringName, technology_id: StringName) -> void:
	technology_researched.emit(faction, technology_id)
	_dispatch_event(&"technology_researched", {"faction": faction, "technology_id": technology_id})

func _on_domain_planet_technology_researched(planet_id: StringName, technology_id: StringName) -> void:
	planet_technology_researched.emit(planet_id, technology_id)
	_dispatch_event(&"planet_technology_researched", {"planet_id": planet_id, "technology_id": technology_id})

func _on_domain_research_started(faction: StringName, technology_id: StringName, remaining: float) -> void:
	research_started.emit(faction, technology_id, remaining)
	_dispatch_event(&"research_started", {"faction": faction, "technology_id": technology_id, "remaining": remaining})

func _on_domain_ship_part_purchased(planet_id: StringName, part_id: StringName) -> void:
	ship_part_purchased.emit(planet_id, part_id)
	_dispatch_event(&"ship_part_purchased", {"planet_id": planet_id, "part_id": part_id})

func _on_domain_ship_disassembled(planet_id: StringName, ship_id: StringName) -> void:
	ship_disassembled.emit(planet_id, ship_id)
	_dispatch_event(&"ship_disassembled", {"planet_id": planet_id, "ship_id": ship_id})

func _on_domain_ship_launched(planet_id: StringName, ship_id: StringName, role: StringName) -> void:
	ship_launched.emit(planet_id, ship_id, role)
	_dispatch_event(&"ship_launched", {"planet_id": planet_id, "ship_id": ship_id, "role": role})

func _on_domain_ship_lost(planet_id: StringName, ship_id: StringName) -> void:
	ship_lost.emit(planet_id, ship_id)
	_dispatch_event(&"ship_lost", {"planet_id": planet_id, "ship_id": ship_id})

func _on_domain_ship_build_started(planet_id: StringName, ship_id: StringName, remaining: float) -> void:
	ship_build_started.emit(planet_id, ship_id, remaining)
	_dispatch_event(&"ship_build_started", {"planet_id": planet_id, "ship_id": ship_id, "remaining": remaining})

func _on_domain_research_ship_task_completed(mission_id: StringName, target_planet_id: StringName, task_type: StringName) -> void:
	research_ship_task_completed.emit(mission_id, target_planet_id, task_type)
	_dispatch_event(&"research_ship_task_completed", {"mission_id": mission_id, "target_planet_id": target_planet_id, "task_type": task_type})

func _on_domain_research_ship_idle(ship_id: StringName, planet_id: StringName) -> void:
	research_ship_idle.emit(ship_id, planet_id)
	_dispatch_event(&"research_ship_idle", {"ship_id": ship_id, "planet_id": planet_id})

func _on_domain_persistent_ship_changed(ship_id: StringName, status: StringName) -> void:
	persistent_ship_changed.emit(ship_id, status)
	_dispatch_event(&"persistent_ship_changed", {"ship_id": ship_id, "status": status})

func _on_ship_assembled_domain(planet_id: StringName, ship_id: StringName) -> void:
	economy_domain.release_workers(planet_id, ship_id)
	ship_assembled.emit(planet_id, ship_id)
	_dispatch_event(&"ship_assembled", {"planet_id": planet_id, "ship_id": ship_id})
	mark_milestone(faction_of(planet_id), &"first_ship")

func _on_domain_faction_changed(planet_id: StringName, old_faction: StringName, new_faction: StringName) -> void:
	faction_changed.emit(planet_id, old_faction, new_faction)
	_dispatch_event(&"faction_changed", {"planet_id": planet_id, "old_faction": old_faction, "new_faction": new_faction})
	if new_faction != FACTION_NEUTRAL and get_ownership_count(new_faction) >= 2:
		mark_milestone(new_faction, &"second_planet")

func _on_domain_milestone_reached(faction: StringName, milestone_id: StringName) -> void:
	milestone_reached.emit(faction, milestone_id)
	_dispatch_event(&"milestone_reached", {"faction": faction, "milestone_id": milestone_id})
	if faction == FACTION_PLAYER and milestone_id == &"second_planet":
		mid_game_started.emit(faction)
		_dispatch_event(&"mid_game_started", {"faction": faction})

func reset_from_catalog(catalog: PlanetCatalog) -> void:
	faction_domain.reset(catalog)
	economy_domain.reset()
	tech_domain.reset()
	ship_domain.reset()
	_transit_records.clear()
	_pending_battle = null
	catalog_reset.emit(catalog)

func reset_for_infinite_world() -> void:
	faction_domain.reset_infinite()
	economy_domain.reset()
	tech_domain.reset()
	ship_domain.reset()
	_transit_records.clear()
	_pending_battle = null
	catalog_reset.emit(null)

## Starts a new run and is the only public path that resets domain state.
func begin_new_game(catalog: PlanetCatalog, scenario_id: StringName, layout_seed: int, infinite_world: bool = false) -> void:
	_run_active = true
	_run_id = StringName("run_%d" % layout_seed)
	_run_scenario_id = scenario_id
	_run_layout_seed = layout_seed
	_run_infinite_world = infinite_world
	_reconnect_requested = false
	_pending_chunk_data = null
	_pending_timers.clear()
	_sync_session()
	if infinite_world:
		reset_for_infinite_world()
	else:
		reset_from_catalog(catalog)
	var player_homeworld: StringName = faction_domain.homeworld_for(FACTION_PLAYER)
	ship_domain.ensure_starter_research_ship(FACTION_PLAYER, player_homeworld, DEFAULT_SHIP_PART_CATALOG)
	run_started.emit(_run_id, _run_layout_seed)
	# Event-Boundary: run_started zusätzlich über den zentralen EventBus ausliefern,
	# damit Konsumenten (WorldChronicle, EventLog, …) nicht direkt an GameState
	# hängen müssen. Das direkte Signal bleibt als Compatibility-API erhalten.
	_dispatch_event(&"run_started", {"run_id": _run_id, "layout_seed": _run_layout_seed})

## Reconnects a newly loaded world scene to this run without mutating any
## faction, economy, technology, or ship-domain data.
func reconnect_world(scenario_id: StringName, layout_seed: int, infinite_world: bool = false) -> bool:
	if not _run_active:
		return false
	if not String(scenario_id).is_empty():
		_run_scenario_id = scenario_id
	_run_layout_seed = layout_seed
	_run_infinite_world = infinite_world
	_sync_session()
	return true

func request_world_reconnect() -> void:
	_reconnect_requested = true

func consume_world_reconnect_request() -> bool:
	var requested := _reconnect_requested
	_reconnect_requested = false
	return requested

func has_active_run() -> bool:
	return _run_active

func run_id() -> StringName:
	return _run_id

## Typed session bridge (scenario, seed, world mode) shared across scenes.
func session() -> RunSession:
	if _session == null:
		_session = RunSession.new()
	return _session

## Clears the active run so the next world boot starts a fresh game instead of
## reconnecting. Called by the main menu's "Neues Spiel" flow.
func request_new_run() -> void:
	_run_active = false
	_reconnect_requested = false
	_run_id = &""
	_run_scenario_id = &""
	_run_layout_seed = 0
	_run_infinite_world = false
	_pending_chunk_data = null
	_pending_timers.clear()
	if _session != null:
		_session.run_id = &""

func world_session_context() -> Dictionary:
	return {
		"run_id": _run_id,
		"scenario_id": _run_scenario_id,
		"layout_seed": _run_layout_seed,
		"infinite_world": _run_infinite_world,
	}

func _sync_session() -> void:
	if _session == null:
		_session = RunSession.new()
	_session.run_id = _run_id
	_session.scenario_id = _run_scenario_id
	_session.layout_seed = _run_layout_seed
	_session.infinite_world = _run_infinite_world
	if _session.started_at <= 0:
		_session.started_at = int(Time.get_unix_time_from_system())

func set_pending_battle_context(context: BattleContext) -> void:
	_pending_battle = context.copy() if context != null else null
	battle_context_changed.emit(_pending_battle)

func pending_battle_context() -> BattleContext:
	return _pending_battle.copy() if _pending_battle != null else null

func clear_pending_battle_context(battle_id: StringName = &"") -> void:
	if _pending_battle == null:
		return
	if not String(battle_id).is_empty() and _pending_battle.battle_id != battle_id:
		return
	_pending_battle = null
	battle_context_changed.emit(null)

func register_transit(record: TransitRecord) -> bool:
	if record == null or String(record.transit_id).is_empty():
		return false
	_transit_records[record.transit_id] = record.copy()
	transit_changed.emit(record)
	return true

func update_transit(record: TransitRecord) -> bool:
	return register_transit(record)

func remove_transit(transit_id: StringName) -> void:
	_transit_records.erase(transit_id)

func get_transit(transit_id: StringName) -> TransitRecord:
	var record: TransitRecord = _transit_records.get(transit_id) as TransitRecord
	return record.copy() if record != null else null

func get_transit_records() -> Array[TransitRecord]:
	var result: Array[TransitRecord] = []
	for value in _transit_records.values():
		var record: TransitRecord = value as TransitRecord
		if record != null:
			result.append(record.copy())
	return result

func next_transit_id() -> StringName:
	_next_transit_index += 1
	return StringName("transit_%d" % _next_transit_index)

func set_jobs_auto_advance(auto_advance: bool) -> void:
	_jobs_auto_advance = auto_advance

func jobs_auto_advance_enabled() -> bool:
	return _jobs_auto_advance

func set_player_identity(player_name: String, profile: String = "FORSCHER") -> void:
	_player_name = player_name.strip_edges()
	_stickman_profile = profile.strip_edges().to_upper() if not profile.strip_edges().is_empty() else "FORSCHER"

func player_identity() -> Dictionary:
	return {"name": _player_name, "profile": _stickman_profile}

func advance_upgrade_builds(delta: float) -> void:
	economy_domain.advance_upgrade_builds(delta)

func upgrade_build_in_progress(planet_id: StringName, upgrade_id: StringName = &"") -> bool:
	return economy_domain.upgrade_build_in_progress(planet_id, upgrade_id)

func upgrade_build_remaining(planet_id: StringName, upgrade_id: StringName) -> float:
	return economy_domain.upgrade_build_remaining(planet_id, upgrade_id)

func abort_upgrade_build(planet_id: StringName, upgrade_id: StringName) -> bool:
	return economy_domain.abort_upgrade_build(planet_id, upgrade_id)

func advance_building_jobs(delta: float) -> void:
	economy_domain.advance_building_jobs(delta)

func building_job_in_progress(planet_id: StringName, q: int, r: int) -> bool:
	return economy_domain.building_job_in_progress(planet_id, q, r)

func abort_building_job(planet_id: StringName, q: int, r: int) -> bool:
	return economy_domain.abort_building_job(planet_id, q, r)

func advance_research(delta: float) -> void:
	tech_domain.advance_research(delta)

func advance_research_faction(faction: StringName, delta: float) -> void:
	tech_domain.advance_research_faction(faction, delta)

func advance_builds(delta: float) -> void:
	ship_domain.advance_builds(delta)

func advance_research_ship_tasks(delta: float) -> void:
	ship_domain.advance_research_ship_tasks(delta)

func _process(delta: float) -> void:
	if _jobs_auto_advance:
		advance_research(delta)
		advance_builds(delta)
		economy_domain.advance_upgrade_builds(delta)
		economy_domain.advance_building_jobs(delta)
		advance_research_ship_tasks(delta)

# --- FACTION & OWNERSHIP DELEGATES ---
func set_faction(planet_id: StringName, faction: StringName) -> void:
	faction_domain.set_faction(planet_id, faction)

func register_planet(planet_id: StringName, initial_faction: StringName) -> void:
	faction_domain.register_planet(planet_id, initial_faction)

func register_homeworld(faction: StringName, planet_id: StringName) -> void:
	faction_domain.register_homeworld(faction, planet_id)

func seed_starting_workers(planet_id: StringName, profile: PlanetSizeProfile) -> void:
	faction_domain.seed_starting_workers(planet_id, profile)

func faction_of(planet_id: StringName) -> StringName:
	return faction_domain.faction_of(planet_id)

func is_uninhabited(planet_id: StringName) -> bool:
	return faction_of(planet_id) == FACTION_UNINHABITED

func is_owned_by(planet_id: StringName, faction: StringName) -> bool:
	return faction_domain.is_owned_by(planet_id, faction)

func homeworld_for(faction: StringName) -> StringName:
	return faction_domain.homeworld_for(faction)

func get_ownership_count(faction: StringName) -> int:
	return faction_domain.get_ownership_count(faction)

func all_owned_planets(faction: StringName) -> Array[StringName]:
	return faction_domain.all_owned_planets(faction)

## Explizite, stabile Input-Schnittstelle für externe Systeme (z.B. WorldChronicle),
## die Weltfakten lesen müssen, ohne in Domain-Interna zu greifen.
## Liefert {faction_id: [planet_ids]} für alle besiedelten Fraktionen
## (neutral/uninhabited ausgeschlossen).
func faction_planet_snapshot() -> Dictionary:
	var result := {}
	for pid in faction_domain.ownership:
		var fid: StringName = faction_domain.ownership[pid] as StringName
		if String(fid).is_empty() or fid == FACTION_NEUTRAL or fid == FACTION_UNINHABITED:
			continue
		if not result.has(fid):
			result[fid] = []
		result[fid].append(pid)
	return result

func starting_workers_of(planet_id: StringName) -> int:
	return int(faction_domain.starting_workers.get(planet_id, 0))

func add_starting_workers(planet_id: StringName, amount: int) -> void:
	faction_domain.add_starting_workers(planet_id, amount)

func discover_planet(faction: StringName, planet_id: StringName) -> bool:
	return faction_domain.discover_planet(faction, planet_id)

func scan_planet(faction: StringName, planet_id: StringName, resource_id: StringName = &"", size_id: StringName = &"", build_slots: int = 0) -> bool:
	var newly_scanned: bool = faction_domain.scan_planet(faction, planet_id, resource_id, size_id, build_slots)
	if newly_scanned:
		mark_milestone(faction, &"first_scan")
	return newly_scanned

func is_known(planet_id: StringName, faction: StringName) -> bool:
	return faction_domain.is_known(planet_id, faction)

func has_scanned_planet(faction: StringName, planet_id: StringName = &"") -> bool:
	return faction_domain.has_scanned_planet(faction, planet_id)

func scan_info_for(faction: StringName, planet_id: StringName) -> Dictionary:
	return faction_domain.scan_info_for(faction, planet_id)

func known_planets_of(faction: StringName) -> Array[StringName]:
	return faction_domain.known_planets_of(faction)

# Lookup by callers using the conflict-manager naming convention.
func mark_milestone(faction: StringName, milestone_id: StringName) -> bool:
	return faction_domain.mark_milestone(faction, milestone_id)

func has_milestone(faction: StringName, milestone_id: StringName) -> bool:
	return faction_domain.has_milestone(faction, milestone_id)

func get_milestones(faction: StringName) -> Dictionary:
	return faction_domain.get_milestones(faction)

# --- ECONOMY & VAULT DELEGATES ---
func credit_transport_resources(faction: StringName, resource_id: StringName, amount: int) -> bool:
	var credited: bool = economy_domain.credit_transport_resources(faction, resource_id, amount)
	if credited:
		mark_milestone(faction, &"first_transport")
	return credited

func get_faction_credits(faction: StringName) -> int:
	return economy_domain.get_faction_credits(faction)

func add_faction_credits(faction: StringName, amount: int) -> int:
	return economy_domain.add_faction_credits(faction, amount)

func spend_faction_credits(faction: StringName, amount: int) -> bool:
	return economy_domain.spend_faction_credits(faction, amount)

func can_spend_faction_credits(faction: StringName, amount: int) -> bool:
	return economy_domain.can_spend_faction_credits(faction, amount)

func can_spend_faction_cost(faction: StringName, resource_id: StringName, resource_amount: int, credit_amount: int) -> bool:
	return economy_domain.can_spend_cost(faction, resource_id, resource_amount, credit_amount)

func begin_worker_transport(faction: StringName, source_planet_id: StringName, destination_planet_id: StringName, amount: int, duration: float, route_path: Array[Vector2]) -> StringName:
	return economy_domain.begin_worker_transport(faction, source_planet_id, destination_planet_id, amount, duration, route_path)

func update_worker_transport(transport_id: StringName, phase: StringName, cargo_resource_id: StringName = &"", cargo_amount: int = 0) -> bool:
	return economy_domain.update_worker_transport(transport_id, phase, cargo_resource_id, cargo_amount)

func set_worker_transport_escorted(transport_id: StringName, escorted: bool = true) -> bool:
	return economy_domain.set_worker_transport_escorted(transport_id, escorted)

func get_worker_transport_records(faction: StringName = &"") -> Array[Dictionary]:
	return economy_domain.get_worker_transport_records(faction)

func complete_worker_transport(transport_id: StringName, delivered: bool = true) -> bool:
	return economy_domain.complete_worker_transport(transport_id, delivered)

func get_market_price(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> float:
	return economy_domain.get_market_price(from_planet, to_planet, resource_id)

func market_snapshot() -> Dictionary:
	return economy_domain.market_snapshot()

func spend_faction_cost(faction: StringName, resource_id: StringName, resource_amount: int, credit_amount: int) -> bool:
	return economy_domain.spend_cost(faction, resource_id, resource_amount, credit_amount)

func get_faction_resource(faction: StringName, resource_id: StringName) -> int:
	return economy_domain.get_faction_resource(faction, resource_id)

func get_faction_vault_snapshot(faction: StringName) -> Dictionary:
	return economy_domain.get_faction_vault_snapshot(faction)

func add_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> int:
	return economy_domain.add_faction_resource(faction, resource_id, amount)

func spend_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> bool:
	return economy_domain.spend_faction_resource(faction, resource_id, amount)

func can_spend_faction_resource(faction: StringName, resource_id: StringName, amount: int) -> bool:
	return economy_domain.can_spend_faction_resource(faction, resource_id, amount)

func set_planet_resource(planet_id: StringName, resource_id: StringName) -> void:
	economy_domain.set_planet_resource(planet_id, resource_id)

func resource_of(planet_id: StringName) -> StringName:
	return economy_domain.resource_of(planet_id)

func deal_resources(catalog: PlanetCatalog, pool: ResourcePool = null, seed_value: int = 0) -> void:
	economy_domain.deal_resources(catalog, pool, seed_value)

func deal_resources_for_planets(planet_data: Array, pool: ResourcePool = null, seed_value: int = 0) -> void:
	economy_domain.deal_resources_for_planets(planet_data, pool, seed_value)

func resource_snapshot() -> Dictionary:
	return economy_domain.resource_snapshot()

func validate_resources(pool: ResourcePool = null) -> PackedStringArray:
	return economy_domain.validate_resources(pool, faction_domain.homeworlds)

func generate_resources_for_planet(planet_id: StringName, catalog: PlanetUpgradeCatalog = null, base_amount: int = 1) -> int:
	return economy_domain.generate_resources_for_planet(planet_id, faction_domain, tech_domain, catalog, base_amount)

func convert_refinery_resources(planet_id: StringName) -> Dictionary:
	return economy_domain.convert_refinery_resources(planet_id, faction_domain)

func has_planet_upgrade(planet_id: StringName, upgrade_id: StringName) -> bool:
	return economy_domain.has_planet_upgrade(planet_id, upgrade_id)

func get_planet_upgrades(planet_id: StringName) -> Array[StringName]:
	return economy_domain.get_planet_upgrades(planet_id)

func can_purchase_upgrade(planet_id: StringName, upgrade_id: StringName, catalog: PlanetUpgradeCatalog = null, available_workers: int = -1) -> bool:
	return economy_domain.can_purchase_upgrade_with_domains(planet_id, upgrade_id, faction_domain, tech_domain, catalog, available_workers)

func purchase_upgrade(planet_id: StringName, upgrade_id: StringName, catalog: PlanetUpgradeCatalog = null, available_workers: int = -1) -> bool:
	return economy_domain.purchase_upgrade_with_domains(planet_id, upgrade_id, faction_domain, tech_domain, catalog, available_workers)

func add_planet_upgrade(planet_id: StringName, upgrade_id: StringName) -> void:
	economy_domain.add_planet_upgrade(planet_id, upgrade_id)

func has_worker_factory(planet_id: StringName) -> bool:
	return economy_domain.has_worker_factory(planet_id)

func can_build_worker_factory(planet_id: StringName, cost_resource: StringName, cost_amount: int, credit_cost: int = 5) -> bool:
	return economy_domain.can_build_worker_factory_with_domains(planet_id, faction_domain, tech_domain, cost_resource, cost_amount, credit_cost)

func build_worker_factory(planet_id: StringName, cost_resource: StringName, cost_amount: int, credit_cost: int = 5) -> bool:
	var built: bool = economy_domain.build_worker_factory_with_domains(planet_id, faction_domain, tech_domain, cost_resource, cost_amount, credit_cost)
	if built:
		mark_milestone(faction_of(planet_id), &"first_worker_factory")
	return built

func register_gathering_workers(faction: StringName, planet_id: StringName, worker_amount: int, source_planet_id: StringName = &"") -> int:
	return economy_domain.register_gathering_workers_with_domains(faction, planet_id, worker_amount, faction_domain, source_planet_id)


func get_available_workers(planet_id: StringName, total_workers: int) -> int:
	return economy_domain.available_workers(planet_id, total_workers)

func reserve_workers(planet_id: StringName, job_id: StringName, amount: int, total_workers: int) -> bool:
	return economy_domain.reserve_workers(planet_id, job_id, amount, total_workers)

func release_workers(planet_id: StringName, job_id: StringName) -> int:
	return economy_domain.release_workers(planet_id, job_id)

func get_gathering_workers(faction: StringName, planet_id: StringName) -> int:
	return economy_domain.gathering_workers_on(faction, planet_id)

func get_gathering_source(faction: StringName, planet_id: StringName) -> StringName:
	return economy_domain.get_gathering_source(faction, planet_id)

func withdraw_gathering_workers(faction: StringName, planet_id: StringName, amount: int) -> int:
	var result: Dictionary = economy_domain.withdraw_gathering_workers(faction, planet_id, amount)
	return int(result.get("count", 0))

func gathering_workers_on(faction: StringName, planet_id: StringName) -> int:
	return economy_domain.gathering_workers_on(faction, planet_id)

func gather_income_tick(base_amounts: Dictionary, catalog: PlanetUpgradeCatalog = null) -> int:
	return economy_domain.gather_income_tick(base_amounts, catalog)

# --- TECHNOLOGY DELEGATES ---
func has_technology(faction: StringName, technology_id: StringName) -> bool:
	return tech_domain.has_technology(faction, technology_id)

func get_researched_technologies(faction: StringName) -> Array[StringName]:
	return tech_domain.get_researched_technologies(faction)

func can_research_technology(faction: StringName, technology_id: StringName, catalog: TechnologyCatalog = null) -> bool:
	var cat: TechnologyCatalog = catalog if catalog != null else DEFAULT_TECHNOLOGY_CATALOG
	return tech_domain.can_research_technology(faction, technology_id, cat, economy_domain, faction_domain)

func research_technology(faction: StringName, technology_id: StringName, catalog: TechnologyCatalog = null) -> bool:
	var cat: TechnologyCatalog = catalog if catalog != null else DEFAULT_TECHNOLOGY_CATALOG
	return tech_domain.research_technology(faction, technology_id, cat, economy_domain, faction_domain)

func research_in_progress(faction: StringName, technology_id: StringName) -> bool:
	return tech_domain.research_in_progress(faction, technology_id)

func research_remaining(faction: StringName, technology_id: StringName) -> float:
	return tech_domain.research_remaining(faction, technology_id)

func has_planet_technology(planet_id: StringName, technology_id: StringName) -> bool:
	return tech_domain.has_planet_technology(planet_id, technology_id)

func get_planet_technologies(planet_id: StringName) -> Array[StringName]:
	return tech_domain.get_planet_technologies(planet_id)

func can_research_planet_technology(faction: StringName, planet_id: StringName, technology_id: StringName, catalog: TechnologyCatalog = null) -> bool:
	var cat: TechnologyCatalog = catalog if catalog != null else DEFAULT_TECHNOLOGY_CATALOG
	return tech_domain.can_research_planet_technology(faction, planet_id, technology_id, cat, economy_domain, faction_domain)

func research_planet_technology(faction: StringName, planet_id: StringName, technology_id: StringName, catalog: TechnologyCatalog = null) -> bool:
	var cat: TechnologyCatalog = catalog if catalog != null else DEFAULT_TECHNOLOGY_CATALOG
	return tech_domain.research_planet_technology(faction, planet_id, technology_id, cat, economy_domain, faction_domain)

# --- SHIP & FLEET DELEGATES ---
func ensure_starter_research_ship(faction: StringName, planet_id: StringName) -> StringName:
	return ship_domain.ensure_starter_research_ship(faction, planet_id, DEFAULT_SHIP_PART_CATALOG)

func mark_research_ship_departed(ship_id: StringName) -> bool:
	return ship_domain.mark_research_ship_departed(ship_id)

func mark_research_ship_arrived(ship_id: StringName, planet_id: StringName) -> bool:
	return ship_domain.mark_research_ship_arrived(ship_id, planet_id)

func get_research_ship_records(faction: StringName = &"") -> Array[Dictionary]:
	return ship_domain.get_research_ship_records(faction)

func register_persistent_fleet(fleet: FleetSnapshot, status: StringName = &"in_transit") -> void:
	ship_domain.register_persistent_fleet(fleet, status)

func get_persistent_ship_records(faction: StringName = &"") -> Array[Dictionary]:
	return ship_domain.get_persistent_ship_records(faction)

func mark_persistent_ship_arrived(ship_id: StringName, planet_id: StringName, status: StringName = &"idle") -> bool:
	return ship_domain.mark_persistent_ship_arrived(ship_id, planet_id, status)

func mark_persistent_ship_lost(ship_id: StringName) -> bool:
	return ship_domain.mark_persistent_ship_lost(ship_id)

func get_research_missions(faction: StringName = &"") -> Array[Dictionary]:
	return ship_domain.get_research_missions(faction)

func queue_research_mission(faction: StringName, target_planet_id: StringName, task_type: StringName, duration: float = 2.0) -> StringName:
	return ship_domain.queue_research_mission(faction, target_planet_id, task_type, duration)

func cancel_research_mission(mission_id: StringName) -> bool:
	return ship_domain.cancel_research_mission(mission_id)

func get_persistent_ship(ship_id: StringName) -> RefCounted:
	return ship_domain.get_persistent_ship(ship_id)

func get_ship_part_inventory(planet_id: StringName) -> Dictionary:
	return ship_domain.get_ship_part_inventory(planet_id)

func get_ship_part_count(planet_id: StringName, part_id: StringName) -> int:
	return int(ship_domain.get_ship_part_inventory(planet_id).get(part_id, 0))

func add_ship_part(planet_id: StringName, part_id: StringName, count: int = 1) -> void:
	ship_domain.add_ship_part(planet_id, part_id, count)

func spend_ship_part(planet_id: StringName, part_id: StringName, count: int = 1) -> bool:
	return ship_domain.spend_ship_part(planet_id, part_id, count)

func can_buy_ship_part(planet_id: StringName, part_id: StringName, catalog: ShipPartCatalog = null) -> bool:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	var faction: StringName = faction_of(planet_id)
	return ship_domain.can_buy_ship_part(faction, planet_id, part_id, cat, economy_domain, tech_domain)

func buy_ship_part(planet_id: StringName, part_id: StringName, catalog: ShipPartCatalog = null) -> bool:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	var faction: StringName = faction_of(planet_id)
	return ship_domain.buy_ship_part(faction, planet_id, part_id, cat, economy_domain, tech_domain)

func get_ship_assemblies(planet_id: StringName) -> Dictionary:
	return ship_domain.get_ship_assemblies(planet_id)

func has_ship_assembly(planet_id: StringName, ship_id: StringName) -> bool:
	return ship_domain.has_ship_assembly(planet_id, ship_id)

func get_ship_assembly(planet_id: StringName, ship_id: StringName) -> ShipAssembly:
	return ship_domain.get_ship_assembly(planet_id, ship_id)

func can_assemble_ship(planet_id: StringName, hull_id: StringName, scanner_id: StringName, module_ids: Array, catalog: ShipPartCatalog = null, weapon_id: StringName = &"", drive_id: StringName = &"", shield_id: StringName = &"") -> bool:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	return ship_domain.can_assemble_ship(planet_id, hull_id, scanner_id, module_ids, weapon_id, drive_id, shield_id, cat)

func assemble_ship(
	planet_id: StringName,
	hull_id: StringName,
	scanner_id: StringName,
	module_ids: Array,
	catalog: ShipPartCatalog = null,
	weapon_id: StringName = &"",
	drive_id: StringName = &"",
	shield_id: StringName = &"",
	blueprint_id: StringName = &"",
	custom_seed: int = -1,
	ship_role: StringName = &""
) -> StringName:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	return ship_domain.assemble_ship(planet_id, hull_id, scanner_id, module_ids, weapon_id, drive_id, shield_id, cat, custom_seed, blueprint_id, ship_role)

func disassemble_ship(planet_id: StringName, ship_id: StringName) -> bool:
	return ship_domain.disassemble_ship(planet_id, ship_id)

func launch_ship(planet_id: StringName, ship_id: StringName) -> ShipAssembly:
	return ship_domain.launch_ship(planet_id, ship_id)

func get_ship_build_jobs(planet_id: StringName) -> Dictionary:
	return ship_domain.get_ship_build_jobs(planet_id)

func ship_build_in_progress(planet_id: StringName, ship_id: StringName = &"") -> bool:
	return ship_domain.ship_build_in_progress(planet_id, ship_id)

func ship_build_remaining(planet_id: StringName, ship_id: StringName) -> float:
	return ship_domain.ship_build_remaining(planet_id, ship_id)

func create_fleet_from_planet(planet_id: StringName, ship_ids: Array, catalog: ShipPartCatalog = null) -> FleetSnapshot:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	var faction: StringName = faction_of(planet_id)
	return ship_domain.create_fleet_from_planet(planet_id, ship_ids, faction, cat)

func preview_fleet_from_planet(planet_id: StringName, ship_ids: Array, catalog: ShipPartCatalog = null) -> FleetSnapshot:
	var cat: ShipPartCatalog = catalog if catalog != null else DEFAULT_SHIP_PART_CATALOG
	var faction: StringName = faction_of(planet_id)
	return ship_domain.preview_fleet_from_planet(planet_id, ship_ids, faction, cat)

func disband_fleet_to_planet(fleet: FleetSnapshot, planet_id: StringName) -> void:
	ship_domain.disband_fleet_to_planet(fleet, planet_id)

func reconcile_defender_fleet(planet_id: StringName, defender_fleet: FleetSnapshot, surviving: Array[ShipAssembly]) -> void:
	ship_domain.reconcile_defender_fleet(planet_id, defender_fleet, surviving)

# --- GRID BUILDINGS, LOCAL RESOURCES & CAPTURE DELEGATES ---
func can_place_planet_building(planet_id: StringName, building_id: StringName, catalog: BuildingCatalog = null) -> bool:
	return economy_domain.can_place_building(planet_id, building_id, faction_domain, tech_domain, catalog)

func place_planet_building(planet_id: StringName, building_id: StringName, q: int, r: int, catalog: BuildingCatalog = null) -> bool:
	return economy_domain.place_building(planet_id, building_id, q, r, faction_domain, tech_domain, catalog)


func remove_planet_building(planet_id: StringName, q: int, r: int) -> bool:
	return not String(economy_domain.remove_planet_building(planet_id, q, r)).is_empty()

func planet_building_at(planet_id: StringName, q: int, r: int) -> StringName:
	return economy_domain.planet_building_at(planet_id, q, r)

func get_local_resource(planet_id: StringName, resource_id: StringName) -> int:
	return economy_domain.get_local_resource(planet_id, resource_id)

func get_local_resources(planet_id: StringName) -> Dictionary:
	return economy_domain.local_vault(planet_id).duplicate()

func add_local_resource(planet_id: StringName, resource_id: StringName, amount: int) -> int:
	return economy_domain.add_local_resource(planet_id, resource_id, amount)

func spend_local_resource(planet_id: StringName, resource_id: StringName, amount: int) -> bool:
	return economy_domain.spend_local_resource(planet_id, resource_id, amount)

func can_spend_local_resource(planet_id: StringName, resource_id: StringName, amount: int) -> bool:
	return amount >= 0 and economy_domain.get_local_resource(planet_id, resource_id) >= amount

func transfer_local_resources(from_planet: StringName, to_planet: StringName, resource_id: StringName, amount: int) -> bool:
	return economy_domain.transfer_resources(from_planet, to_planet, resource_id, amount)

func deal_local_resources(planet_ids: Array, pool: ResourcePool = null, seed_value: int = 0) -> void:
	economy_domain.seed_local_resources(planet_ids, pool, seed_value)

func can_register_trade_route(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> bool:
	return economy_domain.can_register_trade_route(from_planet, to_planet, resource_id)

func register_trade_route(from_planet: StringName, to_planet: StringName, resource_id: StringName) -> StringName:
	return economy_domain.register_trade_route(from_planet, to_planet, resource_id)

func tick_trade_routes() -> int:
	return economy_domain.tick_trade_routes()

func trade_routes_snapshot() -> Dictionary:
	return economy_domain.trade_routes_snapshot()

func capture_planet(planet_id: StringName, decision: StringName, faction: StringName) -> void:
	match decision:
		&"loot":
			steal_resources(planet_id, faction, 0.5)
		&"neutralize":
			set_faction(planet_id, FACTION_NEUTRAL)
		_:
			set_faction(planet_id, faction)

func steal_resources(planet_id: StringName, attacker_faction: StringName, percentage: float = 0.5) -> Dictionary:
	return economy_domain.steal_resources(planet_id, attacker_faction, percentage)


# --- SAVE / LOAD SNAPSHOTS ---

## Captures the full run state as a pure-data RunSaveData resource. The world
## scene is not required: everything lives in the domains, transit records and
## the chunk cache. Runtime-only objects (PersistentShipRecord, ResearchMission)
## are flattened into serializable dictionaries.
func snapshot_run() -> RunSaveData:
	var data := RunSaveData.new()
	data.save_version = RunSaveData.SAVE_VERSION
	data.session = session().copy()
	faction_domain.capture_snapshot(data)
	economy_domain.capture_snapshot(data)
	tech_domain.capture_snapshot(data)
	ship_domain.capture_snapshot(data)

	# Transits
	for record_value in _transit_records.values():
		var record: TransitRecord = record_value as TransitRecord
		if record != null:
			data.transits.append(record.copy())
	data.next_transit_index = _next_transit_index
	# Chunk world + timers
	data.chunk_data = _capture_chunk_data()
	data.timers = _capture_timers().duplicate()
	var chronicle: Node = _get_world_chronicle()
	if chronicle != null and chronicle.has_method("snapshot"):
		data.chronicle = chronicle.call("snapshot") as ChronicleSaveData
	return data

## Restores a snapshot into the domains and marks the world for reconnect on
## the next world-scene boot. The chunk payload and pacing timers are handed to
## the world scene via consume_pending_* accessors.
func restore_run(data: RunSaveData) -> bool:
	if data == null:
		return false
	_run_active = true
	_reconnect_requested = true
	_pending_battle = null
	if data.session != null:
		_session = data.session.copy()
		_run_id = _session.run_id
		_run_scenario_id = _session.scenario_id
		_run_layout_seed = _session.layout_seed
		_run_infinite_world = _session.infinite_world
	else:
		_run_id = &""
		_run_scenario_id = &""
		_run_layout_seed = 0
		_run_infinite_world = false

	faction_domain.restore_snapshot(data)
	economy_domain.restore_snapshot(data)
	tech_domain.restore_snapshot(data)
	ship_domain.restore_snapshot(data)

	# Transits
	_transit_records.clear()
	for record in data.transits:
		if record != null:
			_transit_records[record.transit_id] = record.copy()
	_next_transit_index = data.next_transit_index
	# Chunk world + timers (consumed by the world scene on boot)
	_pending_chunk_data = data.chunk_data
	_pending_timers = data.timers.duplicate()
	var chronicle: Node = _get_world_chronicle()
	if chronicle != null and chronicle.has_method("restore") and data.chronicle != null:
		chronicle.call("restore", data.chronicle)
	return true

func _get_world_chronicle() -> Node:
	var root: Node = get_tree().root if get_tree() != null else null
	return root.get_node_or_null("WorldChronicle") if root != null else null

func pending_chunk_data() -> ChunkSaveData:
	return _pending_chunk_data

func consume_pending_chunk_data() -> ChunkSaveData:
	var data: ChunkSaveData = _pending_chunk_data
	_pending_chunk_data = null
	return data

func pending_timers() -> Dictionary:
	return _pending_timers.duplicate()

func consume_pending_timers() -> Dictionary:
	var timers: Dictionary = _pending_timers.duplicate()
	_pending_timers.clear()
	return timers

## Explizite Dependency-Registrierung: Die Welt-Szene meldet ihre
## ChunkCoordinator-/EconomyManager-Instanz hier an, statt dass GameState den
## Szenenbaum nach Klassennamen durchsuchen muss (Scene-Boundary). Die
## _find_*-Fallbacks bleiben nur für Aufrufer ohne Registrierung (z.B. isolierte
## Fixtures) erhalten.
var _registered_chunk_coordinator: Node = null
var _registered_economy_manager: Node = null

func register_chunk_coordinator(node: Node) -> void:
	_registered_chunk_coordinator = node

func register_economy_manager(node: Node) -> void:
	_registered_economy_manager = node

## Expliziter Zugriff auf den registrierten EconomyManager (Scene-Boundary).
## Fallback auf den Szenenbaum-Scan nur für Aufrufer ohne Registrierung
## (isolierte Fixtures/Tests).
func get_economy_manager() -> Node:
	if _registered_economy_manager != null and is_instance_valid(_registered_economy_manager):
		return _registered_economy_manager
	return _find_economy_manager()

func _capture_chunk_data() -> ChunkSaveData:
	var coordinator: Node = _registered_chunk_coordinator
	if coordinator == null or not is_instance_valid(coordinator):
		coordinator = _find_chunk_coordinator()
	if coordinator != null and coordinator.has_method("save_state"):
		return coordinator.call("save_state") as ChunkSaveData
	return null

func _capture_timers() -> Dictionary:
	var economy_manager: Node = _registered_economy_manager
	if economy_manager == null or not is_instance_valid(economy_manager):
		economy_manager = _find_economy_manager()
	if economy_manager == null:
		return {}
	var result: Dictionary = {}
	if economy_manager.has_method("economy_tick_remaining"):
		result["economy_remaining"] = float(economy_manager.call("economy_tick_remaining"))
	if economy_manager.has_method("gather_tick_remaining"):
		result["gather_remaining"] = float(economy_manager.call("gather_tick_remaining"))
	return result

func _find_chunk_coordinator() -> Node:
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return null
	return _find_node_with_method(scene, "save_state", "ChunkCoordinator")

func _find_economy_manager() -> Node:
	var scene: Node = get_tree().current_scene if get_tree() != null else null
	if scene == null:
		return null
	return _find_node_with_method(scene, "restore_timer_remaining", "PlanetEconomyManager")

func _find_node_with_method(node: Node, method: String, class_hint: String) -> Node:
	if node == null:
		return null
	if node.has_method(method):
		var script: Script = node.get_script()
		if script != null and String(script.get_global_name()) == class_hint:
			return node
	for child in node.get_children():
		var found: Node = _find_node_with_method(child, method, class_hint)
		if found != null:
			return found
	return null

func _restore_dict(source: Dictionary) -> Dictionary:
	return RunSaveData.restore_dict(source)

func _restore_array(source: Array) -> Array:
	return RunSaveData.restore_array(source)

# --- VALIDATION HELPERS ---
func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	for p_id in faction_domain.ownership:
		var faction: StringName = faction_domain.ownership[p_id]
		if faction != FACTION_PLAYER and faction != FACTION_CPU and faction != FACTION_NEUTRAL:
			errors.append("Invalid faction for planet %s: %s" % [p_id, faction])
	return errors

func validate_starting_setup() -> PackedStringArray:
	var errors := PackedStringArray()
	if homeworld_for(FACTION_PLAYER) == &"":
		errors.append("Missing player homeworld")
	if homeworld_for(FACTION_CPU) == &"":
		errors.append("Missing CPU homeworld")
	return errors
