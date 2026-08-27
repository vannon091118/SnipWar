extends Node

## Layer-1 conflict orchestration (event-driven, no direct scene instantiation).
##
## ConflictManager lives inside Layer 1 (child of PlanetField) and orchestrates
## ship transits, arrival resolution and combat. It does NOT instantiate
## BattleScene or ConquestScene directly — those responsibilities belong to
## GameCycleManager (or its ReplayOrchestrator).
##
## Layer contract:
##   Signal: replay_started(type, replay)  — emitted for every combat replay
##   Signal: replay_requested(type, replay) — requested full visual playback
##   Signal: ship_dispatched / ship_arrived  — transit lifecycle

const SHIP_BASE_SCENE: PackedScene = preload("res://scenes/objects/ships/ship_base.tscn")
const DEFAULT_TRANSIT_CONFIG: TransitConfig = preload("res://resources/config/transit_default.tres")
const FLIGHT_TIME_SCRIPT: Script = preload("res://scripts/flight_time.gd")
const ROUTE_ENGAGEMENT_SCRIPT: Script = preload("res://scripts/simulation/route_engagement_resolver.gd")
const COMBAT_SEED_COUNTER_STRIDE: int = 1000003
const BATTLE_SEED_SALT: int = 0x51A7E
const CONQUEST_SEED_SALT: int = 0xC0A57

signal replay_started(simulation_type: StringName, replay: CombatReplay)
signal replay_requested(simulation_type: StringName, replay: CombatReplay)
signal ship_dispatched(ship: ShipBase)
signal ship_arrived(ship: ShipBase)

var transit_config: TransitConfig = DEFAULT_TRANSIT_CONFIG
var _field: Node
var _navigation: NavigationField
var _ship_manager: Node
var _enabled: bool = true
var _active_ships: Array[ShipBase] = []
var _idle_ships: Array[ShipBase] = []
var _game_seed: int = 0
var _battle_counter: int = 0
var _ship_by_transit: Dictionary = {}
var _pending_overlay_context: BattleContext

func _ready() -> void:
	var state: Node = _game_state()
	if state != null and state.has_signal("catalog_reset") and not state.catalog_reset.is_connected(_on_catalog_reset):
		state.catalog_reset.connect(_on_catalog_reset)
	if state != null and state.has_signal("research_ship_task_completed") and not state.research_ship_task_completed.is_connected(_on_research_task_completed):
		state.research_ship_task_completed.connect(_on_research_task_completed)
	_connect_planet_conflicts()

func _connect_planet_conflicts() -> void:
	if _field == null or not is_instance_valid(_field):
		return
	var callback := Callable(self, "_on_planet_conflict_simulated")
	for child in _field.get_children():
		_connect_planet_conflict(child as Planet, callback)
	var coordinator: ChunkCoordinator = _field.get_chunk_coordinator() if _field.has_method("get_chunk_coordinator") else null
	if coordinator != null and not coordinator.planet_added.is_connected(_on_planet_added):
		coordinator.planet_added.connect(_on_planet_added)
	if coordinator != null and not coordinator.planet_removed.is_connected(_on_planet_removed):
		coordinator.planet_removed.connect(_on_planet_removed)

func _connect_planet_conflict(planet: Planet, callback: Callable = Callable()) -> void:
	if planet == null or not is_instance_valid(planet):
		return
	var resolved_callback := callback if callback.is_valid() else Callable(self, "_on_planet_conflict_simulated")
	if not planet.conflict_simulated.is_connected(resolved_callback):
		planet.conflict_simulated.connect(resolved_callback)

## Connects to GameCycleManager so inline replay requests from
## _start_replay are delegated to the proper orchestration layer.
func _connect_replay_orchestration() -> void:
	var main_loop := Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return
	var cycle: Node = (main_loop as SceneTree).root.get_node_or_null("GameCycleManager")
	if cycle == null:
		return
	if not replay_requested.is_connected(Callable(cycle, "_on_replay_requested")):
		replay_requested.connect(Callable(cycle, "_on_replay_requested"))

