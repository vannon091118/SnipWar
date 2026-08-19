extends Node2D

const SIZE_PIXELS := 10.0

@onready var _sprite: Sprite2D = $Sprite2D
var _registered_planet: Node2D
var destination_planet: Node2D
var _flying := false

func _ready() -> void:
	var texture_width: float = _sprite.texture.get_width()
	_sprite.scale = Vector2.ONE * (SIZE_PIXELS / texture_width)

func configure(source: Node2D, destination: Node2D) -> void:
	global_position = source.global_position
	_registered_planet = source
	destination_planet = destination
	source.register_worker(self)

func begin_flight(destination: Node2D) -> void:
	destination_planet = destination
	if is_instance_valid(_registered_planet):
		_registered_planet.unregister_worker(self)
		_registered_planet = null
	_flying = true

func _process(_delta: float) -> void:
	if _flying and is_instance_valid(destination_planet) and is_instance_valid(_sprite):
		_sprite.rotation = global_position.angle_to_point(destination_planet.global_position)

func _arrive() -> void:
	if not _flying:
		return
	_flying = false
	_registered_planet = destination_planet
	destination_planet.register_worker(self)
	destination_planet = null

func _exit_tree() -> void:
	if is_instance_valid(_registered_planet):
		_registered_planet.unregister_worker(self)
