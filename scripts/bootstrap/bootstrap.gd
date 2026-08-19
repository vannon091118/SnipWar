extends Node

func _ready() -> void:
	var background: Node = get_parent()
	var field: Node = background.get_node("PlanetField")
	var scenario: ScenarioDefinition = background.get("active_scenario") as ScenarioDefinition
	if scenario != null and scenario.map_definition != null and scenario.map_definition.world_config != null and not scenario.randomize_layout_seed:
		field.call("set_layout_seed", scenario.map_definition.world_config.layout_seed)
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	field.call("set_layout_seed", rng.randi())
