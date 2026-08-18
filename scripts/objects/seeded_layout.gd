@tool
extends Node2D

@export var layout_seed: int = 241119:
	set(value):
		layout_seed = value
		_queue_layout()

@export var target_size: Vector2 = Vector2(960.0, 540.0):
	set(value):
		target_size = value
		_queue_layout()

@export_range(1, 10, 1) var columns: int = 5:
	set(value):
		columns = maxi(1, value)
		_queue_layout()

@export_range(0.0, 0.4, 0.01) var jitter: float = 0.18:
	set(value):
		jitter = clampf(value, 0.0, 0.4)
		_queue_layout()

@export_range(0.2, 1.5, 0.05) var minimum_scale: float = 0.32:
	set(value):
		minimum_scale = value
		_queue_layout()

@export_range(0.2, 1.5, 0.05) var maximum_scale: float = 0.58:
	set(value):
		maximum_scale = value
		_queue_layout()

@export_range(0.0, 160.0, 1.0) var padding: float = 38.0:
	set(value):
		padding = value
		_queue_layout()

func _ready() -> void:
	regenerate()

func regenerate() -> void:
	var layout_items: Array[Node2D] = []
	for child in get_children():
		if child is Node2D:
			layout_items.append(child)

	if layout_items.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed

	var rows: int = ceili(float(layout_items.size()) / float(columns))
	var cell_size := Vector2(
		target_size.x / float(columns),
		target_size.y / float(rows)
	)

	for index in layout_items.size():
		var column: int = index % columns
		var row: int = floori(float(index) / float(columns))
		var cell_center := Vector2(
			(float(column) + 0.5) * cell_size.x,
			(float(row) + 0.5) * cell_size.y
		)
		var offset := Vector2(
			rng.randf_range(-cell_size.x * jitter, cell_size.x * jitter),
			rng.randf_range(-cell_size.y * jitter, cell_size.y * jitter)
		)
		var item_position := cell_center + offset
		item_position.x = clampf(item_position.x, padding, target_size.x - padding)
		item_position.y = clampf(item_position.y, padding, target_size.y - padding)

		var item_scale: float = rng.randf_range(minimum_scale, maximum_scale)
		var item: Node2D = layout_items[index]
		item.position = item_position
		item.scale = Vector2.ONE * item_scale

func _queue_layout() -> void:
	if is_inside_tree():
		call_deferred("regenerate")