func _on_research_task_completed(_mission_id: StringName, target_planet_id: StringName, task_type: StringName) -> void:
	if task_type != &"scan":
		return
	var target: Planet = _find_planet(target_planet_id)
	var state: Node = _game_state()
	if target != null and state != null:
		state.scan_planet(GameState.FACTION_PLAYER, target.planet_id, target.get_resource_id(), StringName(target.get_size_profile().id), target.get_build_slot_count())

func _on_planet_added(planet: Planet) -> void:
	_connect_planet_conflict(planet)

func _on_planet_removed(_planet: Planet) -> void:
	return

func _on_planet_conflict_simulated(simulation_type: StringName, combat_replay: CombatReplay) -> void:
	_start_replay(simulation_type, combat_replay)

func _start_replay(simulation_type: StringName, combat_replay: CombatReplay) -> void:
	## ConflictManager does NOT instantiate BattleScene/ConquestScene.
	## It emits replay_started (for result tracking) and replay_requested
	## (for visual playback). GameCycleManager or SceneDirector handles
	## the actual scene instantiation and lifecycle.
	replay_started.emit(simulation_type, combat_replay)
	replay_requested.emit(simulation_type, combat_replay)

func configure(field: Node, navigation: Node, ship_manager: Node, config: TransitConfig = null) -> void:
	_field = field
	_navigation = navigation as NavigationField
	_ship_manager = ship_manager
	transit_config = config if config != null else DEFAULT_TRANSIT_CONFIG
	_game_seed = _resolve_game_seed(field)
	_battle_counter = 0
	_ship_by_transit.clear()
	_connect_planet_conflicts()
	_connect_replay_orchestration()
	call_deferred("_restore_persistent_transits")

func _restore_persistent_transits() -> void:
	var state: Node = _game_state()
	if state == null or not state.has_method("get_transit_records"):
		return
	for record_value in state.get_transit_records():
		var record: TransitRecord = record_value as TransitRecord
		if record == null or record.status != TransitRecord.STATUS_IN_FLIGHT:
			continue
		if _ship_by_transit.has(record.transit_id):
			continue
		var destination := _find_planet(record.destination_planet_id)
		if destination == null:
			continue
		var ship: ShipBase = SHIP_BASE_SCENE.instantiate() as ShipBase
		ship.name = "Transit_%s" % String(record.transit_id)
		ship.transit_id = record.transit_id
		ship.configure(record.fleet.copy(), destination, record.route_path, record.duration, _part_catalog(), record.mission_role, record.source_planet_id)
		add_child(ship)
		ship.arrived.connect(_on_ship_arrived)
		_active_ships.append(ship)
		_ship_by_transit[record.transit_id] = ship
		ship.start_flight_from_elapsed(record.elapsed)
	_materialize_research_ships()

func _materialize_research_ships() -> void:
	var state: Node = _game_state()
	if state == null or not state.has_method("get_research_ship_records"):
		return
	for data in state.get_research_ship_records(GameState.FACTION_PLAYER):
		var ship_id: StringName = data.get("ship_id", &"") as StringName
		var already_present := false
		for idle_ship in _idle_ships:
			if is_instance_valid(idle_ship) and idle_ship.name == "ResearchShip_%s" % String(ship_id):
				already_present = true
				break
		if already_present:
			continue
		var record: ShipDomain.PersistentShipRecord = state.get_persistent_ship(ship_id) as ShipDomain.PersistentShipRecord
		if record == null or record.fleet == null:
			continue
		var location: Planet = _find_planet(record.current_planet_id)
		if location == null:
			continue
		var ship: ShipBase = SHIP_BASE_SCENE.instantiate() as ShipBase
		ship.name = "ResearchShip_%s" % String(ship_id)
		ship.configure_idle(record.fleet.copy(), location, _part_catalog(), &"research", record.current_planet_id)
		add_child(ship)
		_idle_ships.append(ship)

func _find_planet(planet_id: StringName) -> Planet:
	if _field == null or not is_instance_valid(_field):
		return null
	for child in _field.get_children():
		var planet := child as Planet
		if planet != null and planet.planet_id == planet_id:
			return planet
	return null

func game_seed() -> int:
	return _game_seed

func battle_counter() -> int:
	return _battle_counter

