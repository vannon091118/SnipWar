@tool
class_name PlanetDetailRing
extends Node2D

var radius := 104.0
var ring_color := Color(0.92, 0.34, 0.38, 0.72)
var ring_width := 3.0
var _pulse := 0.0

func configure(next_radius: float, color: Color) -> void:
	radius = next_radius
	ring_color = color
	queue_redraw()

func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta, TAU)
	queue_redraw()

func _draw() -> void:
	var alpha := 0.58 + sin(_pulse * 1.5) * 0.12
	var color := Color(ring_color, alpha)
	draw_set_transform(Vector2.ZERO, -0.16, Vector2(1.0, 0.42))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, color, ring_width, true)
