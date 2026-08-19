extends Node2D

const WORKER_SCENE: PackedScene = preload("res://scenes/objects/workers/worker.tscn")
const _Dispatch := preload("res://scripts/dispatch.gd")
const _FlightTime := preload("res://scripts/flight_time.gd")

@onready var _network: Node = get_parent().get_node("PlanetNetwork")

func _ready() -> void:
	for planet in get_parent().get_children():
		if planet is Node2D and planet.get("layout_size") != null:
			planet.workers_spawn_requested.connect(_spawn_workers)

func _spawn_workers(source: Node2D, amount: int) -> void:
	var destination: Node2D = _network.get_destination(source)
	if destination == null:
		return
	for index in amount:
		var worker: Node2D = WORKER_SCENE.instantiate()
		add_child(worker)
		worker.configure(source, destination)

func _dispatch_workers(source: Node2D, amount: int) -> void:
	var destination: Node2D = _network.get_destination(source)
	if destination == null:
		return
	var dispatch_count := _Dispatch.launch_amount(int(source.get("worker_count")), amount)
	if dispatch_count <= 0:
		return
	var duration := _FlightTime.seconds_for(source.global_position.distance_to(destination.global_position), dispatch_count)
	var launched := 0
	for worker in _workers_of(source):
		if launched >= dispatch_count:
			break
		worker.begin_flight(destination)
		var tween := worker.create_tween()
		tween.tween_property(worker, "global_position", destination.global_position, duration).set_trans(Tween.TRANS_LINEAR)
		tween.finished.connect(Callable(worker, "_arrive"))
		launched += 1

func _workers_of(source: Node2D) -> Array[Node2D]:
	var result: Array[Node2D] = []
	for child in get_children():
		if child is Node2D and child.get("_registered_planet") == source:
			result.append(child)
	return result
