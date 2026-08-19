class_name CpuDispatchAI
extends Node

const DEFAULT_CONFIG: CpuDispatchConfig = preload("res://resources/config/cpu_dispatch_default.tres")

@export var dispatch_config: CpuDispatchConfig = DEFAULT_CONFIG

var _field: Node
var _network: Node
var _worker_manager: Node
var _timer: Timer
var _enabled: bool = false

func configure(field: Node, network: Node, worker_manager: Node, config: CpuDispatchConfig = null) -> void:
	_field = field
	_network = network
	_worker_manager = worker_manager
	if config != null:
		dispatch_config = config

func _ready() -> void:
	if Engine.is_editor_hint():
		return
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
	return false

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
