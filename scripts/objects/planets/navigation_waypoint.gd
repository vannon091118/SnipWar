@tool
class_name NavigationWaypoint
extends Node2D

var waypoint_type: StringName

func configure(definition: NavigationWaypointDefinition) -> void:
	if definition == null:
		return
	waypoint_type = StringName(definition.waypoint_type)
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite == null or definition.texture == null or definition.texture.get_width() <= 0:
		return
	sprite.texture = definition.texture
	sprite.scale = Vector2.ONE * (definition.size_pixels / float(definition.texture.get_width()))
