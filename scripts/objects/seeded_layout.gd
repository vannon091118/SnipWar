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
	var occupied_slots: Dictionary = {}
	var xl_items: Array[Planet] = []
	var l_items: Array[Planet] = []
	var remaining_items: Array[Planet] = []

	for item in layout_items:
		var size_class: StringName = _size_class(item)
		if size_class == &"xl":
			xl_items.append(item)
		elif size_class == &"l":
			l_items.append(item)
		else:
			remaining_items.append(item)

	if not xl_items.is_empty():
		_assign_slot(xl_items[0], 0, assigned_slots, occupied_slots)
	if xl_items.size() > 1:
		_assign_slot(xl_items[1], layout_items.size() - 1, assigned_slots, occupied_slots)
	for index in range(2, xl_items.size()):
		remaining_items.append(xl_items[index])
	if not l_items.is_empty():
		_assign_slot(l_items[0], _crossing_slot(layout_items.size(), occupied_slots), assigned_slots, occupied_slots)

	for item in l_items:
		if not assigned_slots.has(item):
			remaining_items.append(item)

	var free_slots: Array[int] = []
	for slot in layout_items.size():
		if not occupied_slots.has(slot):
			free_slots.append(slot)

	for item in remaining_items:
		var slot: int = free_slots.pop_front()
		_assign_slot(item, slot, assigned_slots, occupied_slots)

	for item in layout_items:
		var slot: int = assigned_slots[item]
		var column: int = slot % columns
		var row: int = floori(float(slot) / float(columns))
		var cell_center := Vector2(
			(float(column) + 0.5) * cell_size.x,
			(float(row) + 0.5) * cell_size.y
		)
		var offset := Vector2.ZERO
		var is_outer_column: bool = column == 0 or column == columns - 1
		if _size_class(item) != &"xl":
			if is_outer_column:
				var inward_offset: float = cell_size.x * 0.12
				offset.x = inward_offset if column == 0 else -inward_offset
			else:
				offset = Vector2(
					rng.randf_range(-cell_size.x * jitter, cell_size.x * jitter),
					rng.randf_range(-cell_size.y * jitter, cell_size.y * jitter)
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
	for index in range(shuffled_items.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var item: Planet = shuffled_items[index]
		shuffled_items[index] = shuffled_items[swap_index]
		shuffled_items[swap_index] = item
	for index in shuffled_items.size():
		shuffled_items[index].set("layout_size", size_classes[index])
		shuffled_items[index].set_detail_seed(rng.randi())

func _assign_slot(item: Planet, slot: int, assigned_slots: Dictionary, occupied_slots: Dictionary) -> void:
	assigned_slots[item] = slot
	occupied_slots[slot] = true

func _crossing_slot(item_count: int, occupied_slots: Dictionary) -> int:
	var preferred_slot: int = int(columns / 2.0)
	if preferred_slot < item_count and not occupied_slots.has(preferred_slot):
		return preferred_slot
	for slot in item_count:
		if not occupied_slots.has(slot):
			return slot
	return 0

func _size_class(item: Planet) -> StringName:
	return StringName(item.layout_size)

func _scale_for(item: Planet, rng: RandomNumberGenerator) -> float:
	var size_range: Vector2 = Planet.size_profile(_size_class(item))[&"scale_range"]
	return rng.randf_range(size_range.x, size_range.y)

func _queue_layout() -> void:
	if is_inside_tree():
		call_deferred("regenerate")
