extends Node2D

class_name WorkerCluster

const DEFAULT_CONFIG: TransitConfig = preload("res://resources/config/transit_default.tres")

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _attachments: Node2D = $Attachments

var unit_count := 1
var destination_planet: Planet
var transit_config: TransitConfig = DEFAULT_CONFIG

func _ready() -> void:
	_apply_visuals()

func configure_transit(source_position: Vector2, destination: Planet, amount: int, config: TransitConfig = null) -> void:
	global_position = source_position
	destination_planet = destination
	unit_count = amount
	transit_config = config if config != null else DEFAULT_CONFIG
	_apply_visuals()

func get_unit_count() -> int:
	return unit_count

func attach_object(object: Node2D, offset := Vector2.ZERO) -> void:
	_attachments.add_child(object)
	object.position = offset

func _arrive() -> void:
	if is_instance_valid(destination_planet):
		destination_planet.register_workers(unit_count)
	destination_planet = null
	queue_free()

func _apply_visuals() -> void:
	if not is_instance_valid(_sprite):
		return
	var tier := Dispatch.cluster_definition(unit_count, transit_config)
	if tier == null or tier.texture == null:
		return
	_sprite.texture = tier.texture
	_sprite.scale = Vector2.ONE * (tier.visible_pixels / tier.texture.get_width())

static func pixel_width(amount: int, config: TransitConfig = null) -> float:
	var tier := Dispatch.cluster_definition(maxi(1, amount), config)
	return tier.visible_pixels if tier != null else 0.0
