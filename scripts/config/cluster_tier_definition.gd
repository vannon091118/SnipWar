@tool
class_name ClusterTierDefinition
extends Resource

@export var id: StringName
@export_range(1, 1000000, 1) var capacity: int
@export_range(1, 1000000, 1) var display_max_units: int
@export_range(0.1, 1000.0, 0.1) var visible_pixels: float
@export var texture: Texture2D

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if String(id).is_empty():
		errors.append("cluster tier id is empty")
	if capacity < 1:
		errors.append("cluster tier capacity must be positive")
	if display_max_units < 1:
		errors.append("cluster tier display_max_units must be positive")
	if visible_pixels <= 0.0:
		errors.append("cluster tier visible_pixels must be positive")
	if texture == null:
		errors.append("cluster tier texture is missing")
	return errors
