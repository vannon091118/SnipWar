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
var _next_point_id := 1
var _rebuild_queued := false
var _is_built := false

func _ready() -> void:
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

	var planets: Array[Planet] = []
	for child in get_parent().get_children():
		if child is Planet:
			planets.append(child)
	if planets.size() < 2:
			queue_redraw()
			return

	var config: WorldConfig = _resolved_world_config()
	var waypoint_config: NavigationConfig = navigation_config if navigation_config != null else DEFAULT_NAVIGATION_CONFIG
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(config.layout_seed) + 9137
	for planet in planets:
		_point_ids[planet] = _add_graph_point(planet.global_position)

	var edge_index := 0
	for first_index in planets.size():
		for second_index in range(first_index + 1, planets.size()):
			var first: Planet = planets[first_index]
			var second: Planet = planets[second_index]
			if not _are_layout_neighbors(first, second, config.columns):
				continue
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
	var edge_color := config.edge_color
	edge_color.a = config.edge_alpha
	for edge in _edges:
		if edge.size() == 2:
			draw_line(to_local(edge[0]), to_local(edge[1]), edge_color, config.edge_width, true)

func _add_graph_point(position: Vector2) -> int:
	var point_id := _next_point_id
	_next_point_id += 1
	_astar.add_point(point_id, position)
	return point_id

func _connect_graph_points(first_id: int, second_id: int) -> void:
	if not _astar.are_points_connected(first_id, second_id):
		_astar.connect_points(first_id, second_id, true)

func _are_layout_neighbors(first: Planet, second: Planet, columns: int) -> bool:
	var first_slot: int = int(first.get_meta("layout_slot", -1))
	var second_slot: int = int(second.get_meta("layout_slot", -1))
	if first_slot < 0 or second_slot < 0:
		return false
	var safe_columns := maxi(columns, 1)
	var first_row := floori(float(first_slot) / float(safe_columns))
	var first_column := first_slot % safe_columns
	var second_row := floori(float(second_slot) / float(safe_columns))
	var second_column := second_slot % safe_columns
	return absi(first_row - second_row) + absi(first_column - second_column) == 1
