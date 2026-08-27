@tool
class_name Sun
extends Node2D

## Visual representation of a cluster's central sun.
## Provides glow effect, mass-based scaling, and gravity visualization.

## Cluster data reference
var cluster_id: StringName
var sun_mass: float = 1.0
var sun_glow_radius: float = 50.0
var sun_color: Color = Color(1.0, 0.9, 0.7)
var sun_temperature: float = 5778.0
var sun_position: Vector2

## Visual properties
@export var glow_intensity: float = 1.0
@export var pulse_speed: float = 0.5
@export var pulse_amplitude: float = 0.1

## Gravity visualization
@export var show_gravity_field: bool = false
@export var gravity_field_opacity: float = 0.1

## Internal state
var _time: float = 0.0

func _ready() -> void:
	queue_redraw()

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	# Draw gravity field (optional)
	if show_gravity_field:
		_draw_gravity_field()

	# Draw glow layers (multiple for soft effect)
	_draw_glow_layer(sun_glow_radius * 1.5, 0.15)
	_draw_glow_layer(sun_glow_radius * 1.2, 0.25)
	_draw_glow_layer(sun_glow_radius * 0.9, 0.4)
	_draw_glow_layer(sun_glow_radius * 0.6, 0.7)

	# Draw core
	_draw_sun_core()

	# Draw corona effects
	_draw_corona()

func _draw_glow_layer(radius: float, opacity: float) -> void:
	var pulse := 1.0 + sin(_time * pulse_speed) * pulse_amplitude * opacity
	var scale_val := sqrt(sun_mass)
	var actual_radius: float = radius * pulse * scale_val
	var color: Color = _get_visual_color()
	color.a = opacity * glow_intensity
	draw_circle(Vector2.ZERO, actual_radius, color)

func _draw_sun_core() -> void:
	var scale_val := sqrt(sun_mass)
	var core_radius: float = 8.0 * scale_val
	var color: Color = _get_visual_color()
	draw_circle(Vector2.ZERO, core_radius, color)

	# Bright center
	var bright_color := Color(1.0, 1.0, 1.0, 0.8)
	draw_circle(Vector2.ZERO, core_radius * 0.5, bright_color)

func _draw_corona() -> void:
	# Simplified corona spikes
	var spike_count := 8
	var scale_val := sqrt(sun_mass)
	var spike_radius: float = sun_glow_radius * 0.3 * scale_val
	var color: Color = _get_visual_color()
	color.a = 0.3

	for i in spike_count:
		var angle := (float(i) / float(spike_count)) * TAU + _time * 0.1
		var length := spike_radius * (0.8 + sin(_time * 2.0 + float(i)) * 0.2)
		var tip := Vector2(cos(angle), sin(angle)) * length
		var width := length * 0.1
		var perpendicular := Vector2(-sin(angle), cos(angle)) * width

		var points := PackedVector2Array([
			perpendicular,
			tip,
			-perpendicular
		])
		draw_colored_polygon(points, color)

func _draw_gravity_field() -> void:
	var influence_radius: float = sun_glow_radius * 2.0
	var color := Color(0.3, 0.3, 0.5, gravity_field_opacity)

	# Draw gravity rings
	for i in 5:
		var ring_radius: float = influence_radius * (float(i + 1) / 5.0)
		var ring_color := color
		ring_color.a *= (1.0 - float(i) / 5.0)
		draw_arc(Vector2.ZERO, ring_radius, 0, TAU, 64, ring_color, 1.0)

func configure_cluster(p_cluster_id: StringName, p_mass: float, p_glow: float, p_temp: float, p_pos: Vector2) -> void:
	cluster_id = p_cluster_id
	sun_mass = p_mass
	sun_glow_radius = p_glow
	sun_temperature = p_temp
	sun_position = p_pos
	position = p_pos
	scale = Vector2.ONE * sqrt(sun_mass)
	queue_redraw()

func set_gravity_visualization(enabled: bool) -> void:
	show_gravity_field = enabled
	queue_redraw()

func get_gravity_influence() -> float:
	return sun_glow_radius * 2.0

func _get_visual_color() -> Color:
	## Color based on temperature (simplified blackbody)
	if sun_temperature < 3500.0:
		return Color(1.0, 0.6, 0.4)  # Red dwarf
	elif sun_temperature < 5000.0:
		return Color(1.0, 0.8, 0.6)  # Orange
	elif sun_temperature < 6000.0:
		return Color(1.0, 0.95, 0.8)  # Yellow-white (like our sun)
	elif sun_temperature < 10000.0:
		return Color(0.8, 0.9, 1.0)  # Blue-white
	else:
		return Color(0.6, 0.7, 1.0)  # Blue giant
