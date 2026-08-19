class_name PlanetEconomyManager
extends Node

const DEFAULT_CONFIG: EconomyConfig = preload("res://resources/config/economy_default.tres")

@export var economy_config: EconomyConfig = DEFAULT_CONFIG

var _timer: Timer
var _enabled: bool = false
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

func tick_now() -> int:
	var field: Node = get_parent()
	if field == null:
		return 0
	var generated_total: int = 0
	for child in field.get_children():
		var planet: Planet = child as Planet
		if planet != null:
			generated_total += planet.generate_economy_resources()
	return generated_total

func _on_tick() -> void:
	if _enabled:
		tick_now()

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
