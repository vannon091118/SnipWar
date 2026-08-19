extends Node2D

const CLUSTER_SCENE: PackedScene = preload("res://scenes/objects/workers/worker_cluster.tscn")
# Center-to-center distance ratio for a maximum 30% radial overlap budget.
const OVERLAP_BUDGET := 0.85
const GARRISON_PLANET_RADIUS_FALLBACK := 48.0
const GARRISON_GAP := 6.0
const _Dispatch := preload("res://scripts/dispatch.gd")
const _FlightTime := preload("res://scripts/flight_time.gd")

func _spawn_clusters(source: Planet, amount: int) -> void:
	var groups := _Dispatch.cluster_groups(amount)
	if groups.is_empty():
		return
	var cluster: WorkerCluster = CLUSTER_SCENE.instantiate()
	add_child(cluster)
	cluster.configure_garrison_at(source.global_position, source, groups[0])
	_layout_garrison(source)

func _dispatch_clusters(source: Planet, destination: Planet, amount: int) -> void:
	var dispatch_count := _Dispatch.launch_amount(source.worker_count, amount)
	if dispatch_count <= 0:
		return
	var groups := _Dispatch.cluster_groups(dispatch_count)
	if groups.is_empty():
		return
	var distance := source.global_position.distance_to(destination.global_position)
	var duration := _FlightTime.seconds_for(distance, dispatch_count)
	var garrison := _garrison_clusters(source)
	if not _remove_units(garrison, groups[0]):
		return
	_layout_garrison(source)
	var cluster: WorkerCluster = CLUSTER_SCENE.instantiate()
	add_child(cluster)
	cluster.configure_transit(source.global_position, destination, groups[0])
	var tween: Tween = cluster.create_tween()
	tween.tween_property(cluster, "global_position", destination.global_position, duration).set_trans(Tween.TRANS_LINEAR)
	tween.finished.connect(Callable(self, "_arrive_cluster").bind(cluster))

func _arrive_cluster(cluster: WorkerCluster) -> void:
	var destination := cluster.destination_planet
	cluster._arrive()
	if is_instance_valid(destination):
		_layout_garrison(destination)

func _layout_garrison(source: Planet) -> void:
	var clusters := _garrison_clusters(source)
	if clusters.is_empty():
		return
	var groups: Array[int] = []
	for cluster in clusters:
		groups.append(cluster.get_unit_count())
	var cluster_radius := _cluster_radius(groups)
	var perimeter_radius := _planet_visual_radius(source) + cluster_radius + GARRISON_GAP
	var slot_count := _required_garrison_slots(perimeter_radius, cluster_radius)
	for index in clusters.size():
		var angle := (float(index) / float(slot_count)) * TAU
		clusters[index].global_position = source.global_position + Vector2(cos(angle), sin(angle)) * perimeter_radius

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

static func _cluster_radius(groups: Array[int]) -> float:
	var max_width := 0.0
	for group in groups:
		max_width = maxf(max_width, WorkerCluster.pixel_width(group))
	return max_width * 0.5

static func _required_garrison_slots(perimeter_radius: float, cluster_radius: float) -> int:
	if perimeter_radius <= 0.0 or cluster_radius <= 0.0:
		return 1
	var circumference := TAU * perimeter_radius
	var safe_separation := cluster_radius * 2.0 * OVERLAP_BUDGET
	return maxi(1, ceili(circumference / safe_separation))

static func _planet_visual_radius(planet: Planet) -> float:
	if planet == null:
		return GARRISON_PLANET_RADIUS_FALLBACK
	var sprite := planet.get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or sprite.texture == null:
		return GARRISON_PLANET_RADIUS_FALLBACK
	return sprite.texture.get_width() * 0.5 * absf(planet.scale.x)
