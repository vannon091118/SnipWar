extends Node2D

const CLUSTER_SCENE: PackedScene = preload("res://scenes/objects/workers/worker_cluster.tscn")
const DEFAULT_CONFIG: TransitConfig = preload("res://resources/config/transit_default.tres")
const _Dispatch := preload("res://scripts/dispatch.gd")
const _FlightTime := preload("res://scripts/flight_time.gd")

@export var transit_config: TransitConfig = DEFAULT_CONFIG

func _process(_delta: float) -> void:
	# WorkerCluster nodes are visual projections. Recreate a missing projection
	# from the GameState record after chunk eviction or a world reconnect.
	var state: Node = _game_state()
	if state == null or not state.has_method("get_worker_transport_records"):
		return
	for record in state.get_worker_transport_records(GameState.FACTION_PLAYER):
		var transport_id: StringName = record.get("transport_id", &"") as StringName
		if String(transport_id).is_empty() or _has_transport_cluster(transport_id):
			continue
		_restore_transport_record(record)

func _has_transport_cluster(transport_id: StringName) -> bool:
	for child in get_children():
		var cluster: WorkerCluster = child as WorkerCluster
		if cluster != null and is_instance_valid(cluster) and cluster.get_meta("transport_id", &"") == transport_id:
			return true
	return false

func _restore_transport_record(record: Dictionary) -> void:
	var source: Planet = _find_planet(record.get("source_planet_id", &"") as StringName)
	var destination: Planet = _find_planet(record.get("destination_planet_id", &"") as StringName)
	if source == null or destination == null:
		return
	var path: Array[Vector2] = []
	for point in record.get("route_path", []):
		if point is Vector2:
			path.append(point as Vector2)
	if path.size() < 2:
		path = [source.global_position, destination.global_position]
	var cluster: WorkerCluster = CLUSTER_SCENE.instantiate()
	add_child(cluster)
	var amount: int = int(record.get("amount", 0))
	cluster.configure_transit(path[0], destination, amount, record.get("faction", GameState.FACTION_PLAYER) as StringName, transit_config, GameState.MISSION_COLLECT, source.get_cluster_tier_bonus(), source.planet_id)
	cluster.set_meta("transport_id", record.get("transport_id", &"") as StringName)
	var phase: StringName = record.get("phase", &"outbound") as StringName
	var effective_path := path if phase == &"outbound" else path.duplicate()
	if phase != &"outbound":
		effective_path.reverse()
	cluster.configure_roundtrip(path, float(record.get("duration", 1.0)))
	if phase == &"returning":
		cluster.set_cargo(record.get("cargo_resource_id", &"") as StringName, int(record.get("cargo_amount", 0)))
		cluster.begin_return()
	else:
		cluster.global_position = effective_path[0]
	var distance: float = _path_distance(effective_path)
	var duration: float = maxf(float(record.get("duration", 1.0)), 0.001)
	var tween := cluster.create_tween()
	for index in range(1, effective_path.size()):
		var segment: float = effective_path[index - 1].distance_to(effective_path[index])
		tween.tween_property(cluster, "global_position", effective_path[index], duration * segment / maxf(distance, 0.001)).set_trans(Tween.TRANS_LINEAR)
	if phase == &"returning":
		tween.finished.connect(Callable(self, "_on_worker_returned").bind(cluster))
	else:
		tween.finished.connect(Callable(self, "_arrive_cluster").bind(cluster))

func _find_planet(planet_id: StringName) -> Planet:
	var field: Node = get_parent()
	if field == null:
		return null
	for child in field.get_children():
		var planet: Planet = child as Planet
		if planet != null and planet.planet_id == planet_id:
			return planet
	return null

func _spawn_clusters(source: Planet, amount: int) -> void:
	source.register_workers(maxi(amount, 0))

func dispatch_mission(source: Planet, destination: Planet, amount: int, route_path: Array[Vector2] = [], mission_type: StringName = &"military") -> void:
	_dispatch_clusters(source, destination, amount, route_path, mission_type)

## True when the player already has an active transport targeting `planet_id`.
## Sprint 6 (S9): at most one dispatch order per destination planet — the UI
## disables the send button while a mission is in flight.
func has_active_order(planet_id: StringName) -> bool:
	if String(planet_id).is_empty():
		return false
	var state: Node = _game_state()
	if state == null or not state.has_method("get_worker_transport_records"):
		return false
	for record in state.get_worker_transport_records(GameState.FACTION_PLAYER):
		if (record.get("destination_planet_id", &"") as StringName) == planet_id:
			return true
	return false

func can_dispatch_mission(source: Planet, destination: Planet, mission_type: StringName = &"military") -> bool:
	if source == null or destination == null or source == destination:
		return false
	if mission_type != GameState.MISSION_COLLECT:
		return true
	var state: Node = _game_state()
	if state == null or source.get_faction() == GameState.FACTION_NEUTRAL:
		return false
	# Sprint 6 (S5): uninhabited worlds have no stock to harvest — collecting
	# from them is pointless until they are colonized.
	if state.has_method("is_uninhabited") and state.is_uninhabited(destination.planet_id):
		return false
	return destination.get_faction() == GameState.FACTION_NEUTRAL and state.has_scanned_planet(source.get_faction(), destination.planet_id)