func _resolve_game_seed(field: Node) -> int:
	if field == null or not is_instance_valid(field):
		return 0
	var config: WorldConfig = field.get("world_config") as WorldConfig
	return config.layout_seed if config != null else 0

func _requires_combat(destination: Planet, fleet: FleetSnapshot, mission_role: StringName) -> bool:
	if destination == null or fleet == null or fleet.ships.is_empty():
		return false
	var resolved_role: StringName = mission_role if not String(mission_role).is_empty() else fleet.mission_role
	if resolved_role == &"colony":
		return false
	return destination.get_faction() != fleet.faction and fleet.faction != GameState.FACTION_NEUTRAL

func _next_combat_seeds() -> Dictionary:
	_battle_counter += 1
	return {
		"battle_seed": _derive_combat_seed(_battle_counter, BATTLE_SEED_SALT),
		"conquest_seed": _derive_combat_seed(_battle_counter, CONQUEST_SEED_SALT),
	}

func _derive_combat_seed(counter: int, salt: int) -> int:
	var seed_input: int = _game_seed + counter * COMBAT_SEED_COUNTER_STRIDE + salt
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_input
	return int(rng.randi())

func set_enabled(enabled: bool) -> void:
	_enabled = enabled

func active_ship_count() -> int:
	_prune_active_ships()
	return _active_ships.size()

## Returns visible idle armed ships that can accompany a worker convoy.
func get_escort_candidates(source_planet: Planet, destination: Planet) -> Array[ShipBase]:
	var candidates: Array[ShipBase] = []
	if source_planet == null or destination == null:
		return candidates
	for ship in _idle_ships:
		if ship == null or not is_instance_valid(ship) or ship.fleet == null:
			continue
		for assembly in ship.fleet.ships:
			if assembly != null and not String(assembly.weapon_id).is_empty():
				candidates.append(ship)
				break
	return candidates

func has_escort_available(source_planet: Planet, destination: Planet) -> bool:
	if not get_escort_candidates(source_planet, destination).is_empty():
		return true
	var state: Node = _game_state()
	if state == null or source_planet == null or not state.has_method("get_ship_assemblies"):
		return false
	for assembly in state.get_ship_assemblies(source_planet.planet_id).values():
		if assembly is ShipAssembly and not String((assembly as ShipAssembly).weapon_id).is_empty():
			return true
	return false

func dispatch_research_ship(source: Planet, destination: Planet) -> ShipBase:
	if not _enabled or source == null or destination == null or source == destination:
		return null
	var state: Node = _game_state()
	if state == null or not state.has_method("get_research_ship_records"):
		return null
	var record: ShipDomain.PersistentShipRecord = null
	for data in state.get_research_ship_records(GameState.FACTION_PLAYER):
		var candidate: ShipDomain.PersistentShipRecord = state.get_persistent_ship(data.get("ship_id", &"")) as ShipDomain.PersistentShipRecord
		if candidate != null and candidate.status == &"idle" and candidate.current_planet_id == source.planet_id and String(candidate.active_mission_id).is_empty():
			record = candidate
			break
	if record == null or record.fleet == null or _route(source, destination).size() < 2:
		return null
	var route_path: Array[Vector2] = _route(source, destination)
	var distance := PathUtils.distance(route_path)
	var duration: float = FLIGHT_TIME_SCRIPT.seconds_for_ship(distance, record.fleet.ships.size(), transit_config, record.fleet.transfer_speed_multiplier())
	var transit := TransitRecord.new()
	transit.transit_id = state.next_transit_id()
	transit.fleet = record.fleet.copy()
	transit.source_planet_id = source.planet_id
	transit.destination_planet_id = destination.planet_id
	transit.mission_role = &"research"
	transit.route_path = route_path.duplicate()
	transit.duration = duration
	state.register_transit(transit)
	state.ship_domain.mark_research_ship_departed(record.ship_id)
	var ship: ShipBase = SHIP_BASE_SCENE.instantiate() as ShipBase
	ship.name = "ResearchTransit_%s" % String(record.ship_id)
	ship.transit_id = transit.transit_id
	ship.configure(record.fleet.copy(), destination, route_path, duration, _part_catalog(), &"research", source.planet_id)
	add_child(ship)
	ship.arrived.connect(_on_ship_arrived)
	_active_ships.append(ship)
	_ship_by_transit[ship.transit_id] = ship
	for idle_ship in _idle_ships:
		if idle_ship != null and is_instance_valid(idle_ship) and idle_ship.name == "ResearchShip_%s" % String(record.ship_id):
			_idle_ships.erase(idle_ship)
			idle_ship.queue_free()
			break
	ship.start_flight()
	ship_dispatched.emit(ship)
	return ship

