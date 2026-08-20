@tool
class_name BattleEvent
extends Resource

const TYPE_SPAWN: StringName = &"spawn"
const TYPE_FIRE: StringName = &"fire"
const TYPE_HIT: StringName = &"hit"
const TYPE_DESTROYED: StringName = &"destroyed"
const TYPE_RETREAT: StringName = &"retreat"

@export var timestamp: float = 0.0
@export var event_type: StringName = TYPE_SPAWN
@export var source_id: StringName = &""
@export var target_id: StringName = &""
@export var value: float = 0.0
@export var source_pos: Vector2 = Vector2.ZERO
@export var target_pos: Vector2 = Vector2.ZERO
## Immutable loadout snapshot for TYPE_SPAWN replay events. Other event types leave
## this empty, keeping the event contract compact while preserving full visuals.
@export var ship_data: Dictionary = {}


static func create(
	time: float,
	type: StringName,
	src: StringName,
	tgt: StringName,
	val: float = 0.0,
	src_p: Vector2 = Vector2.ZERO,
	tgt_p: Vector2 = Vector2.ZERO,
	spawn_ship_data: Dictionary = {}
) -> BattleEvent:
	var event := BattleEvent.new()
	event.timestamp = time
	event.event_type = type
	event.source_id = src
	event.target_id = tgt
	event.value = val
	event.source_pos = src_p
	event.target_pos = tgt_p
	event.ship_data = spawn_ship_data.duplicate(true)
	return event


func to_dictionary() -> Dictionary:
	return {
		"timestamp": timestamp,
		"event_type": event_type,
		"source_id": source_id,
		"target_id": target_id,
		"value": value,
		"source_pos": source_pos,
		"target_pos": target_pos,
		"ship_data": ship_data.duplicate(true),
	}


static func from_dictionary(source: Dictionary) -> BattleEvent:
	var event := BattleEvent.new()
	event.timestamp = float(source.get("timestamp", 0.0))
	event.event_type = _string_name(source.get("event_type", TYPE_SPAWN), TYPE_SPAWN)
	event.source_id = _string_name(source.get("source_id", &""))
	event.target_id = _string_name(source.get("target_id", &""))
	event.value = float(source.get("value", 0.0))
	event.source_pos = source.get("source_pos", Vector2.ZERO) as Vector2
	event.target_pos = source.get("target_pos", Vector2.ZERO) as Vector2
	var raw_ship_data: Variant = source.get("ship_data", {})
	if raw_ship_data is Dictionary:
		event.ship_data = (raw_ship_data as Dictionary).duplicate(true)
	return event


static func _string_name(value: Variant, fallback: StringName = &"") -> StringName:
	if value is StringName:
		return value as StringName
	if value is String and not (value as String).is_empty():
		return StringName(value as String)
	return fallback
