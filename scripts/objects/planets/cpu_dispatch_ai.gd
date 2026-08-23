class_name CpuDispatchAI
extends Node

const DEFAULT_CONFIG: CpuDispatchConfig = preload("res://resources/config/cpu_dispatch_default.tres")
const DEFAULT_TECHNOLOGY_CATALOG: TechnologyCatalog = preload("res://resources/config/technology_catalog_default.tres")

## CPU tech progression: the opponent researches ship construction first and
## then works toward the drone branches, so its ship loadouts evolve from
## bare hulls to twin-drive drone ships over the course of a run.
const CPU_RESEARCH_PRIORITY: Array[StringName] = [
	&"shipyard_construction",
	&"scout_hull",
	&"scanner_drone",
	&"weapon_systems",
	&"repair_drone_t1",
	&"combat_drone_t1",
	&"drone_booster_t1",
]

@export var dispatch_config: CpuDispatchConfig = DEFAULT_CONFIG

var _field: Node
var _network: Node
var _worker_manager: Node
var _timer: Timer
var _enabled: bool = false
var _ship_rng := RandomNumberGenerator.new()

func configure(field: Node, network: Node, worker_manager: Node, config: CpuDispatchConfig = null) -> void:
	_field = field
	_network = network
	_worker_manager = worker_manager
	if config != null:
		dispatch_config = config

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_ship_rng.seed = 4242
	var resolved_config: CpuDispatchConfig = dispatch_config if dispatch_config != null else DEFAULT_CONFIG
	_timer = Timer.new()
	_timer.name = "CpuDecisionTimer"
	_timer.wait_time = resolved_config.decision_interval
	_timer.one_shot = false
	_timer.timeout.connect(_on_decision_timer)
	add_child(_timer)
	_enabled = resolved_config.enabled
	if _enabled:
		_timer.start()

func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if _timer == null:
		return
	_timer.paused = not enabled
	if enabled and _timer.is_stopped():
		_timer.start()

func is_enabled() -> bool:
	return _enabled

func dispatch_once(force: bool = false) -> bool:
	if not force and not _enabled:
		return false
	if _field == null or _network == null or _worker_manager == null:
		return false
	var resolved_config: CpuDispatchConfig = dispatch_config if dispatch_config != null else DEFAULT_CONFIG
	# Research driver: the CPU spends idle ticks advancing its tech queue so
	# it can eventually build ships (worker missions keep priority below).
	_advance_cpu_research(resolved_config)
	for child in _field.get_children():
		var source: Planet = child as Planet
		if source == null or source.get_faction() != GameState.FACTION_CPU:
			continue
		if source.worker_count < resolved_config.minimum_source_workers:
			continue
		var available: int = source.worker_count - resolved_config.reserve_workers
		if available <= 0:
			continue
		var destinations := _route_destinations(source)
		var action: Dictionary = _select_action(source, destinations)
		var target: Planet = action.get("target") as Planet
		if target == null:
			continue
		var mission_type: StringName = action.get("mission", GameState.MISSION_MILITARY) as StringName
		var amount: int = mini(available, maxi(1, int(floor(float(available) * resolved_config.dispatch_fraction))))
		var route_path: Array[Vector2] = _route_path(source, target)
		_worker_manager.call("dispatch_mission", source, target, amount, route_path, mission_type)
		return true
	# No worker action anywhere: try the ship path on an eligible CPU planet.
	for child in _field.get_children():
		var source: Planet = child as Planet
		if source == null or source.get_faction() != GameState.FACTION_CPU:
			continue
		if _maybe_build_and_dispatch_ship(source, resolved_config):
			return true
	return false

## Advances the CPU's current research job by one decision interval without
## touching other factions' jobs (see GameState.advance_research_faction).
func _advance_cpu_research(config: CpuDispatchConfig) -> void:
	var state := _game_state()
	if state == null or config == null:
		return
	var researched: Array = state.get_researched_technologies(GameState.FACTION_CPU)
	var current: StringName = &""
	var tech_catalog: TechnologyCatalog = _technology_catalog()
	# Skip techs whose prerequisites are not met yet so the queue never stalls;
	# the priority list itself covers the ship line (scout_hull → scanner_drone).
	for tech_id in CPU_RESEARCH_PRIORITY:
		if researched.has(tech_id) or state.research_in_progress(GameState.FACTION_CPU, tech_id):
			continue
		if state.can_research_technology(GameState.FACTION_CPU, tech_id, tech_catalog):
			current = tech_id
			break
	if String(current).is_empty():
		return
	state.research_technology(GameState.FACTION_CPU, current, tech_catalog)
	state.advance_research_faction(GameState.FACTION_CPU, config.decision_interval)

