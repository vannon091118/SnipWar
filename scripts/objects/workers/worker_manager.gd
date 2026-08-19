extends Node2D

const CLUSTER_SCENE: PackedScene = preload("res://scenes/objects/workers/worker_cluster.tscn")
const DEFAULT_CONFIG: TransitConfig = preload("res://resources/config/transit_default.tres")
const _Dispatch := preload("res://scripts/dispatch.gd")
const _FlightTime := preload("res://scripts/flight_time.gd")

@export var transit_config: TransitConfig = DEFAULT_CONFIG

func _spawn_clusters(source: Planet, amount: int) -> void:
	source.register_workers(maxi(amount, 0))

func _dispatch_clusters(source: Planet, destination: Planet, amount: int) -> void:
	var dispatch_count := _Dispatch.launch_amount(source.worker_count, amount)
	if dispatch_count <= 0:
		return
	var groups := _Dispatch.cluster_groups(dispatch_count, transit_config)
	if groups.is_empty():
		return
	var source_position := source.global_position
	var destination_position := destination.global_position
	var distance := source_position.distance_to(destination_position)
	var duration := _FlightTime.seconds_for(distance, dispatch_count, transit_config)
	source.unregister_workers(dispatch_count)

	var direction := (destination_position - source_position).normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	var spacing := _formation_spacing(groups)
	var offsets := _formation_offsets(groups.size(), direction, perpendicular, spacing)
	for index in groups.size():
		var cluster: WorkerCluster = CLUSTER_SCENE.instantiate()
		add_child(cluster)
		cluster.configure_transit(source_position + offsets[index], destination, groups[index], transit_config)
		var tween: Tween = cluster.create_tween()
		tween.tween_property(cluster, "global_position", destination_position + offsets[index], duration).set_trans(Tween.TRANS_LINEAR)
		tween.finished.connect(Callable(self, "_arrive_cluster").bind(cluster))

func _arrive_cluster(cluster: WorkerCluster) -> void:
	cluster._arrive()

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

func _formation_spacing(groups: Array[int]) -> float:
	return _cluster_radius(groups) * 2.0 * transit_config.overlap_budget

func _cluster_radius(groups: Array[int]) -> float:
	var max_width := 0.0
	for group in groups:
		max_width = maxf(max_width, WorkerCluster.pixel_width(group, transit_config))
	return max_width * 0.5
