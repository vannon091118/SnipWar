@tool
class_name NavigationWaypoint
extends Node2D

var waypoint_type: StringName

func configure(type: StringName, texture: Texture2D, size_pixels: float) -> void:
	waypoint_type = type
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or texture == null or texture.get_width() <= 0:
		return
	sprite.texture = texture
	sprite.scale = Vector2.ONE * (size_pixels / float(texture.get_width()))