## Builds one module-model-aware ship loadout (CpuLoadoutBuilder) on a CPU
## planet with a researched shipyard and dispatches it. Returns true when a
## ship actually launched.
func _maybe_build_and_dispatch_ship(source: Planet, config: CpuDispatchConfig) -> bool:
	if source == null or config == null or source.get_faction() != GameState.FACTION_CPU:
		return false
	if source.worker_count < config.minimum_source_workers:
		return false
	var state := _game_state()
	var ship_manager: Node = _field.get_node_or_null("ShipManager") if _field != null else null
	var conflict_manager: Node = _field.get_node_or_null("ConflictManager") if _field != null else null
	if state == null or ship_manager == null or conflict_manager == null:
		return false
	if not state.has_technology(GameState.FACTION_CPU, &"shipyard_construction"):
		return false
	var catalog: ShipPartCatalog = ship_manager.get_part_catalog()

	# 1. Dispatch a completed ship that is waiting in the hangar. The build
	#    job finishes via GameState._process() (live) or advance_builds() (test).
	var assemblies: Dictionary = state.get_ship_assemblies(source.planet_id)
	for ship_id_value in assemblies:
		var ship_id: StringName = ship_id_value as StringName
		var assembly: ShipAssembly = state.get_ship_assembly(source.planet_id, ship_id)
		if assembly == null:
			continue
		var target: Planet = _ship_target(source)
		if target == null:
			return false
		var role: StringName = assembly.role if not String(assembly.role).is_empty() else GameState.MISSION_MILITARY
		if target.get_faction() == GameState.FACTION_NEUTRAL:
			role = GameState.MISSION_COLONY if state.has_scanned_planet(GameState.FACTION_CPU, target.planet_id) else GameState.MISSION_MILITARY
		var ship: Node = conflict_manager.call("dispatch_ship", source, target, ship_id, role) as Node
		if ship != null:
			return true

	# 2. Wait while a ship build job is running (one ship at a time per planet).
	if not state.get_ship_build_jobs(source.planet_id).is_empty():
		return false

	# 3. The assembly path requires the orbital shipyard upgrade; buy it once.
	if not state.has_planet_upgrade(source.planet_id, &"shipyard"):
		if not state.can_purchase_upgrade(source.planet_id, &"shipyard", null, source.worker_count):
			return false
		state.purchase_upgrade(source.planet_id, &"shipyard", null, source.worker_count)
		return false

	# 4. Build a module-model-aware ship for the best available target.
	var researched: Array = state.get_researched_technologies(GameState.FACTION_CPU)
	var target: Planet = _ship_target(source)
	if target == null:
		return false
	var role: StringName = GameState.MISSION_COLONY if target.get_faction() == GameState.FACTION_NEUTRAL else GameState.MISSION_MILITARY
	var loadout: Dictionary = CpuLoadoutBuilder.build_loadout(catalog, researched, _ship_rng, role)
	if loadout.is_empty():
		return false
	var part_ids: Array[StringName] = [loadout.get("hull_id", &""), loadout.get("drive_id", &""), loadout.get("shield_id", &""), loadout.get("scanner_id", &""), loadout.get("weapon_id", &"")]
	part_ids.append_array(loadout.get("module_ids", []))
	var seen := {}
	for part_id in part_ids:
		if String(part_id).is_empty() or seen.has(part_id):
			continue
		seen[part_id] = true
		if not ship_manager.buy_part(source, part_id):
			return false
	var ship_id: StringName = ship_manager.assemble_ship(
		source,
		loadout.get("hull_id", &""),
		loadout.get("scanner_id", &""),
		loadout.get("module_ids", []),
		loadout.get("weapon_id", &""),
		loadout.get("drive_id", &""),
		loadout.get("shield_id", &""),
		&"",
		-1,
		role
	) as StringName
	# The ship enters a build job (build_time > 0); it dispatches once the job
	# completes and step 1 picks it up. A non-empty id means the build started.
	return not String(ship_id).is_empty()

