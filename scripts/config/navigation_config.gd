@tool
class_name NavigationConfig
extends Resource

@export var waypoint_catalog: NavigationWaypointCatalog
@export var midpoint_jitter: float
@export var edge_color: Color
@export var edge_alpha: float
@export var edge_width: float

func waypoint_for_edge(edge_index: int) -> NavigationWaypointDefinition:
	if waypoint_catalog == null:
		return null
	return waypoint_catalog.definition_for_edge(edge_index)

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
	return errors
