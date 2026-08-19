extends Node

func _ready() -> void:
	var background: Node2D = get_parent() as Node2D
	if background == null:
		return
	var field: SeededLayout = background.get_node_or_null("PlanetField") as SeededLayout
	var scenario: ScenarioDefinition = background.get("active_scenario") as ScenarioDefinition
	var final_seed := 0
	if scenario != null and scenario.map_definition != null and scenario.map_definition.world_config != null and not scenario.randomize_layout_seed:
		final_seed = scenario.map_definition.world_config.layout_seed
	else:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		final_seed = rng.randi()
	if field != null:
		field.set_layout_seed(final_seed)
	var state: Node = get_tree().root.get_node_or_null("GameState")
	if state != null and scenario != null and scenario.map_definition != null:
		state.call("deal_resources", scenario.map_definition.planet_catalog, scenario.map_definition.resource_pool, final_seed)
