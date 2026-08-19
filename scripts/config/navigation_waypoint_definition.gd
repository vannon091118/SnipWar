@tool
class_name NavigationWaypointDefinition
extends Resource

@export var id: StringName
@export_enum("moon", "comet") var waypoint_type: String = "moon"
@export var texture: Texture2D
@export var size_pixels: float = 16.0
@export_range(1, 32, 1) var every_n_edges: int = 1

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("navigation waypoint definition id is empty")
	if waypoint_type != "moon" and waypoint_type != "comet":
		errors.append("navigation waypoint %s has an invalid type" % id)
	if texture == null:
		errors.append("navigation waypoint %s texture is missing" % id)
	if size_pixels <= 0.0:
		errors.append("navigation waypoint %s size must be positive" % id)
	if every_n_edges < 1:
		errors.append("navigation waypoint %s every_n_edges must be positive" % id)
	return errors
