@tool
class_name BattleEvent
extends RefCounted

const TYPE_SPAWN := &"spawn"
const TYPE_FIRE := &"fire"
const TYPE_HIT := &"hit"
const TYPE_DESTROYED := &"destroyed"
const TYPE_RETREAT := &"retreat"

var timestamp: float = 0.0
var event_type: StringName = TYPE_SPAWN
var source_id: StringName = &""
var target_id: StringName = &""
var value: float = 0.0
var source_pos: Vector2 = Vector2.ZERO
var target_pos: Vector2 = Vector2.ZERO

static func create(time: float, type: StringName, src: StringName, tgt: StringName, val: float = 0.0, src_p: Vector2 = Vector2.ZERO, tgt_p: Vector2 = Vector2.ZERO) -> BattleEvent:
	var event := BattleEvent.new()
	event.timestamp = time
	event.event_type = type
	event.source_id = src
	event.target_id = tgt
	event.value = val
	event.source_pos = src_p
	event.target_pos = tgt_p
	return event
