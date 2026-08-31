@tool
class_name NavigationField
extends Node2D

const WAYPOINT_SCENE: PackedScene = preload("res://scenes/objects/planets/navigation_waypoint.tscn")
const DEFAULT_WORLD_CONFIG: WorldConfig = preload("res://resources/config/world_default.tres")
const DEFAULT_NAVIGATION_CONFIG: NavigationConfig = preload("res://resources/config/navigation_default.tres")

@export var world_config: WorldConfig = DEFAULT_WORLD_CONFIG
@export var navigation_config: NavigationConfig = DEFAULT_NAVIGATION_CONFIG

var _astar := AStar2D.new()
var _point_ids: Dictionary = {}
var _waypoints: Array[NavigationWaypoint] = []
var _edges: Array[Array] = []
## Parallel to _edges: endpoint planet refs at each side of the edge (null for
## waypoint midpoints). _draw() uses this array to dim/skip edges that lie
## outside the player's fog-of-war frontier without re-resolving nodes.
var _edge_endpoints: Array[Array] = []
## Parallel to _edges: sector edge type per edge (intra/inter/void, or empty
## when the sector system is disabled). _draw() uses this for sector tinting.
var _edge_types: Array[StringName] = []
## Per-planet neighbor map covering both grid edges and K-nearest long-range
## edges. Single source of truth for PlanetNetwork.get_neighbors() — the slot
## grid is no longer authoritative on its own.
var _planet_neighbors: Dictionary = {}
var _next_point_id := 1
var _rebuild_queued := false
var _is_built := false
## Pending edges keyed by cell: cell -> Array[Vector2i] (neighbor cells that
## haven't been instantiated yet). When a planet is added, its pending edges
## are realized against already-active neighbors.
var _pending_edges: Dictionary = {}
## Cell -> Planet for active planets in the AStar graph.
var _cell_to_planet: Dictionary = {}

func _ready() -> void:
	if get_parent() != null and get_parent().has_signal("layout_completed"):
		var parent_node: Node = get_parent()
		if not parent_node.is_connected("layout_completed", Callable(self, "_on_layout_completed")):
			parent_node.connect("layout_completed", Callable(self, "_on_layout_completed"))
	request_rebuild()

func _on_layout_completed(_planets: Array = []) -> void:
	world_config = _resolved_world_config()
	request_rebuild()

func request_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("rebuild")