func dispatch_ship(source: Planet, destination: Planet, ship_id: StringName, role: StringName = &"") -> ShipBase:
	if not _enabled or source == null or destination == null or source == destination:
		return null
	var state: Node = _game_state()
	if state == null or not state.has_ship_assembly(source.planet_id, ship_id):
		return null
	var assembly: ShipAssembly = state.get_ship_assembly(source.planet_id, ship_id)
	if assembly == null:
		return null
	var resolved_role: StringName = role
	if String(resolved_role).is_empty():
		resolved_role = assembly.role
	if resolved_role == GameState.MISSION_COLONY:
		resolved_role = &"colony"
	if resolved_role == &"colony":
		if destination.get_faction() != GameState.FACTION_NEUTRAL or not state.has_scanned_planet(source.get_faction(), destination.planet_id):
			return null
	var route_path: Array[Vector2] = _route(source, destination)
	if route_path.size() < 2:
		return null
	# Freeze the destination's current fleet before the attacker leaves. This
	# snapshot belongs to the transit, not to the eventual arrival frame.
	var defender_fleet: FleetSnapshot = _defender_fleet(destination, source.get_faction(), resolved_role)
	var fleet: FleetSnapshot = state.create_fleet_from_planet(source.planet_id, [ship_id], _part_catalog())
	if fleet == null or fleet.ships.is_empty():
		return null
	fleet.destination_planet_id = destination.planet_id
	fleet.mission_role = resolved_role
	var distance: float = PathUtils.distance(route_path)
	var duration: float = FLIGHT_TIME_SCRIPT.seconds_for_ship(distance, fleet.ships.size(), transit_config, fleet.transfer_speed_multiplier())
	var record := TransitRecord.new()
	record.transit_id = state.next_transit_id()
	record.fleet = fleet.copy()
	record.source_planet_id = source.planet_id
	record.destination_planet_id = destination.planet_id
	record.mission_role = resolved_role
	record.route_path = route_path.duplicate()
	record.duration = duration
	record.defender_fleet = defender_fleet
	state.register_transit(record)
	if state.has_method("register_persistent_fleet"):
		state.register_persistent_fleet(fleet, &"in_transit")
	var ship: ShipBase = SHIP_BASE_SCENE.instantiate() as ShipBase
	ship.name = "Ship_%s_%s" % [source.name, destination.name]
	ship.transit_id = record.transit_id
	ship.configure(fleet, destination, route_path, duration, _part_catalog(), resolved_role, source.planet_id)
	add_child(ship)
	ship.arrived.connect(_on_ship_arrived)
	_active_ships.append(ship)
	_ship_by_transit[record.transit_id] = ship
	state.ship_launched.emit(source.planet_id, ship_id, resolved_role)
	if not _check_route_engagement(record):
		ship.start_flight()
	ship_dispatched.emit(ship)
	return ship

func _check_route_engagement(record: TransitRecord) -> bool:
	if record == null or record.fleet == null or record.mission_role == &"colony":
		return false
	var state: Node = _game_state()
	if state == null or not state.has_method("get_transit_records"):
		return false
	for other in state.get_transit_records():
		var other_record: TransitRecord = other as TransitRecord
		if other_record == null or other_record.transit_id == record.transit_id:
			continue
		if other_record.status != TransitRecord.STATUS_IN_FLIGHT or other_record.fleet == null:
			continue
		if other_record.fleet.faction == record.fleet.faction:
			continue
		if other_record.mission_role == &"colony":
			continue
		var speed_a: float = other_record.fleet.speed
		var speed_b: float = record.fleet.speed
		var engagement: Dictionary = ROUTE_ENGAGEMENT_SCRIPT.detect_engagement(
			other_record.route_path,
			speed_a,
			record.route_path,
			speed_b
		)
		if engagement.is_empty() or engagement.get("type", &"") == &"destination_arrival":
			continue
		return _begin_route_battle(other_record, record, engagement)
	return false

