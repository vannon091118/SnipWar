@tool
class_name BattleContext
extends Resource

@export var battle_id: StringName = &""
@export var transit_ids: Array[StringName] = []
@export var fleet_a: FleetSnapshot
@export var fleet_b: FleetSnapshot
@export var route_a: Array[Vector2] = []
@export var route_b: Array[Vector2] = []
@export var engagement_point: Vector2 = Vector2.ZERO
@export var engagement_type: StringName = &""
@export var engagement_time_a: float = 0.0
@export var engagement_time_b: float = 0.0
@export var replay: CombatReplay
@export var return_scene_path: String = "res://scenes/backgrounds/starfield_background.tscn"
@export var committed: bool = false
@export var route_engagement: bool = false

func copy() -> BattleContext:
	return duplicate(true) as BattleContext

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(battle_id).is_empty():
		errors.append("battle context id is empty")
	if fleet_a == null or fleet_a.ships.is_empty():
		errors.append("battle context attacker fleet is empty")
	if fleet_b == null or fleet_b.ships.is_empty():
		errors.append("battle context defender fleet is empty")
	if route_a.size() < 2 or route_b.size() < 2:
		errors.append("battle context routes must contain at least two points")
	if replay == null or not replay.is_battle():
		errors.append("battle context replay is missing or not a battle")
	return errors
