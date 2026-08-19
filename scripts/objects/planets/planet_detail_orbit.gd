@tool
class_name PlanetDetailOrbit
extends Node2D

var orbit_radius := 110.0
var angular_speed := 0.2
var _angle := 0.0

func configure(radius: float, speed: float, phase: float) -> void:
	orbit_radius = radius
	angular_speed = speed
	_angle = phase
	rotation = _angle

func set_sprite(texture: Texture2D, size_pixels: float) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	var texture_width: float = texture.get_width()
	sprite.scale = Vector2.ONE * (size_pixels / texture_width)
	sprite.position = Vector2(orbit_radius, 0.0)
	add_child(sprite)

func _process(delta: float) -> void:
	_angle = fmod(_angle + angular_speed * delta, TAU)
	rotation = _angle