func _begin_route_battle(first: TransitRecord, second: TransitRecord, engagement: Dictionary) -> bool:
	var state: Node = _game_state()
	if state == null or first == null or second == null:
		return false
	var seeds := _next_combat_seeds()
	var battle_id := StringName("battle_%d" % _battle_counter)
	first.status = TransitRecord.STATUS_ENGAGED
	second.status = TransitRecord.STATUS_ENGAGED
	first.battle_id = battle_id
	second.battle_id = battle_id
	state.update_transit(first)
	state.update_transit(second)
	var first_ship: ShipBase = _ship_by_transit.get(first.transit_id) as ShipBase
	var second_ship: ShipBase = _ship_by_transit.get(second.transit_id) as ShipBase
	if first_ship != null and is_instance_valid(first_ship):
		first_ship.stop_flight()
	if second_ship != null and is_instance_valid(second_ship):
		second_ship.stop_flight()
	var replay := FleetBattleSimulator.simulate_route_battle(
		first.fleet,
		second.fleet,
		first.route_path,
		second.route_path,
		engagement,
		int(seeds["battle_seed"]),
		_part_catalog()
	)
	var context := BattleContext.new()
	context.battle_id = battle_id
	context.transit_ids = [first.transit_id, second.transit_id]
	context.fleet_a = first.fleet.copy()
	context.fleet_b = second.fleet.copy()
	context.route_a = first.route_path.duplicate()
	context.route_b = second.route_path.duplicate()
	context.engagement_point = engagement.get("point", Vector2.ZERO)
	context.engagement_type = engagement.get("type", &"")
	context.engagement_time_a = float(engagement.get("time_a", 0.0))
	context.engagement_time_b = float(engagement.get("time_b", 0.0))
	context.replay = replay
	context.route_engagement = true
	var cycle: Node = get_node_or_null("/root/GameCycleManager")
	var player_involved := first.fleet.faction == GameState.FACTION_PLAYER or second.fleet.faction == GameState.FACTION_PLAYER
	if cycle != null and cycle.has_method("begin_battle"):
		cycle.call("begin_battle", context, player_involved)
		if not player_involved:
			cycle.call("apply_battle_result", context)
	elif player_involved:
		_pending_overlay_context = context
		_start_replay(&"battle", replay)
	return true

func preview_duration(source: Planet, destination: Planet, ship_id: StringName) -> float:
	var state: Node = _game_state()
	if state == null or source == null or destination == null:
		return 0.0
	var assembly: ShipAssembly = state.get_ship_assembly(source.planet_id, ship_id)
	if assembly == null:
		return 0.0
	var route_path: Array[Vector2] = _route(source, destination)
	var fleet := _fleet_preview(source, assembly)
	if fleet == null:
		return 0.0
	return FLIGHT_TIME_SCRIPT.seconds_for_ship(PathUtils.distance(route_path), fleet.ships.size(), transit_config, fleet.transfer_speed_multiplier())

