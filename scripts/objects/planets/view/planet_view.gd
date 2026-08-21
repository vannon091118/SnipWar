class_name PlanetView

## Visual drawing and styling helper for Planet nodes (faction rings, selection outlines, and strength indicators).

static func calculate_faction_ring_radius(sprite: Sprite2D, config: TransformerConfig) -> float:
	if sprite == null or not is_instance_valid(sprite) or sprite.texture == null:
		return 0.0
	var resolved_config := config if config != null else Planet.DEFAULT_TRANSFORMER_CONFIG
	var planet_visual_radius: float = float(sprite.texture.get_width()) * resolved_config.planet_visual_radius_ratio * sprite.scale.x
	return planet_visual_radius + resolved_config.faction_ring_margin

static func draw_planet_rings(
	canvas_item: CanvasItem,
	ring_radius: float,
	faction: StringName,
	is_selected: bool,
	config: TransformerConfig
) -> void:
	if canvas_item == null or ring_radius <= 0.0:
		return
	var resolved_config := config if config != null else Planet.DEFAULT_TRANSFORMER_CONFIG
	var ring_color: Color = resolved_config.resolve_tint(&"faction", faction)
	canvas_item.draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 64, ring_color, resolved_config.faction_ring_width, true)
	if is_selected:
		canvas_item.draw_arc(
			Vector2.ZERO,
			ring_radius + resolved_config.selection_ring_margin,
			0.0,
			TAU,
			64,
			resolved_config.selection_ring_color,
			resolved_config.selection_ring_width,
			true
		)

static func setup_strength_label(label: Label, config: TransformerConfig) -> void:
	if label == null:
		return
	var resolved_config := config if config != null else Planet.DEFAULT_TRANSFORMER_CONFIG
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", resolved_config.strength_label_font_size)
	label.add_theme_color_override("font_outline_color", resolved_config.strength_label_outline_color)
	label.add_theme_constant_override("outline_size", resolved_config.strength_label_outline_size)

static func update_strength_label(
	label: Label,
	worker_count: int,
	faction: StringName,
	ring_radius: float,
	planet_scale_x: float,
	config: TransformerConfig
) -> void:
	if label == null or not is_instance_valid(label):
		return
	var resolved_config := config if config != null else Planet.DEFAULT_TRANSFORMER_CONFIG
	label.text = str(worker_count)
	label.add_theme_color_override("font_color", resolved_config.resolve_tint(&"faction", faction))
	var label_size: Vector2 = resolved_config.strength_label_size
	label.position = Vector2(-label_size.x * 0.5, ring_radius + resolved_config.strength_label_offset_y - label_size.y * 0.5)
	label.size = label_size
	label.scale = Vector2.ONE * (1.0 / maxf(planet_scale_x, 0.001))
