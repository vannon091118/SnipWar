extends Node

func _ready() -> void:
	var field: Node = get_parent().get_node("PlanetField")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	field.layout_seed = rng.randi()
