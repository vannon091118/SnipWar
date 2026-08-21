extends Node

func _ready() -> void:
	var background: Node2D = get_parent() as Node2D
	if background == null:
		return
	var scenario: ScenarioDefinition = background.get("active_scenario") as ScenarioDefinition
	var final_seed: int = background.get("active_layout_seed")
	var state: Node = get_tree().root.get_node_or_null("GameState")
	var deal_catalog: PlanetCatalog = background.get("active_catalog") as PlanetCatalog
	if state != null and deal_catalog != null and scenario != null and scenario.map_definition != null:
		state.call("deal_resources", deal_catalog, scenario.map_definition.resource_pool, final_seed)