## Colony ships need a scanned neutral planet; the CPU never scouts, so it
## defaults to military strikes against the closest non-CPU planet.
func _ship_target(source: Planet) -> Planet:
	var state := _game_state()
	var destinations := _route_destinations(source)
	if state != null:
		for candidate in destinations:
			var planet: Planet = candidate as Planet
			if planet != null and planet.get_faction() == GameState.FACTION_NEUTRAL and state.has_scanned_planet(GameState.FACTION_CPU, planet.planet_id):
				return planet
	return _closest_enemy(source, destinations)

func _game_state() -> Node:
	return GameStateAccess.autoload(self)

func _technology_catalog() -> TechnologyCatalog:
	var ship_manager: Node = _field.get_node_or_null("ShipManager") if _field != null else null
	if ship_manager != null and ship_manager.has_method("get_technology_catalog"):
		return ship_manager.get_technology_catalog() as TechnologyCatalog
	return DEFAULT_TECHNOLOGY_CATALOG

func _on_decision_timer() -> void:
	if _enabled:
		dispatch_once()
		var resolved_config: CpuDispatchConfig = dispatch_config if dispatch_config != null else DEFAULT_CONFIG
		if _timer != null and resolved_config != null:
			var current_wait := _timer.wait_time
			var target_min := resolved_config.min_decision_interval
			if current_wait > target_min:
				_timer.wait_time = maxf(target_min, current_wait * (1.0 - resolved_config.pacing_decay_rate))

func _route_destinations(source: Planet) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var raw_destinations: Variant = _network.call("get_route_destinations", source)
	if not raw_destinations is Array:
		return result
	for candidate in raw_destinations:
		if candidate is Node2D and is_instance_valid(candidate):
			result.append(candidate as Node2D)
	return result

func _route_path(source: Planet, target: Planet) -> Array[Vector2]:
	var raw_path: Variant = _network.call("get_route_path", source, target)
	if raw_path is Array:
		var result: Array[Vector2] = []
		for point in raw_path:
			if point is Vector2:
				result.append(point as Vector2)
		return result
	return [source.global_position, target.global_position]

func _select_action(source: Planet, destinations: Array[Node2D]) -> Dictionary:
	var neutral_target: Planet = _closest_neutral(source, destinations)
	if neutral_target != null:
		return {"target": neutral_target, "mission": GameState.MISSION_COLONY}
	var reinforcement_target: Planet = _closest_weak_cpu_planet(source, destinations)
	if reinforcement_target != null:
		return {"target": reinforcement_target, "mission": GameState.MISSION_CARGO}
	var enemy_target: Planet = _closest_enemy(source, destinations)
	if enemy_target != null:
		return {"target": enemy_target, "mission": GameState.MISSION_MILITARY}
	return {}

func _closest_neutral(source: Planet, destinations: Array[Node2D]) -> Planet:
	var best: Planet
	var best_distance: float = INF
	for candidate in destinations:
		var planet: Planet = candidate as Planet
		if planet == null or planet.get_faction() != GameState.FACTION_NEUTRAL:
			continue
		var distance: float = source.global_position.distance_to(planet.global_position)
		if distance < best_distance:
			best = planet
			best_distance = distance
	return best

func _closest_weak_cpu_planet(source: Planet, destinations: Array[Node2D]) -> Planet:
	var best: Planet
	var best_distance: float = INF
	for candidate in destinations:
		var planet: Planet = candidate as Planet
		if planet == null or planet.get_faction() != GameState.FACTION_CPU or planet.worker_count >= source.worker_count:
			continue
		var distance: float = source.global_position.distance_to(planet.global_position)
		if distance < best_distance:
			best = planet
			best_distance = distance
	return best

func _closest_enemy(source: Planet, destinations: Array[Node2D]) -> Planet:
	var best: Planet
	var best_distance: float = INF
	for candidate in destinations:
		var planet: Planet = candidate as Planet
		if planet == null or planet.get_faction() == GameState.FACTION_CPU:
			continue
		var distance: float = source.global_position.distance_to(planet.global_position)
		if distance < best_distance:
			best = planet
			best_distance = distance
	return best
