extends Node2D

const WORKER_SCENE: PackedScene = preload("res://scenes/objects/workers/worker.tscn")
const _Dispatch := preload("res://scripts/dispatch.gd")
const _FlightTime := preload("res://scripts/flight_time.gd")

func _spawn_workers(source: Node2D, destination: Node2D, amount: int) -> void:
	if destination == null:
		return
	for index in amount:
		var worker: Node2D = WORKER_SCENE.instantiate()
		add_child(worker)
		worker.configure(source, destination)

func _dispatch_workers(source: Node2D, destination: Node2D, amount: int) -> void:
	if destination == null:
		return
	var dispatch_count := _Dispatch.launch_amount(int(source.get("worker_count")), amount)
	var duration := _FlightTime.seconds_for(source.global_position.distance_to(destination.global_position), dispatch_count)
	var departing: Array[Node2D] = []
	for child in get_children():
		if child is Node2D and child.get("_registered_planet") == source:
			departing.append(child as Node2D)
	for worker in departing.slice(0, dispatch_count):
		worker.begin_flight(destination)
		var tween: Tween = worker.create_tween()
		tween.tween_property(worker, "global_position", destination.global_position, duration).set_trans(Tween.TRANS_LINEAR)
		tween.finished.connect(Callable(worker, "_arrive"))
