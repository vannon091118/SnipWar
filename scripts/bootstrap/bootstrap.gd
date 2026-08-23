extends Node

func _ready() -> void:
	var background: Node2D = get_parent() as Node2D
	if background == null:
		return
	var scenario: ScenarioDefinition = background.get("active_scenario") as ScenarioDefinition
	var final_seed: int = background.get("active_layout_seed")
	var state: Node = GameStateAccess.autoload(self)
	var deal_catalog: PlanetCatalog = background.get("active_catalog") as PlanetCatalog
	if state != null and deal_catalog != null and scenario != null and scenario.map_definition != null:
		var field: Node = background.get_node_or_null("PlanetField")
		var world_config: WorldConfig = field.get("world_config") as WorldConfig if field != null else background.get("world_config") as WorldConfig
		if world_config == null or not world_config.is_infinite_world():
			state.call("deal_resources", deal_catalog, scenario.map_definition.resource_pool, final_seed)
			var local_ids: Array = []
			for definition in deal_catalog.planets:
				if definition != null:
					local_ids.append(definition.planet_id)
			state.call("deal_local_resources", local_ids, scenario.map_definition.resource_pool, final_seed)
