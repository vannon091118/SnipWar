class_name PlanetEconomyManager
extends Node

const DEFAULT_CONFIG: EconomyConfig = preload("res://resources/config/economy_default.tres")

@export var economy_config: EconomyConfig = DEFAULT_CONFIG

var _timer: Timer
var _gather_timer: Timer
var _enabled: bool = false
var _gathering_enabled: bool = true
var _manual_override: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var resolved_config: EconomyConfig = economy_config if economy_config != null else DEFAULT_CONFIG
	_timer = Timer.new()
	_timer.name = "EconomyTimer"
	_timer.wait_time = resolved_config.tick_interval
	_timer.one_shot = false
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	var state: Node = _game_state()
	if state != null and state.has_signal("technology_researched"):
		state.technology_researched.connect(_on_technology_researched)
	if state != null and state.has_signal("catalog_reset"):
		state.catalog_reset.connect(_on_catalog_reset)
	_enabled = _has_worker_automation()
	_timer.paused = not _enabled
	if _enabled:
		_timer.start()
	_gather_timer = Timer.new()
	_gather_timer.name = "GatherTimer"
	_gather_timer.wait_time = resolved_config.tick_interval
	_gather_timer.one_shot = false
	_gather_timer.timeout.connect(_on_gather_tick)
	add_child(_gather_timer)
	_gather_timer.start()

func set_enabled(enabled: bool) -> void:
	_manual_override = true
	_enabled = enabled
	if _timer == null:
		return
	_timer.paused = not enabled
	if enabled and _timer.is_stopped():
		_timer.start()

func is_enabled() -> bool:
	return _enabled

func economy_tick_remaining() -> float:
	if _timer == null or _timer.is_stopped() or _timer.paused:
		return -1.0
	return _timer.time_left

func economy_tick_interval() -> float:
	if _timer != null and _timer.wait_time > 0.0:
		return _timer.wait_time
	var resolved_config: EconomyConfig = economy_config if economy_config != null else DEFAULT_CONFIG
	return resolved_config.tick_interval

func set_gathering_enabled(enabled: bool) -> void:
	_gathering_enabled = enabled
	if _gather_timer != null:
		_gather_timer.paused = not enabled

func is_gathering_enabled() -> bool:
	return _gathering_enabled

func tick_now() -> int:
	return _tick_economy()

func _tick_economy() -> int:
	var field: Node = get_parent()
	if field == null:
		return 0
	var state: Node = _game_state()
	var generated_total: int = 0
	var automation_researched: bool = _has_worker_automation()
	# Snapshot the children list to avoid iterating over a mutating child set
	# during chunk cycling (queue_free + add_child in the same frame).
	var snapshot: Array = field.get_children().duplicate()
	for child in snapshot:
		if not is_instance_valid(child):
			continue
		var planet: Planet = child as Planet
		if planet != null:
			generated_total += planet.generate_economy_resources()
			if automation_researched and state != null and state.has_method("convert_refinery_resources"):
				if state.has_planet_upgrade(planet.planet_id, &"refinery"):
					state.convert_refinery_resources(planet.planet_id)
	if state != null and state.has_method("tick_trade_routes"):
		state.tick_trade_routes()
	return generated_total

func gather_now() -> int:
	var state: Node = _game_state()
	if state == null:
		return 0
	var field: Node = get_parent()
	if field == null:
		return 0
	var base_amounts: Dictionary = {}
	var snapshot: Array = field.get_children().duplicate()
	for child in snapshot:
		if not is_instance_valid(child):
			continue
		var planet: Planet = child as Planet
		if planet != null:
			base_amounts[planet.planet_id] = planet.get_size_profile().resource_base
	return int(state.gather_income_tick(base_amounts))

func _on_tick() -> void:
	if _enabled:
		_tick_economy()

func _on_gather_tick() -> void:
	if _gathering_enabled:
		gather_now()

func _on_technology_researched(_faction: StringName, _technology_id: StringName) -> void:
	if _manual_override:
		return
	set_enabled(_has_worker_automation())
	_manual_override = false

func _on_catalog_reset(_catalog: PlanetCatalog) -> void:
	_manual_override = false
	set_enabled(_has_worker_automation())
	_manual_override = false

func _has_worker_automation() -> bool:
	var state: Node = _game_state()
	return state != null and (state.has_technology(GameState.FACTION_PLAYER, GameState.TECH_WORKER_AUTOMATION) or state.has_technology(GameState.FACTION_CPU, GameState.TECH_WORKER_AUTOMATION))

func _game_state() -> Node:
	return GameStateAccess.autoload(self)
