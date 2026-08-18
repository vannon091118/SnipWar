extends Node2D

@export var orbit_radius := 36.0
@export var angular_speed := 0.24
@export var size_pixels := 6.0
@export var asteroid_texture: Texture2D:
	set(value):
		asteroid_texture = value
		_apply_visuals()

@onready var _sprite: Sprite2D = $Sprite2D
var _target: Node2D
var _angle := 0.0

func _ready() -> void:
	_target = get_tree().get_first_node_in_group("planet_toxic") as Node2D
	_apply_visuals()

func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		return
	_angle = fmod(_angle + angular_speed * delta, TAU)
	global_position = _target.global_position + Vector2.from_angle(_angle) * orbit_radius

func _apply_visuals() -> void:
	if not is_instance_valid(_sprite):
		return
	_sprite.texture = asteroid_texture
	var texture_width: float = _sprite.texture.get_width()
	_sprite.scale = Vector2.ONE * (size_pixels / texture_width)
