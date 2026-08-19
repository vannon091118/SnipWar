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

@export_range(0, 20, 1) var extra_large_count: int = 2:
	set(value):
		extra_large_count = maxi(0, value)
		_queue_layout()

@export_range(0, 20, 1) var large_count: int = 1:
	set(value):
		large_count = maxi(0, value)
		_queue_layout()

@export_range(0.0, 0.4, 0.01) var jitter: float = 0.12:
	set(value):
		jitter = clampf(value, 0.0, 0.4)
		_queue_layout()

@export_range(0.0, 160.0, 1.0) var padding: float = 132.0:
	set(value):
		padding = value
		_queue_layout()

func _ready() -> void:
	regenerate()

func regenerate() -> void:
	var layout_items: Array[Planet] = []
	for child in get_children():
		if child is Planet:
			layout_items.append(child)

	if layout_items.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	_assign_size_classes(layout_items, rng)
	var rows: int = ceili(float(layout_items.size()) / float(columns))
	var cell_size := Vector2(
		target_size.x / float(columns),
		target_size.y / float(rows)
	)
	var assigned_slots: Dictionary = {}
	var slots: Array[int] = []
	for slot in layout_items.size():
		slots.append(slot)
	_shuffle(slots, rng)
	for index in layout_items.size():
		assigned_slots[layout_items[index]] = slots[index]

	for item in layout_items:
		var slot: int = assigned_slots[item]
		var column: int = slot % columns
		var row: int = floori(float(slot) / float(columns))
		var cell_center := Vector2(
			(float(column) + 0.5) * cell_size.x,
			(float(row) + 0.5) * cell_size.y
		)
		var jitter_factor := 0.65 if _size_class(item) == &"xl" else 1.0
		var offset := Vector2(
			rng.randf_range(-cell_size.x * jitter * jitter_factor, cell_size.x * jitter * jitter_factor),
			rng.randf_range(-cell_size.y * jitter * jitter_factor, cell_size.y * jitter * jitter_factor)
		)
		var item_position := cell_center + offset
		item_position.x = clampf(item_position.x, padding, target_size.x - padding)
		item_position.y = clampf(item_position.y, padding, target_size.y - padding)
		item.set_meta("layout_slot", slot)
		item.position = item_position
		item.scale = Vector2.ONE * _scale_for(item, rng)

func _assign_size_classes(items: Array[Planet], rng: RandomNumberGenerator) -> void:
	var size_classes: Array[StringName] = []
	for _index in mini(extra_large_count, items.size()):
		size_classes.append(&"xl")
	for _index in mini(large_count, maxi(0, items.size() - size_classes.size())):
		size_classes.append(&"l")
	while size_classes.size() < items.size():
		size_classes.append(&"variable")

	var shuffled_items: Array[Planet] = items.duplicate()
	_shuffle(shuffled_items, rng)
	for index in shuffled_items.size():
		shuffled_items[index].set("layout_size", size_classes[index])
		shuffled_items[index].set_detail_seed(rng.randi())

func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = value

func _size_class(item: Planet) -> StringName:
	return StringName(item.layout_size)

func _scale_for(item: Planet, rng: RandomNumberGenerator) -> float:
	var size_range: Vector2 = Planet.size_profile(_size_class(item))[&"scale_range"]
	return rng.randf_range(size_range.x, size_range.y)

func _queue_layout() -> void:
	if is_inside_tree():
		call_deferred("regenerate")
