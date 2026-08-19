@tool
class_name NavigationConfig
extends Resource

@export var waypoint_catalog: NavigationWaypointCatalog
@export var midpoint_jitter: float
@export var edge_color: Color
@export var edge_alpha: float
@export var edge_width: float
## K-nearest graph neighbor ratio. NavigationField defaults to its parent
## WorldConfig when this value is left at <= 0 (lets the world own the
## percentage).
@export_range(-1.0, 0.5, 0.005) var graph_neighbor_ratio: float = -1.0
## Hard cap on K-nearest edges. 0 inherits WorldConfig.max_extra_edges or
## disables the cap. Negative means "no cap".
@export var max_extra_edges_override: int = -1

func waypoint_for_edge(edge_index: int) -> NavigationWaypointDefinition:
	if waypoint_catalog == null:
		return null
	return waypoint_catalog.definition_for_edge(edge_index)

## Returns the K-nearest ratio after merging WorldConfig defaults.
func resolved_graph_neighbor_ratio(world_config: WorldConfig) -> float:
	if graph_neighbor_ratio < 0.0:
		if world_config == null:
			return 0.0
		return world_config.resolved_graph_neighbor_ratio()
	return clampf(graph_neighbor_ratio, 0.0, 0.5)

## Returns the absolute edge cap. -1 means inherit WorldConfig.
func resolved_max_extra_edges(world_config: WorldConfig) -> int:
	if max_extra_edges_override == 0:
		return 0
	if max_extra_edges_override > 0:
		return max_extra_edges_override
	if world_config == null:
		return 0
	return world_config.resolved_max_extra_edges()

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if waypoint_catalog == null:
		errors.append("navigation waypoint_catalog is missing")
	else:
		for catalog_error in waypoint_catalog.validate():
			errors.append("navigation catalog: " + catalog_error)
	if midpoint_jitter < 0.0:
		errors.append("navigation midpoint_jitter cannot be negative")
	if edge_alpha < 0.0 or edge_alpha > 1.0 or edge_width <= 0.0:
		errors.append("navigation edge styling is invalid")
	if graph_neighbor_ratio > 0.5:
		errors.append("navigation graph_neighbor_ratio must stay at or below 0.5")
	if max_extra_edges_override < -1:
		errors.append("navigation max_extra_edges_override must stay at -1 or higher")
	return errors
