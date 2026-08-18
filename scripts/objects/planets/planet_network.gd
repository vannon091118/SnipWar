extends Node2D

var _planets: Array[Node2D] = []
var _routes: Dictionary = {}
var _active_planet: Node2D
var _menu: PopupMenu
var _line_phase := 0.0

func _ready() -> void:
	for child in get_parent().get_children():
		if child is Node2D and child.get("layout_size") != null:
			_planets.append(child)
			child.planet_selected.connect(_on_planet_selected)
	_create_menu.call_deferred()

func _create_menu() -> void:
	_menu = PopupMenu.new()
	_menu.name = "PlanetDestinationMenu"
	get_tree().root.add_child(_menu)
	_menu.id_pressed.connect(_on_destination_selected)
	_menu.popup_hide.connect(_on_menu_closed)

func _exit_tree() -> void:
	if is_instance_valid(_menu):
		_menu.queue_free()

func _process(delta: float) -> void:
	if _active_planet != null and _menu.visible:
		_line_phase += delta
		queue_redraw()

func _draw() -> void:
	if _active_planet == null or not _menu.visible:
		return
	var neighbors := get_neighbors(_active_planet)
	for index in neighbors.size():
		var pulse := 0.5 + sin(_line_phase * 2.0 + float(index)) * 0.18
		var color := Color(0.25, 0.85, 1.0, pulse)
		draw_line(to_local(_active_planet.global_position), to_local(neighbors[index].global_position), color, 2.0, true)

func _on_planet_selected(planet: Node2D) -> void:
	_active_planet = planet
	_menu.clear()
	for destination in _planets:
		if destination != planet:
			_menu.add_item(destination.name, destination.get_instance_id())
	var screen_position: Vector2 = get_viewport().get_canvas_transform() * planet.global_position
	_menu.popup(Rect2i(Vector2i(screen_position + Vector2(12.0, 12.0)), Vector2i(240, 0)))
	queue_redraw()

func _on_destination_selected(instance_id: int) -> void:
	if _active_planet == null:
		return
	for destination in _planets:
		if destination.get_instance_id() == instance_id:
			_routes[_active_planet] = destination
			break
	_menu.hide()

func _on_menu_closed() -> void:
	_active_planet = null
	queue_redraw()

func get_destination(source: Node2D) -> Node2D:
	var selected: Node2D = _routes.get(source)
	if is_instance_valid(selected):
		return selected
	var neighbors := get_neighbors(source)
	return neighbors[0] if not neighbors.is_empty() else null

func get_neighbors(planet: Node2D) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var slot: int = int(planet.get_meta("layout_slot", -1))
	if slot < 0:
		return result
	var columns: int = int(get_parent().columns)
	var row: int = floori(float(slot) / float(columns))
	var column: int = slot % columns
	for other in _planets:
		if other == planet:
			continue
		var other_slot: int = int(other.get_meta("layout_slot", -1))
		if other_slot < 0:
			continue
		var other_row: int = floori(float(other_slot) / float(columns))
		var other_column: int = other_slot % columns
		if absi(row - other_row) + absi(column - other_column) == 1:
			result.append(other)
	return result
