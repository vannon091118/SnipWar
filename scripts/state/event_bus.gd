class_name GameEventBus
extends Node

## Unified Game Event Bus for SnipWar.
## Provides a centralized decoupled event stream for game systems, UI, MCP, and EventLog.

signal game_event(type: StringName, data: Dictionary)

var _subscribers: Dictionary = {}

func emit_event(type: StringName, data: Dictionary = {}) -> void:
	game_event.emit(type, data)
	if _subscribers.has(type):
		var list: Array = _subscribers[type]
		for cb: Callable in list:
			if cb.is_valid():
				cb.call(data)

func subscribe(type: StringName, callable: Callable) -> void:
	if not _subscribers.has(type):
		_subscribers[type] = []
	var list: Array = _subscribers[type]
	if not list.has(callable):
		list.append(callable)

func unsubscribe(type: StringName, callable: Callable) -> void:
	if _subscribers.has(type):
		var list: Array = _subscribers[type]
		list.erase(callable)
		if list.is_empty():
			_subscribers.erase(type)

func clear_subscribers() -> void:
	_subscribers.clear()
