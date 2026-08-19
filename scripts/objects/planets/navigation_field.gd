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
var _next_point_id := 1
var _rebuild_queued := false
var _is_built := false

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
	_astar = AStar2D.new()
	_next_point_id = 1
	_is_built = false
	_edge_endpoints.clear()

	var planets: Array[Planet] = []
	for child in get_parent().get_children():
		if child is Planet:
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

	var processed_edges: Dictionary = {}
	var edge_index := 0
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
			edge_index += 1
	_is_built = not _point_ids.is_empty()
	queue_redraw()

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
