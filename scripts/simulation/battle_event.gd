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
## Immutable typed assembly snapshot for TYPE_SPAWN replay events. Other event
## types leave this null, keeping the event contract compact while preserving
## full visuals.
@export var ship_data: ShipAssembly


static func create(
	time: float,
	type: StringName,
	src: StringName,
	tgt: StringName,
	val: float = 0.0,
	src_p: Vector2 = Vector2.ZERO,
	tgt_p: Vector2 = Vector2.ZERO,
	spawn_ship_data: ShipAssembly = null
) -> BattleEvent:
	var event := BattleEvent.new()
	event.timestamp = time
	event.event_type = type
	event.source_id = src
	event.target_id = tgt
	event.value = val
	event.source_pos = src_p
	event.target_pos = tgt_p
	event.ship_data = spawn_ship_data.copy() if spawn_ship_data != null else null
	return event