func rebuild() -> void:
	_rebuild_queued = false
	for waypoint in _waypoints:
		if is_instance_valid(waypoint):
			waypoint.queue_free()
	_waypoints.clear()
	_edges.clear()
	_point_ids.clear()
	_cell_to_planet.clear()
	_pending_edges.clear()
	_astar = AStar2D.new()
	_next_point_id = 1
	_is_built = false
	_edge_endpoints.clear()
	_edge_types.clear()
	_planet_neighbors.clear()

	var planets: Array[Planet] = []
	for child in get_parent().get_children():
		if child is Planet and not child.get_meta("pending_free", false):
			planets.append(child)
	if planets.size() < 2:
			queue_redraw()
			return

	var config: WorldConfig = _resolved_world_config()
	var waypoint_config: NavigationConfig = navigation_config if navigation_config != null else DEFAULT_NAVIGATION_CONFIG
	var columns := config.resolved_columns(planets.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(config.layout_seed) + 9137

	var slot_planets: Dictionary = {}
	for planet in planets:
		_point_ids[planet] = _add_graph_point(planet.global_position)
		var slot: int = int(planet.get_meta("layout_slot", -1))
		if slot >= 0:
			slot_planets[slot] = planet
		_planet_neighbors[planet] = [] as Array[Node2D]
		if config.is_infinite_world() and planet.has_meta("cell"):
			_cell_to_planet[planet.get_meta("cell")] = planet

	if config.is_infinite_world():
		_rebuild_infinite_edges(planets, waypoint_config)
		_is_built = not _point_ids.is_empty()
		queue_redraw()
		return

	var processed_edges: Dictionary = {}
	var edge_index := 0
	var grid_edge_pairs: Array = []
	for first in planets:
		var first_slot: int = int(first.get_meta("layout_slot", -1))
		if first_slot < 0:
			continue
		var first_column := first_slot % columns
		var candidate_slots: Array[int] = []
		if first_column > 0:
			candidate_slots.append(first_slot - 1)
		if first_column < columns - 1:
			candidate_slots.append(first_slot + 1)
		candidate_slots.append(first_slot - columns)
		candidate_slots.append(first_slot + columns)
		for neighbor_slot in candidate_slots:
			if not slot_planets.has(neighbor_slot):
				continue
			var edge_key := "%d-%d" % [mini(first_slot, neighbor_slot), maxi(first_slot, neighbor_slot)]
			if processed_edges.has(edge_key):
				continue
			processed_edges[edge_key] = true
			var second: Planet = slot_planets[neighbor_slot]
			var midpoint := (first.global_position + second.global_position) * 0.5
			var direction := (second.global_position - first.global_position).normalized()
			var perpendicular := Vector2(-direction.y, direction.x)
			midpoint += perpendicular * rng.randf_range(-waypoint_config.midpoint_jitter, waypoint_config.midpoint_jitter)
			midpoint = _clear_of_planets(midpoint, planets)
			var waypoint_definition: NavigationWaypointDefinition = waypoint_config.waypoint_for_edge(edge_index)
			if waypoint_definition == null:
				continue
			var waypoint: NavigationWaypoint = WAYPOINT_SCENE.instantiate()
			waypoint.name = "%sWaypoint_%d" % [waypoint_definition.waypoint_type.capitalize(), edge_index]
			add_child(waypoint)
			waypoint.global_position = midpoint
			waypoint.configure(waypoint_definition)
			_waypoints.append(waypoint)
			var waypoint_id := _add_graph_point(midpoint)
			_connect_graph_points(_point_ids[first], waypoint_id)
			_connect_graph_points(waypoint_id, _point_ids[second])
			_edges.append([first.global_position, midpoint])
			_edges.append([midpoint, second.global_position])
			_edge_endpoints.append([first, null])
			_edge_endpoints.append([null, second])
			_push_edge_type(first, second)
			_push_edge_type(first, second)
			_record_neighbor_pair(first, second)
			grid_edge_pairs.append([first, second])
			edge_index += 1

	# Layer 2: deterministic K-nearest long-range edges. Bounded by
	# NavigationConfig (which can inherit the WorldConfig ratio/cap). Grid
	# edges are excluded so the K-nearest layer is purely additive.
	var knn_ratio: float = waypoint_config.resolved_graph_neighbor_ratio(config)
	var knn_cap: int = waypoint_config.resolved_max_extra_edges(config)
	var knn_edges: Array = WorldGenerator.build_knn_edges(planets, knn_ratio, knn_cap, grid_edge_pairs)
	for entry in knn_edges:
		var first: Planet = entry[0] as Planet
		var second: Planet = entry[1] as Planet
		if first == null or second == null:
			continue
		_connect_graph_points(_point_ids[first], _point_ids[second])
		_edges.append([first.global_position, second.global_position])
		_edge_endpoints.append([first, second])
		_push_edge_type(first, second)

	_is_built = not _point_ids.is_empty()
	queue_redraw()

func _rebuild_infinite_edges(planets: Array[Planet], waypoint_config: NavigationConfig) -> void:
	var edge_index := 0
	for first in planets:
		var first_cell: Vector2i = first.get_meta("cell", Vector2i.ZERO)
		for second_cell in [Vector2i(first_cell.x + 1, first_cell.y), Vector2i(first_cell.x, first_cell.y + 1)]:
			if not _cell_to_planet.has(second_cell):
				continue
			var second: Planet = _cell_to_planet[second_cell]
			if second == null or not is_instance_valid(second):
				continue
			var midpoint := (first.global_position + second.global_position) * 0.5
			var direction := (second.global_position - first.global_position).normalized()
			var perpendicular := Vector2(-direction.y, direction.x)
			midpoint += perpendicular * waypoint_config.midpoint_jitter * sin(float(edge_index + 1))
			midpoint = _clear_of_planets(midpoint, planets)
			var waypoint_definition: NavigationWaypointDefinition = waypoint_config.waypoint_for_edge(edge_index)
			if waypoint_definition == null:
				continue
			var waypoint: NavigationWaypoint = WAYPOINT_SCENE.instantiate()
			waypoint.name = "%sWaypoint_%d" % [waypoint_definition.waypoint_type.capitalize(), edge_index]
			add_child(waypoint)
			waypoint.global_position = midpoint
			waypoint.configure(waypoint_definition)
			_waypoints.append(waypoint)
			var waypoint_id := _add_graph_point(midpoint)
			_connect_graph_points(_point_ids[first], waypoint_id)
			_connect_graph_points(waypoint_id, _point_ids[second])
			_edges.append([first.global_position, midpoint])
			_edges.append([midpoint, second.global_position])
			_edge_endpoints.append([first, null])
			_edge_endpoints.append([null, second])
			_push_edge_type(first, second)
			_push_edge_type(first, second)
			_record_neighbor_pair(first, second)
			edge_index += 1

func get_neighbors_for_planet(planet: Node2D) -> Array[Node2D]:
	if not _is_built:
		rebuild()
	var cached: Variant = _planet_neighbors.get(planet)
	if cached == null:
		return []
	return (cached as Array).duplicate() as Array[Node2D]

## --- Incremental graph API for infinite chunk-grid world ---

func has_planet(planet: Planet) -> bool:
	return _point_ids.has(planet)

## Adds a planet to the AStar graph and connects it to any active neighbors.
## cell is the chunk-grid cell of this planet. Pending edges are stored for
## neighbors that don't exist yet.
func add_planet(planet: Planet, cell: Vector2i) -> void:
	if _point_ids.has(planet):
		return
	_point_ids[planet] = _add_graph_point(planet.global_position)
	_cell_to_planet[cell] = planet
	_planet_neighbors[planet] = [] as Array[Node2D]
	# Connect to deterministic grid neighbors that are already active.
	for neighbor_cell in _deterministic_neighbor_cells(cell):
		if _cell_to_planet.has(neighbor_cell):
			var neighbor: Planet = _cell_to_planet[neighbor_cell]
			if neighbor != null and is_instance_valid(neighbor):
				_connect_graph_points(_point_ids[planet], _point_ids[neighbor])
				_record_neighbor_pair(planet, neighbor)
		else:
			# Store as pending — realized when the neighbor is added.
			if not _pending_edges.has(neighbor_cell):
				_pending_edges[neighbor_cell] = [] as Array[Vector2i]
			var pending: Array = _pending_edges[neighbor_cell]
			if not pending.has(cell):
				pending.append(cell)
				_pending_edges[neighbor_cell] = pending
	# Realize pending edges from other cells pointing to this one.
	if _pending_edges.has(cell):
		var waiting_cells: Array = _pending_edges[cell]
		_pending_edges.erase(cell)
		for waiting_cell in waiting_cells:
			if _cell_to_planet.has(waiting_cell):
				var neighbor: Planet = _cell_to_planet[waiting_cell]
				if neighbor != null and is_instance_valid(neighbor):
					_connect_graph_points(_point_ids[planet], _point_ids[neighbor])
					_record_neighbor_pair(planet, neighbor)
	_is_built = not _point_ids.is_empty()
	queue_redraw()

## Removes a planet from the AStar graph. AStar2D.remove_point() automatically
## cleans up all connections. Also cleans _planet_neighbors, _edges,
## _edge_endpoints and _cell_to_planet. Pending edges are preserved (they're
## cell-based, not planet-based).
func remove_planet(planet: Planet) -> void:
	if not _point_ids.has(planet):
		return
	var point_id: int = _point_ids[planet]
	# AStar2D.remove_point() automatically removes all connections.
	_astar.remove_point(point_id)
	_point_ids.erase(planet)
	# Clean _planet_neighbors (both directions).
	if _planet_neighbors.has(planet):
		for neighbor in _planet_neighbors[planet]:
			var neighbor_list: Array = _planet_neighbors.get(neighbor, [])
			neighbor_list.erase(planet)
			_planet_neighbors[neighbor] = neighbor_list
		_planet_neighbors.erase(planet)
	# Clean _edges, _edge_endpoints and _edge_types.
	var i := 0
	while i < _edges.size():
		var endpoints: Array = _edge_endpoints[i] if i < _edge_endpoints.size() else [null, null]
		if endpoints.has(planet):
			_edges.remove_at(i)
			_edge_endpoints.remove_at(i)
			if i < _edge_types.size():
				_edge_types.remove_at(i)
		else:
			i += 1
	# Clean _cell_to_planet.
	var cell_to_erase: Variant = null
	for cell_key in _cell_to_planet:
		if _cell_to_planet[cell_key] == planet:
			cell_to_erase = cell_key
			break
	if cell_to_erase != null:
		_cell_to_planet.erase(cell_to_erase)
	_is_built = not _point_ids.is_empty()
	queue_redraw()

## Returns the deterministic grid-neighbor cells for a given cell. These are
## the 4-connected neighbors (left, right, up, down) in chunk-cell space.
func _deterministic_neighbor_cells(cell: Vector2i) -> Array[Vector2i]:
	return [
		Vector2i(cell.x - 1, cell.y),
		Vector2i(cell.x + 1, cell.y),
		Vector2i(cell.x, cell.y - 1),
		Vector2i(cell.x, cell.y + 1),
	]

func _record_neighbor_pair(first: Node2D, second: Node2D) -> void:
	if not _planet_neighbors.has(first):
		_planet_neighbors[first] = [] as Array[Node2D]
	if not _planet_neighbors.has(second):
		_planet_neighbors[second] = [] as Array[Node2D]
	var first_list: Array = _planet_neighbors[first]
	var second_list: Array = _planet_neighbors[second]
	if not first_list.has(second):
		first_list.append(second)
		_planet_neighbors[first] = first_list
	if not second_list.has(first):
		second_list.append(first)
		_planet_neighbors[second] = second_list

func find_route(source: Node2D, destination: Node2D) -> Array[Vector2]:
	if not _is_built:
		rebuild()
	var fallback: Array[Vector2] = [source.global_position, destination.global_position]
	if not _point_ids.has(source) or not _point_ids.has(destination):
		return fallback
	var packed_path: PackedVector2Array = _astar.get_point_path(_point_ids[source], _point_ids[destination])
	if packed_path.size() < 2:
		return fallback
	var result: Array[Vector2] = []
	for point in packed_path:
		result.append(point)
	return result

func get_waypoint_count() -> int:
	return _waypoints.size()

func get_edges() -> Array[Array]:
	return _edges.duplicate()

func get_edge_type(edge_index: int) -> StringName:
	if edge_index < 0 or edge_index >= _edge_types.size():
		return &""
	return _edge_types[edge_index]

func _sector_typing_active() -> bool:
	var config: WorldConfig = _resolved_world_config()
	return config != null and config.resolved_sector_count() > 0 and not config.sector_flavors.is_empty()

func _sector_id_of(planet: Planet) -> StringName:
	if planet == null:
		return &""
	return planet.get_meta("sector_id", &"") as StringName

func _push_edge_type(first: Planet, second: Planet) -> void:
	if _sector_typing_active():
		_edge_types.append(SectorClassifier.edge_type(_sector_id_of(first), _sector_id_of(second)))
	else:
		_edge_types.append(&"")

func _resolved_world_config() -> WorldConfig:
	var parent_config: WorldConfig = get_parent().get("world_config") as WorldConfig
	if parent_config != null:
		return parent_config
	return world_config if world_config != null else DEFAULT_WORLD_CONFIG

func _draw() -> void:
	var config: NavigationConfig = navigation_config if navigation_config != null else DEFAULT_NAVIGATION_CONFIG
	var base_color := config.edge_color
	var frontier_color := config.edge_color
	frontier_color.a = config.edge_alpha * 0.55
	for index in range(_edges.size()):
		var edge: Array = _edges[index]
		if edge.size() != 2:
			continue
		# Use the cached endpoint refs populated by rebuild(); null means the
		# endpoint is a waypoint midpoint (always rendered with the dim tier).
		var endpoints: Array = _edge_endpoints[index] if index < _edge_endpoints.size() else [null, null]
		var max_fog := _max_fog(endpoints)
		if max_fog == FOG_HIDDEN:
			continue
		var color := base_color if max_fog == FOG_VISIBLE else frontier_color
		# Sector edge typing dims inter-sector / void edges (paper-look tint).
		if index < _edge_types.size() and not String(_edge_types[index]).is_empty():
			var edge_type: StringName = _edge_types[index]
			var factor := 1.0
			if edge_type == SectorClassifier.EDGE_INTER:
				factor = 0.6
			elif edge_type == SectorClassifier.EDGE_VOID:
				factor = 0.3
			color = Color(color.r * factor, color.g * factor, color.b * factor, color.a)
		color.a = config.edge_alpha
		draw_line(to_local(edge[0]), to_local(edge[1]), color, config.edge_width, true)

const FOG_VISIBLE := 0
const FOG_FRONTIER := 1
const FOG_HIDDEN := 2

## Returns the most-hidden fog tier across the two endpoints. A waypoint/null
## side (i.e. midpoint of an edge) is treated as FRONTIER so the dim grid is
## still visible along revealed planetary edges.
func _max_fog(endpoints: Array) -> int:
	var result := FOG_VISIBLE
	for endpoint in endpoints:
		if endpoint == null:
			result = maxi(result, FOG_FRONTIER)
			continue
		var planet: Planet = endpoint as Planet
		if planet != null and is_instance_valid(planet):
			var state: int = planet.get_fog_state()
			if state == Planet.FogState.FOG:
				return FOG_HIDDEN
			if state == Planet.FogState.FRONTIER:
				result = maxi(result, FOG_FRONTIER)
	return result

func _add_graph_point(point_position: Vector2) -> int:
	var point_id := _next_point_id
	_next_point_id += 1
	_astar.add_point(point_id, point_position)
	return point_id

func _connect_graph_points(first_id: int, second_id: int) -> void:
	if not _astar.are_points_connected(first_id, second_id):
		_astar.connect_points(first_id, second_id, true)

## Waypoint clearance from every planet in the field. Runs after jitter so the
## rendered position is guaranteed clear (bounded iterative nudge: each pass rc
## away from the nearest infringing planet; handful of passes converges on grid
## layouts and degrades gracefully in dense chunk worlds).
const WAYPOINT_MIN_PLANET_DIST := 56.0

func _clear_of_planets(midpoint: Vector2, planets: Array[Planet]) -> Vector2:
	var result := midpoint
	for _pass in 8:
		var nearest: Planet = null
		var nearest_dist := WAYPOINT_MIN_PLANET_DIST
		for planet in planets:
			if planet == null:
				continue
			var dist: float = result.distance_to(planet.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = planet
		if nearest == null:
			break
		var away := (result - nearest.global_position)
		if away.length() <= 0.0001:
			# On top of the planet: bias along a deterministic axis.
			away = Vector2(1.0, 0.3)
		else:
			away = away.normalized()
		result = nearest.global_position + away * WAYPOINT_MIN_PLANET_DIST
	return result
