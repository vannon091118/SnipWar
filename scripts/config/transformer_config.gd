@tool
class_name TransformerConfig
extends Resource

# Tint-Farben nach Modus
@export var faction_player_tint: Color = Color(0.3, 0.7, 1.0)
@export var faction_cpu_tint: Color = Color(1.0, 0.4, 0.4)
@export var faction_neutral_tint: Color = Color(0.8, 0.8, 0.8)
@export var resource_tint: Color = Color(0.95, 0.8, 0.3)

# Orbit-Generierungs-Algorithmus
@export_range(50.0, 500.0, 1.0) var base_orbit_radius: float = 130.0
@export_range(1.0, 100.0, 0.5) var orbit_radius_step: float = 15.0
@export_range(0.0, 5.0, 0.01) var orbit_angular_speed: float = 0.4
@export_range(0.0, 10.0, 0.01) var orbit_phase_step: float = 1.2
@export_range(4.0, 128.0, 1.0) var sprite_size: float = 24.0
@export_range(0.0, 60.0, 1.0) var faction_ring_margin: float = 10.0
@export_range(1.0, 16.0, 0.5) var faction_ring_width: float = 4.0
@export_range(0.1, 1.0, 0.01) var planet_visual_radius_ratio: float = 0.375
@export_range(6, 96, 1) var strength_label_font_size: int = 15
@export_range(0, 16, 1) var strength_label_outline_size: int = 3
@export var strength_label_outline_color: Color = Color(0.0, 0.0, 0.0, 0.9)
@export var strength_label_size: Vector2 = Vector2(80.0, 22.0)
@export_range(0.0, 60.0, 0.5) var strength_label_offset_y: float = 6.0

func resolve_tint(tint_mode: StringName, faction: StringName) -> Color:
	match tint_mode:
		&"faction":
			match faction:
				&"a":
					return faction_player_tint
				&"b":
					return faction_cpu_tint
				_:
					return faction_neutral_tint
		&"resource":
			return resource_tint
		_:
			return Color.WHITE

func orbit_radius_for_child_count(child_count: int) -> float:
	return base_orbit_radius + float(child_count) * orbit_radius_step

func orbit_phase_for_child_count(child_count: int) -> float:
	return float(child_count) * orbit_phase_step

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if base_orbit_radius <= 0.0:
		errors.append("transformer base_orbit_radius must be positive")
	if orbit_radius_step < 0.0:
		errors.append("transformer orbit_radius_step cannot be negative")
	if orbit_angular_speed < 0.0:
		errors.append("transformer orbit_angular_speed cannot be negative")
	if sprite_size <= 0.0:
		errors.append("transformer sprite_size must be positive")
	if faction_ring_margin < 0.0:
		errors.append("transformer faction_ring_margin cannot be negative")
	if faction_ring_width <= 0.0:
		errors.append("transformer faction_ring_width must be positive")
	if planet_visual_radius_ratio <= 0.0 or planet_visual_radius_ratio > 1.0:
		errors.append("transformer planet_visual_radius_ratio must be within (0, 1]")
	if strength_label_font_size < 1:
		errors.append("transformer strength_label_font_size must be positive")
	if strength_label_outline_size < 0:
		errors.append("transformer strength_label_outline_size cannot be negative")
	if strength_label_size.x <= 0.0 or strength_label_size.y <= 0.0:
		errors.append("transformer strength_label_size must be positive")
	if strength_label_offset_y < 0.0:
		errors.append("transformer strength_label_offset_y cannot be negative")
	return errors
