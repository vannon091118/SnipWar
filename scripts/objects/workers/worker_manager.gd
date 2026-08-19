extends Node2D

const CLUSTER_SCENE: PackedScene = preload("res://scenes/objects/workers/worker_cluster.tscn")
const DEFAULT_CONFIG: TransitConfig = preload("res://resources/config/transit_default.tres")
const _Dispatch := preload("res://scripts/dispatch.gd")
const _FlightTime := preload("res://scripts/flight_time.gd")

@export var transit_config: TransitConfig = DEFAULT_CONFIG

func _spawn_clusters(source: Planet, amount: int) -> void:
	source.register_workers(maxi(amount, 0))

func dispatch_mission(source: Planet, destination: Planet, amount: int, route_path: Array[Vector2] = [], mission_type: StringName = &"military") -> void:
	_dispatch_clusters(source, destination, amount, route_path, mission_type)

func _dispatch_clusters(source: Planet, destination: Planet, amount: int, route_path: Array[Vector2] = [], mission_type: StringName = &"military") -> void:
	var dispatch_count := _Dispatch.launch_amount(source.worker_count, amount)
	if dispatch_count <= 0:
		return
	var groups := _Dispatch.cluster_groups(dispatch_count, transit_config)
	if groups.is_empty():
		return
	var source_position := source.global_position
	var destination_position := destination.global_position
	var source_faction: StringName = source.get_faction()
	var cluster_tier_bonus: int = source.get_cluster_tier_bonus()
	var resolved_path: Array[Vector2] = route_path if route_path.size() >= 2 else [source_position, destination_position]
	var distance := _path_distance(resolved_path)
	var duration := _FlightTime.seconds_for(distance, dispatch_count, transit_config, source.get_transfer_speed_multiplier())
	source.unregister_workers(dispatch_count)

	var direction := (destination_position - source_position).normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	var spacing := _formation_spacing(groups, cluster_tier_bonus)
	var offsets := _formation_offsets(groups.size(), direction, perpendicular, spacing)
	for index in groups.size():
		var cluster: WorkerCluster = CLUSTER_SCENE.instantiate()
		add_child(cluster)
		var offset_path: Array[Vector2] = []
		for point in resolved_path:
			offset_path.append(point + offsets[index])
		var offset_distance: float = _path_distance(offset_path)
		cluster.configure_transit(offset_path[0], destination, groups[index], source_faction, transit_config, mission_type, cluster_tier_bonus)
		var tween: Tween = cluster.create_tween()
		for point_index in range(1, offset_path.size()):
			var segment_distance: float = offset_path[point_index - 1].distance_to(offset_path[point_index])
			var segment_duration: float = duration * segment_distance / offset_distance if offset_distance > 0.0 else 0.0
			tween.tween_property(cluster, "global_position", offset_path[point_index], segment_duration).set_trans(Tween.TRANS_LINEAR)
		tween.finished.connect(Callable(self, "_arrive_cluster").bind(cluster))

func _arrive_cluster(cluster: WorkerCluster) -> StringName:
	return cluster._arrive()

func _formation_offsets(count: int, direction: Vector2, perpendicular: Vector2, spacing: float) -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	if count <= 1:
		offsets.append(Vector2.ZERO)
		return offsets
	var center := float(count - 1) * 0.5
	for index in count:
		var lateral := (float(index) - center) * spacing
		var depth := absf(float(index) - center) * spacing * transit_config.formation_depth_ratio
		offsets.append(perpendicular * lateral - direction * depth)
	return offsets

func _formation_spacing(groups: Array[int], tier_bonus: int = 0) -> float:
	return _cluster_radius(groups, tier_bonus) * 2.0 * transit_config.overlap_budget

func _cluster_radius(groups: Array[int], tier_bonus: int = 0) -> float:
	var max_width := 0.0
	for group in groups:
		max_width = maxf(max_width, WorkerCluster.pixel_width(group, transit_config, tier_bonus))
	return max_width * 0.5

func _path_distance(path: Array[Vector2]) -> float:
	var distance := 0.0
	for index in range(path.size() - 1):
		distance += path[index].distance_to(path[index + 1])
	return distance
