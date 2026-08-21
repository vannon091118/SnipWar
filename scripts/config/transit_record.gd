@tool
class_name TransitRecord
extends Resource

const STATUS_IN_FLIGHT: StringName = &"in_flight"
const STATUS_ENGAGED: StringName = &"engaged"
const STATUS_ARRIVED: StringName = &"arrived"
const STATUS_RESOLVED: StringName = &"resolved"
const STATUS_CANCELLED: StringName = &"cancelled"

@export var transit_id: StringName = &""
@export var fleet: FleetSnapshot
@export var source_planet_id: StringName = &""
@export var destination_planet_id: StringName = &""
@export var mission_role: StringName = &""
@export var route_path: Array[Vector2] = []
@export var duration: float = 0.0
@export var elapsed: float = 0.0
@export var status: StringName = STATUS_IN_FLIGHT
@export var defender_fleet: FleetSnapshot
@export var battle_id: StringName = &""

func copy() -> TransitRecord:
	return duplicate(true) as TransitRecord

func progress() -> float:
	if duration <= 0.0:
		return 1.0
	return clampf(elapsed / duration, 0.0, 1.0)

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(transit_id).is_empty():
		errors.append("transit record id is empty")
	if fleet == null or fleet.ships.is_empty():
		errors.append("transit record fleet is empty")
	if route_path.size() < 2:
		errors.append("transit record route must contain at least two points")
	if duration <= 0.0:
		errors.append("transit record duration must be positive")
	if elapsed < 0.0 or elapsed > duration + 0.001:
		errors.append("transit record elapsed time is outside its duration")
	return errors
