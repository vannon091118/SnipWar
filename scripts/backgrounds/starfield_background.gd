@tool
extends Node2D

const DEFAULT_WORLD_CONFIG: WorldConfig = preload("res://resources/config/world_default.tres")
const DEFAULT_BACKGROUND_CONFIG: BackgroundConfig = preload("res://resources/config/background_default.tres")

@export var world_config: WorldConfig = DEFAULT_WORLD_CONFIG
@export var background_config: BackgroundConfig = DEFAULT_BACKGROUND_CONFIG

var stars: Array[Dictionary] = []
var folds: Array[Dictionary] = []
var grain: Array[Dictionary] = []
var dust: Array[Dictionary] = []

func _ready() -> void:
	var world: WorldConfig = world_config if world_config != null else DEFAULT_WORLD_CONFIG
	var config: BackgroundConfig = background_config if background_config != null else DEFAULT_BACKGROUND_CONFIG
	var rng := RandomNumberGenerator.new()
	rng.seed = world.decorative_seed

	for i in config.star_count:
		stars.append({
			"position": Vector2(rng.randf(), rng.randf()),
			"radius": rng.randf_range(config.star_radius_range.x, config.star_radius_range.y),
			"alpha": rng.randf_range(config.star_alpha_range.x, config.star_alpha_range.y),
			"bright": rng.randf() < config.star_bright_chance,
			"layer": rng.randi_range(config.star_layer_range.x, config.star_layer_range.y)
		})

	for i in config.fold_count:
		folds.append({
			"position": Vector2(rng.randf(), rng.randf()),
			"angle": rng.randf_range(0.0, TAU),
			"length": rng.randf_range(config.fold_length_range.x, config.fold_length_range.y),
			"bend": rng.randf_range(config.fold_bend_range.x, config.fold_bend_range.y),
			"phase": rng.randf_range(0.0, TAU),
			"strength": rng.randf_range(config.fold_strength_range.x, config.fold_strength_range.y)
		})

	for i in config.grain_count:
		var grain_start := Vector2(rng.randf(), rng.randf())
		var grain_direction := Vector2.from_angle(rng.randf_range(0.0, TAU))
		var grain_length := rng.randf_range(config.grain_length_range.x, config.grain_length_range.y)
		grain.append({
			"from": grain_start,
			"to": grain_start + grain_direction * grain_length,
			"alpha": rng.randf_range(config.grain_alpha_range.x, config.grain_alpha_range.y)
		})

	for i in config.dust_count:
		dust.append({
			"position": Vector2(rng.randf(), rng.randf()),
			"radius": rng.randf_range(config.dust_radius_range.x, config.dust_radius_range.y),
			"alpha": rng.randf_range(config.dust_alpha_range.x, config.dust_alpha_range.y)
		})

	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var size := get_viewport_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return

	var config: BackgroundConfig = background_config if background_config != null else DEFAULT_BACKGROUND_CONFIG
	draw_rect(Rect2(Vector2.ZERO, size), config.background_color)
	_draw_nebula(size, config)
	_draw_folds(size, config)
	_draw_grain(size, config)
	_draw_dust(size, config)
	_draw_stars(size, config)

func _draw_nebula(size: Vector2, config: BackgroundConfig) -> void:
	var short_side: float = minf(size.x, size.y)
	for cloud in config.nebula_clouds:
		if cloud == null:
			continue
		var center := cloud.normalized_position * size
		var radius: float = cloud.radius_ratio * short_side
		for layer in range(config.nebula_layer_count, 0, -1):
			var layer_radius: float = radius * (config.nebula_radius_base + float(layer) * config.nebula_radius_step)
			var alpha: float = config.nebula_alpha_base + float(config.nebula_layer_count + 1 - layer) * config.nebula_alpha_step
			draw_circle(center, layer_radius, Color(cloud.color.r, cloud.color.g, cloud.color.b, alpha))

func _draw_folds(size: Vector2, config: BackgroundConfig) -> void:
	var fold_scale: float = minf(size.x, size.y)
	for fold in folds:
		var center: Vector2 = fold["position"] * size
		var direction: Vector2 = Vector2.from_angle(float(fold["angle"]))
		var perpendicular: Vector2 = direction.orthogonal()
		var length: float = fold["length"] * fold_scale
		var bend: float = fold["bend"] * fold_scale
		var phase: float = fold["phase"]
		var strength: float = fold["strength"]
		var points := PackedVector2Array()
		for point_index in config.fold_point_count:
			var t: float = float(point_index) / float(config.fold_point_count - 1)
			var along: float = (t - 0.5) * length
			var sideways: float = sin(t * PI * 2.5 + phase) * bend
			points.append(center + direction * along + perpendicular * sideways)

		var shadow_color := config.fold_shadow_color
		shadow_color.a = config.fold_shadow_alpha * strength
		var highlight_color := config.fold_highlight_color
		highlight_color.a = config.fold_highlight_alpha * strength
		draw_polyline(points, shadow_color, config.fold_shadow_width, true)
		draw_polyline(points, highlight_color, config.fold_highlight_width, true)

func _draw_grain(size: Vector2, config: BackgroundConfig) -> void:
	for mark in grain:
		var from: Vector2 = mark["from"] * size
		var to: Vector2 = mark["to"] * size
		var color := config.grain_color
		color.a = mark["alpha"]
		draw_line(from, to, color, config.grain_width, true)

func _draw_dust(size: Vector2, config: BackgroundConfig) -> void:
	for speck in dust:
		var speck_position: Vector2 = speck["position"] * size
		var color := config.dust_color
		color.a = speck["alpha"]
		draw_circle(speck_position, speck["radius"], color)

func _draw_stars(size: Vector2, config: BackgroundConfig) -> void:
	for star in stars:
		var star_position: Vector2 = star["position"] * size
		var radius: float = star["radius"]
		var color := config.star_color
		color.a = star["alpha"]

		if star["layer"] == config.star_layer_range.x:
			color.a *= config.far_star_alpha_multiplier
		elif star["layer"] == config.star_layer_range.y:
			radius *= config.near_star_radius_multiplier

		if star["bright"]:
			var diamond: PackedVector2Array = PackedVector2Array([
				star_position + Vector2(0.0, -radius * config.bright_star_vertical_ratio),
				star_position + Vector2(radius * config.bright_star_horizontal_ratio, 0.0),
				star_position + Vector2(0.0, radius * config.bright_star_vertical_ratio),
				star_position + Vector2(-radius * config.bright_star_horizontal_ratio, 0.0)
			])
			draw_colored_polygon(diamond, color)
		else:
			draw_circle(star_position, radius, color)
