extends Node2D

const DEFAULT_WORLD_CONFIG: WorldConfig = preload("res://resources/config/world_default.tres")
const DEFAULT_METEOR_CONFIG: MeteorConfig = preload("res://resources/config/meteor_default.tres")

@export var world_config: WorldConfig = DEFAULT_WORLD_CONFIG
@export var meteor_config: MeteorConfig = DEFAULT_METEOR_CONFIG

var _rng := RandomNumberGenerator.new()
var _bounds := Rect2()
var _edge_margin := 48.0
var _meteor_config: MeteorConfig = DEFAULT_METEOR_CONFIG
var _meteors: Array[Sprite2D] = []
var _velocities: Array[Vector2] = []

func _ready() -> void:
	var config: WorldConfig = world_config if world_config != null else DEFAULT_WORLD_CONFIG
	_meteor_config = meteor_config if meteor_config != null else DEFAULT_METEOR_CONFIG
	_bounds = config.meteor_bounds()
	_edge_margin = config.meteor_edge_margin
	_rng.randomize()
	for child in get_children():
		if child is Sprite2D:
			_meteors.append(child)
			_velocities.append(Vector2.ZERO)
	for index in _meteors.size():
		_spawn(index)

func _process(delta: float) -> void:
	for index in _meteors.size():
		_meteors[index].position += _velocities[index] * delta
		if not _bounds.grow(_edge_margin).has_point(_meteors[index].position):
			_spawn(index)

func _spawn(index: int) -> void:
	var start_position := _random_edge_position()
	var target_position := Vector2(
		_rng.randf_range(_bounds.position.x, _bounds.end.x),
		_rng.randf_range(_bounds.position.y, _bounds.end.y)
	)
	var direction := (target_position - start_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	_meteors[index].position = start_position
	var texture_width: float = _meteors[index].texture.get_width()
	var size_pixels: float = _rng.randf_range(_meteor_config.minimum_size_pixels, _meteor_config.maximum_size_pixels)
	_meteors[index].scale = Vector2.ONE * (size_pixels / texture_width)
	_velocities[index] = direction * _rng.randf_range(_meteor_config.minimum_speed, _meteor_config.maximum_speed)

func _random_edge_position() -> Vector2:
	match _rng.randi_range(0, 3):
		0:
			return Vector2(_bounds.position.x - _edge_margin, _rng.randf_range(_bounds.position.y, _bounds.end.y))
		1:
			return Vector2(_bounds.end.x + _edge_margin, _rng.randf_range(_bounds.position.y, _bounds.end.y))
		2:
			return Vector2(_rng.randf_range(_bounds.position.x, _bounds.end.x), _bounds.position.y - _edge_margin)
		_:
			return Vector2(_rng.randf_range(_bounds.position.x, _bounds.end.x), _bounds.end.y + _edge_margin)
