@tool
class_name PlanetDetailOrbit
extends Node2D

var orbit_radius := 110.0
var angular_speed := 0.2
var orbit_motion_mode: String = PlanetDetailFidelity.MOTION_FULL
var orbit_update_interval := 0.0
var _angle := 0.0
var _pending_delta := 0.0

func configure(radius: float, speed: float, phase: float, fidelity: PlanetDetailFidelity = null) -> void:
	orbit_radius = radius
	angular_speed = speed
	_angle = phase
	_pending_delta = 0.0
	orbit_motion_mode = PlanetDetailFidelity.MOTION_FULL
	orbit_update_interval = 0.0
	if fidelity != null:
		orbit_motion_mode = fidelity.orbit_motion_mode
		orbit_update_interval = fidelity.orbit_update_interval
	rotation = _angle

func set_sprite(texture: Texture2D, size_pixels: float) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	var texture_width: float = texture.get_width()
	sprite.scale = Vector2.ONE * (size_pixels / texture_width)
	sprite.position = Vector2(orbit_radius, 0.0)
	add_child(sprite)

func _process(delta: float) -> void:
	if orbit_motion_mode == PlanetDetailFidelity.MOTION_STATIC:
		return
	var update_delta: float = delta
	if orbit_motion_mode == PlanetDetailFidelity.MOTION_THROTTLED:
		_pending_delta += delta
		if _pending_delta < orbit_update_interval:
			return
		update_delta = _pending_delta
		_pending_delta = 0.0
	_angle = fmod(_angle + angular_speed * update_delta, TAU)
	rotation = _angle
