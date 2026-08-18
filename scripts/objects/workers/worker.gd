extends Node2D

const SIZE_PIXELS := 10.0

@onready var _sprite: Sprite2D = $Sprite2D
var _source_planet: Node2D
var destination_planet: Node2D

func _ready() -> void:
	var texture_width: float = _sprite.texture.get_width()
	_sprite.scale = Vector2.ONE * (SIZE_PIXELS / texture_width)

func configure(source: Node2D, destination: Node2D) -> void:
	global_position = source.global_position
	_source_planet = source
	destination_planet = destination
	source.register_worker(self)

func _exit_tree() -> void:
	if is_instance_valid(_source_planet):
		_source_planet.unregister_worker(self)
