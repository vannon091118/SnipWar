extends Node2D

const AREA_SIZE := Vector2(960.0, 540.0)
const EDGE_MARGIN := 48.0
const MINIMUM_SIZE_PIXELS := 4.0
const MAXIMUM_SIZE_PIXELS := 10.0
const MINIMUM_SPEED := 16.0
const MAXIMUM_SPEED := 34.0

var _rng := RandomNumberGenerator.new()
var _bounds := Rect2(Vector2.ZERO, AREA_SIZE)
var _meteors: Array[Sprite2D] = []
var _velocities: Array[Vector2] = []

func _ready() -> void:
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
		if not _bounds.grow(EDGE_MARGIN).has_point(_meteors[index].position):
			_spawn(index)

func _spawn(index: int) -> void:
	var start_position := _random_edge_position()
	var target_position := Vector2(
		_rng.randf_range(0.0, AREA_SIZE.x),
		_rng.randf_range(0.0, AREA_SIZE.y)
	)
	var direction := (target_position - start_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	_meteors[index].position = start_position
	var texture_width: float = _meteors[index].texture.get_width()
	var size_pixels: float = _rng.randf_range(MINIMUM_SIZE_PIXELS, MAXIMUM_SIZE_PIXELS)
	_meteors[index].scale = Vector2.ONE * (size_pixels / texture_width)
	_velocities[index] = direction * _rng.randf_range(MINIMUM_SPEED, MAXIMUM_SPEED)

func _random_edge_position() -> Vector2:
	match _rng.randi_range(0, 3):
		0:
			return Vector2(-EDGE_MARGIN, _rng.randf_range(0.0, AREA_SIZE.y))
		1:
			return Vector2(AREA_SIZE.x + EDGE_MARGIN, _rng.randf_range(0.0, AREA_SIZE.y))
		2:
			return Vector2(_rng.randf_range(0.0, AREA_SIZE.x), -EDGE_MARGIN)
		_:
			return Vector2(_rng.randf_range(0.0, AREA_SIZE.x), AREA_SIZE.y + EDGE_MARGIN)
