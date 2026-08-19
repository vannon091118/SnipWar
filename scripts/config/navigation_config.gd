@tool
class_name NavigationConfig
extends Resource

@export var moon_texture: Texture2D
@export var comet_texture: Texture2D
@export var moon_size_pixels: float
@export var comet_size_pixels: float
@export var midpoint_jitter: float
@export var edge_color: Color
@export var edge_alpha: float
@export var edge_width: float
@export_range(1, 10, 1) var comet_every: int

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if moon_texture == null:
		errors.append("navigation moon_texture is missing")
	if comet_texture == null:
		errors.append("navigation comet_texture is missing")
	if moon_size_pixels <= 0.0 or comet_size_pixels <= 0.0:
		errors.append("navigation waypoint sizes must be positive")
	if midpoint_jitter < 0.0:
		errors.append("navigation midpoint_jitter cannot be negative")
	if edge_alpha < 0.0 or edge_alpha > 1.0 or edge_width <= 0.0:
		errors.append("navigation edge styling is invalid")
	if comet_every < 1:
		errors.append("navigation comet_every must be positive")
	return errors