func _on_ship_arrived(ship_node: Node2D) -> void:
	var ship: ShipBase = ship_node as ShipBase
	if ship == null:
		return
	ship_arrived.emit(ship)
	var state: Node = _game_state()
	var record: TransitRecord = state.get_transit(ship.transit_id) if state != null and not String(ship.transit_id).is_empty() else null
	if ship.mission_role == &"research":
		if state != null and ship.destination != null:
			state.mark_research_ship_arrived(ship.fleet.ships[0].ship_id, ship.destination.planet_id)
			if not String(ship.transit_id).is_empty():
				state.remove_transit(ship.transit_id)
		_active_ships.erase(ship)
		_ship_by_transit.erase(ship.transit_id)
		if is_instance_valid(ship):
			ship.stop_flight()
			_idle_ships.append(ship)
			ship.name = "ResearchShip_%s" % String(ship.fleet.ships[0].ship_id)
		return
	if record != null and record.status == TransitRecord.STATUS_ENGAGED:
		return
	var result: Dictionary = {}
	if ship.destination != null and is_instance_valid(ship.destination) and ship.fleet != null:
		var defender_fleet: FleetSnapshot = record.defender_fleet if record != null else _defender_fleet(ship.destination, ship.fleet.faction, ship.mission_role)
		var battle_seed: int = 0
		var conquest_seed: int = 0
		var used_grid: bool = false
		if _requires_combat(ship.destination, ship.fleet, ship.mission_role):
			var combat_seeds: Dictionary = _next_combat_seeds()
			battle_seed = int(combat_seeds["battle_seed"])
			conquest_seed = int(combat_seeds["conquest_seed"])
			if ship.destination.has_method("get_base_hp") and int(ship.destination.get_base_hp()) > 0:
				used_grid = true
				result = PlanetArrivalResolver.simulate_grid_arrival(ship.destination, ship.fleet, null, conquest_seed)
		if not used_grid:
			result = PlanetArrivalResolver.simulate_ship_arrival(ship.destination, ship.fleet, defender_fleet, battle_seed, conquest_seed, ship.mission_role)
		var replay: CombatReplay = result.get("replay") as CombatReplay
		if replay != null and replay.is_battle() and ship.fleet.faction == GameState.FACTION_PLAYER:
			var context := BattleContext.new()
			context.battle_id = StringName("battle_%d" % _battle_counter)
			context.transit_ids = [ship.transit_id]
			context.fleet_a = ship.fleet.copy()
			context.fleet_b = defender_fleet.copy() if defender_fleet != null else null
			context.route_a = record.route_path if record != null else ship.route_path()
			context.route_b = [ship.destination.global_position, ship.destination.global_position]
			context.engagement_point = ship.destination.global_position
			context.engagement_type = &"destination_arrival"
			context.replay = replay
			context.route_engagement = false
			if record != null:
				record.status = TransitRecord.STATUS_ENGAGED
				record.battle_id = context.battle_id
				state.update_transit(record)
			var cycle: Node = get_node_or_null("/root/GameCycleManager")
			if cycle != null and cycle.has_method("begin_battle"):
				cycle.call("begin_battle", context, true)
			_active_ships.erase(ship)
			_ship_by_transit.erase(ship.transit_id)
			ship.stop_flight()
			ship.queue_free()
			return
		PlanetArrivalResolver.commit_ship_arrival(ship.destination, ship.fleet, result, ship.fleet.faction != GameState.FACTION_CPU)
		if used_grid:
			_maybe_show_capture_decision(ship.destination, ship.fleet, result)
		ship.destination.show_arrival_feedback(int(result.get("surviving_attackers", 0)), ship.fleet.faction)
	var ship_id: StringName = &""
	if ship.fleet != null and not ship.fleet.ships.is_empty():
		ship_id = ship.fleet.ships[0].ship_id
	var outcome: StringName = result.get("result", Planet.ARRIVAL_REJECTED) as StringName
	var surviving_fleet: FleetSnapshot = ship.fleet.copy() if ship.fleet != null else null
	var replay_result: CombatReplay = result.get("replay") as CombatReplay
	if outcome == Planet.ARRIVAL_REPELLED and replay_result != null and replay_result.is_battle():
		surviving_fleet.ships = replay_result.survivors_a.duplicate()
		surviving_fleet.calculate_stats(_part_catalog())
	if state != null:
		if outcome == Planet.ARRIVAL_SETTLED and ship.mission_role == &"colony":
			state.mark_milestone(ship.fleet.faction, &"first_colony")
		if outcome == Planet.ARRIVAL_SETTLED or outcome == Planet.ARRIVAL_CAPTURED or outcome == Planet.ARRIVAL_FRIENDLY:
			if surviving_fleet != null:
				state.disband_fleet_to_planet(surviving_fleet, ship.destination.planet_id)
				state.mark_persistent_ship_arrived(ship_id, ship.destination.planet_id)
		elif outcome == Planet.ARRIVAL_REPELLED:
			if surviving_fleet != null and not surviving_fleet.ships.is_empty():
				var return_planet: Planet = _find_planet(ship.source_planet_id)
				if return_planet != null:
					state.disband_fleet_to_planet(surviving_fleet, return_planet.planet_id)
					state.mark_persistent_ship_arrived(ship_id, return_planet.planet_id)
			else:
				state.mark_persistent_ship_lost(ship_id)
		elif outcome == Planet.ARRIVAL_REJECTED:
			var rejected_source: Planet = _find_planet(ship.source_planet_id)
			if rejected_source != null and surviving_fleet != null:
				state.disband_fleet_to_planet(surviving_fleet, rejected_source.planet_id)
				state.mark_persistent_ship_arrived(ship_id, rejected_source.planet_id)
		if not String(ship.transit_id).is_empty():
			state.remove_transit(ship.transit_id)
	_active_ships.erase(ship)
	_ship_by_transit.erase(ship.transit_id)
	if is_instance_valid(ship):
		ship.queue_free()

