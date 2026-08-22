extends Node2D

class_name WorkerCluster

const DEFAULT_CONFIG: TransitConfig = preload("res://resources/config/transit_default.tres")

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _attachments: Node2D = $Attachments

const ARRIVAL_FRIENDLY := &"friendly"
const ARRIVAL_REPELLED := &"repelled"
const ARRIVAL_CAPTURED := &"captured"
const ARRIVAL_REJECTED := &"rejected"
const ARRIVAL_SETTLED := &"settled"
const ARRIVAL_COLLECTED := &"collected"

var unit_count := 1
var source_faction: StringName = &"neutral"
var source_planet_id: StringName = &""
var destination_planet: Planet
var transit_config: TransitConfig = DEFAULT_CONFIG
var mission_type: StringName = &"military"
var cluster_tier_bonus: int = 0
var arrival_result: StringName = ARRIVAL_REJECTED
enum TransitPhase { OUTBOUND, LOADING, RETURNING, DELIVERED }
var phase: TransitPhase = TransitPhase.OUTBOUND
var cargo_amount: int = 0
var cargo_resource_id: StringName = &""
var _return_path: Array[Vector2] = []
var _return_duration: float = 0.0

func _ready() -> void:
	_apply_visuals()

func configure_transit(source_position: Vector2, destination: Planet, amount: int, faction: StringName, config: TransitConfig = null, mission: StringName = &"military", tier_bonus: int = 0, source_id: StringName = &"") -> void:
	global_position = source_position
	destination_planet = destination
	unit_count = amount
	source_faction = faction
	transit_config = config if config != null else DEFAULT_CONFIG
	mission_type = mission
	cluster_tier_bonus = maxi(tier_bonus, 0)
	source_planet_id = source_id
	arrival_result = ARRIVAL_REJECTED
	phase = TransitPhase.OUTBOUND
	cargo_amount = 0
	cargo_resource_id = &""
	_return_path.clear()
	_return_duration = 0.0
	_apply_visuals()

func get_unit_count() -> int:
	return unit_count

func configure_roundtrip(route_path: Array[Vector2], duration: float) -> void:
	_return_path = route_path.duplicate()
	_return_path.reverse()
	_return_duration = maxf(duration, 0.001)

func set_cargo(resource_id: StringName, amount: int) -> void:
	cargo_resource_id = resource_id
	cargo_amount = maxi(amount, 0)
	phase = TransitPhase.LOADING

func begin_return() -> void:
	phase = TransitPhase.RETURNING
	global_position = _return_path[0] if not _return_path.is_empty() else global_position

func mark_delivered() -> void:
	phase = TransitPhase.DELIVERED

func attach_object(object: Node2D, offset := Vector2.ZERO) -> void:
	_attachments.add_child(object)
	object.position = offset

func _arrive() -> StringName:
	if mission_type == GameState.MISSION_COLLECT:
		phase = TransitPhase.LOADING
		return ARRIVAL_COLLECTED
	if is_instance_valid(destination_planet):
		arrival_result = destination_planet.resolve_mission(source_faction, unit_count, mission_type, source_planet_id)
		_spawn_arrival_feedback()
	else:
		arrival_result = ARRIVAL_REJECTED
	destination_planet = null
	queue_free()
	return arrival_result

## Pops a "+N" label above the destination for outcomes that land workers,
## delegating the spawn to Planet.show_arrival_feedback.
func _spawn_arrival_feedback() -> void:
	if arrival_result != ARRIVAL_FRIENDLY and arrival_result != ARRIVAL_CAPTURED and arrival_result != ARRIVAL_SETTLED:
		return
	destination_planet.show_arrival_feedback(unit_count, source_faction)

func _apply_visuals() -> void:
	if not is_instance_valid(_sprite):
		return
	var tier := Dispatch.cluster_definition(unit_count, transit_config, cluster_tier_bonus)
	if tier == null or tier.texture == null:
		return
	_sprite.texture = tier.texture
	_sprite.scale = Vector2.ONE * (tier.visible_pixels / tier.texture.get_width())

static func pixel_width(amount: int, config: TransitConfig = null, tier_bonus: int = 0) -> float:
	var tier := Dispatch.cluster_definition(maxi(1, amount), config, tier_bonus)
	return tier.visible_pixels if tier != null else 0.0
