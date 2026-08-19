extends Node

func _ready() -> void:
	var field: Node = get_parent().get_node("PlanetField")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	field.call("set_layout_seed", rng.randi())
