extends Node2D

class_name WorkerCluster

const _Dispatch := preload("res://scripts/dispatch.gd")
const TIER_TEXTURES: Dictionary = {
	&"k": preload("res://assets/objects/workers/cluster_k.svg"),
	&"m": preload("res://assets/objects/workers/cluster_m.svg"),
	&"l": preload("res://assets/objects/workers/cluster_l.svg")
}
const TIER_PIXELS: Dictionary = {
	&"k": 12.0,
	&"m": 20.0,
	&"l": 30.0
}

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _attachments: Node2D = $Attachments

var unit_count := 1
var destination_planet: Planet

func _ready() -> void:
	_apply_visuals()

func configure_transit(source_position: Vector2, destination: Planet, amount: int) -> void:
	global_position = source_position
	destination_planet = destination
	unit_count = amount
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
	var tier := _Dispatch.cluster_tier(unit_count)
	var texture: Texture2D = TIER_TEXTURES[tier]
	_sprite.texture = texture
	_sprite.scale = Vector2.ONE * (TIER_PIXELS[tier] / texture.get_width())

static func pixel_width(amount: int) -> float:
	return TIER_PIXELS[_Dispatch.cluster_tier(maxi(1, amount))]
