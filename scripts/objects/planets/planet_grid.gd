class_name PlanetGrid
extends Node2D

## Buildable hex/rect grid on a planet. Owns PlanetGridCell instances, building
## placement/removal, and BFS pathfinding for minion movement. Renders cell
## outlines via _draw() in the paper-comic style.

var _config: PlanetGridConfig
var _building_catalog: BuildingCatalog
var _cells: Dictionary = {}

func configure(config: PlanetGridConfig, catalog: BuildingCatalog = null) -> void:
	_config = config
	_building_catalog = catalog
	_build_cells()
	queue_redraw()

func get_config() -> PlanetGridConfig:
	return _config

func _build_cells() -> void:
	_cells.clear()
	if _config == null:
		return
	for q in range(-_config.grid_radius, _config.grid_radius + 1):
		for r in range(-_config.grid_radius, _config.grid_radius + 1):
			if not _config.in_bounds(q, r):
				continue
			var cell := PlanetGridCell.new()
			cell.axial_q = q
			cell.axial_r = r
			_cells[Vector2i(q, r)] = cell

func cell_at(q: int, r: int) -> PlanetGridCell:
	return _cells.get(Vector2i(q, r)) as PlanetGridCell

func get_cell_at(q: int, r: int) -> PlanetGridCell:
	return cell_at(q, r)

func place_building(q: int, r: int, building: BuildingDefinition) -> bool:
	var cell := cell_at(q, r)
	if cell == null or building == null or cell.building != null:
		return false
	cell.building = building
	cell.state = &"occupied"
	cell.current_hp = building.hp
	queue_redraw()
	return true

func remove_building(q: int, r: int) -> bool:
	var cell := cell_at(q, r)
	if cell == null or cell.building == null:
		return false
	cell.building = null
	cell.state = &"empty"
	cell.current_hp = 0
	queue_redraw()
	return true

func get_neighbors(q: int, r: int) -> Array[PlanetGridCell]:
	var result: Array[PlanetGridCell] = []
	if _config == null:
		return result
	for offset in _config.axial_neighbors(q, r):
		var cell := cell_at(offset.x, offset.y)
		if cell != null:
			result.append(cell)
	return result

## BFS shortest path from (sq, sr) to (tq, target_row) through passable cells.
func find_path(sq: int, sr: int, tq: int, target_row: int, blocked_states: Array[StringName] = [&"blocked"]) -> Array[Vector2i]:
	var start := Vector2i(sq, sr)
	var target := Vector2i(tq, target_row)
	if not _cells.has(start) or not _cells.has(target):
		return []
	var frontier: Array[Vector2i] = [start]
	var came_from: Dictionary = { start: Vector2i(-1, -1) }
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if current == target:
			break
		for neighbor in get_neighbors(current.x, current.y):
			var key := neighbor.key()
			if came_from.has(key):
				continue
			if blocked_states.has(neighbor.state):
				continue
			came_from[key] = current
			frontier.append(key)
	if not came_from.has(target):
		return []
	var path: Array[Vector2i] = []
	var step := target
	while step != start:
		path.append(step)
		step = came_from[step] as Vector2i
	path.append(start)
	path.reverse()
	return path

func base_hp() -> int:
	var total := 0
	for cell in building_cells():
		total += cell.current_hp
	return total

func building_cells() -> Array[PlanetGridCell]:
	var result: Array[PlanetGridCell] = []
	for key in _cells:
		var cell: PlanetGridCell = _cells[key]
		if cell.building != null:
			result.append(cell)
	return result

func towers() -> Array[PlanetGridCell]:
	var result: Array[PlanetGridCell] = []
	for key in _cells:
		var cell: PlanetGridCell = _cells[key]
		if cell.building != null and cell.building.building_type == "tower":
			result.append(cell)
	return result

func reset_grid() -> void:
	_build_cells()
	queue_redraw()

func _draw() -> void:
	if _config == null:
		return
	for key in _cells:
		var cell: PlanetGridCell = _cells[key]
		var pos: Vector2 = cell.pixel_position(_config)
		var radius: float = _config.cell_size.x * 0.42
		if cell.building != null:
			draw_circle(pos, radius, Color(0.35, 0.35, 0.42, 0.9))
			draw_arc(pos, radius, 0.0, TAU, 20, Color(0.1, 0.1, 0.15, 1.0), 2.0, true)
		else:
			draw_circle(pos, radius, Color(1.0, 1.0, 1.0, 0.06))
			draw_arc(pos, radius, 0.0, TAU, 20, Color(0.1, 0.1, 0.15, 0.6), 1.0, true)
