@tool
class_name BattleEvent
extends Resource

const TYPE_SPAWN: StringName = &"spawn"
const TYPE_FIRE: StringName = &"fire"
const TYPE_HIT: StringName = &"hit"
const TYPE_DESTROYED: StringName = &"destroyed"
const TYPE_RETREAT: StringName = &"retreat"
const TYPE_WAVE_START: StringName = &"wave_start"
const TYPE_MINION_SPAWN: StringName = &"minion_spawn"
const TYPE_TOWER_FIRE: StringName = &"tower_fire"
const TYPE_BASE_DAMAGE: StringName = &"base_damage"
const TYPE_WAVE_CLEARED: StringName = &"wave_cleared"
## Module-based damage model events.
const TYPE_MOVE: StringName = &"move"
const TYPE_MODULE_HIT: StringName = &"module_hit"
const TYPE_MODULE_DESTROYED: StringName = &"module_destroyed"
const TYPE_REPAIR: StringName = &"repair"

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

@export_group("Module Damage")
## Identifies the module a TYPE_MODULE_HIT / TYPE_MODULE_DESTROYED refers to.
@export var module_part_id: StringName = &""
@export var module_slot_type: StringName = &""
@export var module_trait: StringName = &""


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


static func create_module(
	time: float,
	type: StringName,
	src: StringName,
	tgt: StringName,
	val: float,
	mod_part_id: StringName,
	mod_slot_type: StringName,
	mod_trait: StringName,
	src_p: Vector2 = Vector2.ZERO,
	tgt_p: Vector2 = Vector2.ZERO
) -> BattleEvent:
	var event := create(time, type, src, tgt, val, src_p, tgt_p)
	event.module_part_id = mod_part_id
	event.module_slot_type = mod_slot_type
	event.module_trait = mod_trait
	return event