func _dispatch_clusters(source: Planet, destination: Planet, amount: int, route_path: Array[Vector2] = [], mission_type: StringName = &"military") -> void:
	if not can_dispatch_mission(source, destination, mission_type):
		return
	var state: Node = _game_state()
	var available_workers: int = source.worker_count
	if state != null and state.has_method("get_available_workers"):
		available_workers = state.get_available_workers(source.planet_id, source.worker_count)
	var dispatch_count := _Dispatch.launch_amount(available_workers, amount)
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
		cluster.configure_transit(offset_path[0], destination, groups[index], source_faction, transit_config, mission_type, cluster_tier_bonus, source.planet_id)
		cluster.configure_roundtrip(offset_path, duration)
		if mission_type == GameState.MISSION_COLLECT and state != null and state.has_method("begin_worker_transport"):
			var transport_id: StringName = state.begin_worker_transport(source_faction, source.planet_id, destination.planet_id, groups[index], duration, offset_path)
			if not String(transport_id).is_empty():
				cluster.set_meta("transport_id", transport_id)
				var conflict_manager: Node = get_parent().get_node_or_null("ConflictManager") if get_parent() != null else null
				if conflict_manager != null and conflict_manager.has_method("has_escort_available") and conflict_manager.has_escort_available(source, destination):
					state.set_worker_transport_escorted(transport_id, true)
					state.mark_milestone(source_faction, &"first_escort")
		var tween: Tween = cluster.create_tween()
		for point_index in range(1, offset_path.size()):
			var segment_distance: float = offset_path[point_index - 1].distance_to(offset_path[point_index])
			var segment_duration: float = duration * segment_distance / offset_distance if offset_distance > 0.0 else 0.0
			tween.tween_property(cluster, "global_position", offset_path[point_index], segment_duration).set_trans(Tween.TRANS_LINEAR)
		tween.finished.connect(Callable(self, "_arrive_cluster").bind(cluster))

func _arrive_cluster(cluster: WorkerCluster) -> StringName:
	if cluster == null or not is_instance_valid(cluster):
		return Planet.ARRIVAL_REJECTED
	if cluster.mission_type != GameState.MISSION_COLLECT:
		# Worker clusters stay count-only for military/colony/cargo legacy paths.
		return cluster._arrive()
	var state: Node = _game_state()
	var destination: Planet = cluster.destination_planet
	if state == null or destination == null or not is_instance_valid(destination):
		_complete_transport_record(cluster, false)
		_return_workers_to_source(cluster)
		return Planet.ARRIVAL_REJECTED
	if state.has_method("update_worker_transport"):
		state.update_worker_transport(_transport_id(cluster), &"loading")
	var resource_id: StringName = state.resource_of(destination.planet_id)
	var base_amount: int = maxi(destination.get_size_profile().resource_base, 1)
	var requested: int = maxi(cluster.unit_count * base_amount, 1)
	var available: int = state.get_local_resource(destination.planet_id, resource_id) if not String(resource_id).is_empty() else 0
	var loaded: int = mini(requested, available)
	if loaded <= 0 or not state.spend_local_resource(destination.planet_id, resource_id, loaded):
		_complete_transport_record(cluster, false)
		_return_workers_to_source(cluster)
		cluster.arrival_result = Planet.ARRIVAL_REJECTED
		cluster.queue_free()
		return cluster.arrival_result
	cluster.set_cargo(resource_id, loaded)
	if state.has_method("update_worker_transport"):
		state.update_worker_transport(_transport_id(cluster), &"returning", resource_id, loaded)
	cluster.begin_return()
	var return_tween: Tween = cluster.create_tween()
	var return_path: Array[Vector2] = cluster._return_path
	var return_distance: float = _path_distance(return_path)
	for point_index in range(1, return_path.size()):
		var segment_distance: float = return_path[point_index - 1].distance_to(return_path[point_index])
		var segment_duration: float = cluster._return_duration * segment_distance / return_distance if return_distance > 0.0 else 0.0
		return_tween.tween_property(cluster, "global_position", return_path[point_index], segment_duration).set_trans(Tween.TRANS_LINEAR)
	return_tween.finished.connect(Callable(self, "_on_worker_returned").bind(cluster))
	return Planet.ARRIVAL_COLLECTED

func _on_worker_returned(cluster: WorkerCluster) -> void:
	if cluster == null or not is_instance_valid(cluster):
		return
	var state: Node = _game_state()
	cluster.mark_delivered()
	if state != null and cluster.cargo_amount > 0:
		state.credit_transport_resources(cluster.source_faction, cluster.cargo_resource_id, cluster.cargo_amount)
	_complete_transport_record(cluster, true)
	_return_workers_to_source(cluster)
	cluster.queue_free()

func _transport_id(cluster: WorkerCluster) -> StringName:
	if cluster == null or not cluster.has_meta("transport_id"):
		return &""
	return cluster.get_meta("transport_id") as StringName

func _complete_transport_record(cluster: WorkerCluster, delivered: bool) -> void:
	var transport_id: StringName = _transport_id(cluster)
	var state: Node = _game_state()
	if state != null and not String(transport_id).is_empty() and state.has_method("complete_worker_transport"):
		state.complete_worker_transport(transport_id, delivered)

func _return_workers_to_source(cluster: WorkerCluster) -> void:
	if cluster == null:
		return
	var field: Node = get_parent()
	if field == null:
		return
	for child in field.get_children():
		var planet: Planet = child as Planet
		if planet != null and planet.planet_id == cluster.source_planet_id:
			planet.register_workers(cluster.unit_count)
			return

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
	return PathUtils.distance(path)

func _game_state() -> Node:
	return GameStateAccess.autoload(self)
