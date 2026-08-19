class_name PlanetEconomyManager
extends Node

const DEFAULT_CONFIG: EconomyConfig = preload("res://resources/config/economy_default.tres")

@export var economy_config: EconomyConfig = DEFAULT_CONFIG

var _timer: Timer
var _enabled: bool = false

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
	_enabled = true
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
