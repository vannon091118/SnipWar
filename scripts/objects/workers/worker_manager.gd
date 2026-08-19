extends Node2D

const CLUSTER_SCENE: PackedScene = preload("res://scenes/objects/workers/worker_cluster.tscn")
const FLEET_SPACING := 14.0
const _Dispatch := preload("res://scripts/dispatch.gd")
const _FlightTime := preload("res://scripts/flight_time.gd")

func _spawn_clusters(source: Planet, amount: int) -> void:
	for group_size in _Dispatch.cluster_groups(amount):
		var cluster: WorkerCluster = CLUSTER_SCENE.instantiate()
		add_child(cluster)
		cluster.configure_garrison(source, group_size)

func _dispatch_clusters(source: Planet, destination: Planet, amount: int) -> void:
	var dispatch_count := _Dispatch.launch_amount(source.worker_count, amount)
	if dispatch_count <= 0:
		return
	var source_position := source.global_position
	var distance := source_position.distance_to(destination.global_position)
	var duration := _FlightTime.seconds_for(distance, dispatch_count)
	var garrison := _garrison_clusters(source)
	var groups := _Dispatch.cluster_groups(dispatch_count)
	var direction := (destination.global_position - source_position).normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	var fleet_offsets := _fleet_offsets(groups.size(), perpendicular)
	var index := 0
	for group_size in groups:
		if not _remove_units(garrison, group_size):
			return
		var cluster: WorkerCluster = CLUSTER_SCENE.instantiate()
		var start_position := source_position + fleet_offsets[index]
		add_child(cluster)
		cluster.configure_transit(start_position, destination, group_size)
		var tween: Tween = cluster.create_tween()
		tween.tween_property(cluster, "global_position", destination.global_position, duration).set_trans(Tween.TRANS_LINEAR)
		tween.finished.connect(Callable(cluster, "_arrive"))
		index += 1

func _fleet_offsets(count: int, perpendicular: Vector2) -> Array[Vector2]:
	var offsets: Array[Vector2] = []
	if count <= 1:
		offsets.append(Vector2.ZERO)
		return offsets
	var half_span := float(count - 1) * 0.5
	for index in count:
		offsets.append(perpendicular * (float(index) - half_span) * FLEET_SPACING)
	return offsets

func _garrison_clusters(source: Planet) -> Array[WorkerCluster]:
	var result: Array[WorkerCluster] = []
	for child in get_children():
		if child is WorkerCluster and child.is_registered_at(source):
			result.append(child)
	return result

func _remove_units(clusters: Array[WorkerCluster], amount: int) -> bool:
	var remaining := amount
	for cluster in clusters:
		if remaining <= 0:
			break
		if not is_instance_valid(cluster):
			continue
		remaining -= cluster.remove_units(remaining)
	return remaining == 0
