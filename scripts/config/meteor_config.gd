@tool
class_name MeteorConfig
extends Resource

@export var minimum_size_pixels: float
@export var maximum_size_pixels: float
@export var minimum_speed: float
@export var maximum_speed: float

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if minimum_size_pixels <= 0.0 or maximum_size_pixels < minimum_size_pixels:
		errors.append("meteor size range is invalid")
	if minimum_speed < 0.0 or maximum_speed < minimum_speed:
		errors.append("meteor speed range is invalid")
	return errors