func _maybe_show_capture_decision(destination: Planet, fleet: FleetSnapshot, result: Dictionary) -> void:
	var outcome: StringName = result.get("result", Planet.ARRIVAL_REJECTED) as StringName
	if outcome != Planet.ARRIVAL_CAPTURED or destination == null or fleet == null:
		return
	if fleet.faction != GameState.FACTION_PLAYER:
		return
	var overlay := CaptureDecisionOverlay.new()
	overlay.name = "CaptureDecisionOverlay"
	add_child(overlay)
	overlay.capture_decision_made.connect(Callable(self, "_on_capture_decision_made").bind(destination, fleet.faction, overlay))
	overlay.present(destination)

func _on_capture_decision_made(decision: StringName, destination: Planet, faction: StringName, overlay: CaptureDecisionOverlay) -> void:
	PlanetArrivalResolver.commit_capture_decision(destination, decision, faction)
	if overlay != null and is_instance_valid(overlay):
		overlay.queue_free()

func _defender_fleet(destination: Planet, attacking_faction: StringName, mission_role: StringName) -> FleetSnapshot:
	if destination == null or mission_role == &"colony" or destination.get_faction() == attacking_faction:
		return null
	var state: Node = _game_state()
	if state == null or not state.has_method("preview_fleet_from_planet"):
		return null
	var assemblies: Dictionary = state.get_ship_assemblies(destination.planet_id)
	if assemblies.is_empty():
		return null
	return state.preview_fleet_from_planet(destination.planet_id, assemblies.keys(), _part_catalog())

func get_active_ships() -> Array[ShipBase]:
	var result: Array[ShipBase] = []
	for ship in _active_ships:
		if ship != null and is_instance_valid(ship):
			result.append(ship)
	return result

func get_idle_ships() -> Array[ShipBase]:
	var result: Array[ShipBase] = []
	for ship in _idle_ships:
		if ship != null and is_instance_valid(ship):
			result.append(ship)
	return result

func _on_catalog_reset(_catalog: PlanetCatalog) -> void:
	for ship in _active_ships:
		if is_instance_valid(ship):
			ship.queue_free()
	for ship in _idle_ships:
		if is_instance_valid(ship):
			ship.queue_free()
	_active_ships.clear()
	_idle_ships.clear()
	_ship_by_transit.clear()
	_game_seed = _resolve_game_seed(_field)
	_battle_counter = 0
	_connect_planet_conflicts()

func _route(source: Planet, destination: Planet) -> Array[Vector2]:
	if _navigation != null and is_instance_valid(_navigation):
		return _navigation.find_route(source, destination)
	return [source.global_position, destination.global_position]

func _fleet_preview(source: Planet, assembly: ShipAssembly) -> FleetSnapshot:
	var fleet := FleetSnapshot.new()
	fleet.faction = source.get_faction()
	fleet.source_planet_id = source.planet_id
	fleet.ships = [assembly.copy()]
	fleet.calculate_stats(_part_catalog())
	return fleet

func _part_catalog() -> ShipPartCatalog:
	if _ship_manager != null and _ship_manager.has_method("get_part_catalog"):
		return _ship_manager.get_part_catalog()
	return preload("res://resources/config/ship_part_catalog_default.tres")

func _prune_active_ships() -> void:
	var alive: Array[ShipBase] = []
	for ship in _active_ships:
		if is_instance_valid(ship):
			alive.append(ship)
	_active_ships = alive

func _game_state() -> Node:
	return GameStateAccess.autoload(self)
