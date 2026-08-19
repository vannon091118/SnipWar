extends Node2D

const SIZE_PIXELS := 10.0

@onready var _sprite: Sprite2D = $Sprite2D
var _registered_planet: Node2D
var destination_planet: Node2D

func _ready() -> void:
	var texture_width: float = _sprite.texture.get_width()
	_sprite.scale = Vector2.ONE * (SIZE_PIXELS / texture_width)

func configure(source: Node2D, destination: Node2D) -> void:
	global_position = source.global_position
	_registered_planet = source
	destination_planet = destination
	source.register_worker(self)

func fly_to(destination: Node2D, duration: float) -> void:
	destination_planet = destination
	_registered_planet.unregister_worker(self)
	_registered_planet = null
	var tween := create_tween()
	tween.tween_property(self, "global_position", destination.global_position, duration).set_trans(Tween.TRANS_LINEAR)
	tween.finished.connect(_arrive)

func _arrive() -> void:
	if not is_instance_valid(destination_planet):
		return
	_registered_planet = destination_planet
	destination_planet.register_worker(self)
	destination_planet = null

func _exit_tree() -> void:
	if is_instance_valid(_registered_planet):
		_registered_planet.unregister_worker(self)
