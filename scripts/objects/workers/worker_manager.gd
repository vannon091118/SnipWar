extends Node2D

const WORKER_SCENE: PackedScene = preload("res://scenes/objects/workers/worker.tscn")

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
