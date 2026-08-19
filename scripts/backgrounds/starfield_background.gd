@tool
extends Node2D

const STAR_COUNT := 120
const FOLD_COUNT := 20
const GRAIN_COUNT := 220
const DUST_COUNT := 260
const DEFAULT_WORLD_CONFIG: WorldConfig = preload("res://resources/config/world_default.tres")

@export var world_config: WorldConfig = DEFAULT_WORLD_CONFIG

var stars: Array[Dictionary] = []
var folds: Array[Dictionary] = []
var grain: Array[Dictionary] = []
var dust: Array[Dictionary] = []

func _ready() -> void:
	var config: WorldConfig = world_config if world_config != null else DEFAULT_WORLD_CONFIG
	var rng := RandomNumberGenerator.new()
	rng.seed = config.decorative_seed

	for i in STAR_COUNT:
		stars.append({
			"position": Vector2(rng.randf(), rng.randf()),
			"radius": rng.randf_range(0.4, 1.5),
			"alpha": rng.randf_range(0.22, 0.78),
			"bright": rng.randf() < 0.09,
			"layer": rng.randi_range(0, 2)
		})

	for i in FOLD_COUNT:
		folds.append({
			"position": Vector2(rng.randf(), rng.randf()),
			"angle": rng.randf_range(0.0, TAU),
			"length": rng.randf_range(0.35, 0.95),
			"bend": rng.randf_range(0.015, 0.08),
			"phase": rng.randf_range(0.0, TAU),
			"strength": rng.randf_range(0.35, 0.9)
		})

	for i in GRAIN_COUNT:
		var grain_start := Vector2(rng.randf(), rng.randf())
		var grain_direction := Vector2.from_angle(rng.randf_range(0.0, TAU))
		var grain_length := rng.randf_range(0.002, 0.012)
		grain.append({
			"from": grain_start,
			"to": grain_start + grain_direction * grain_length,
			"alpha": rng.randf_range(0.012, 0.045)
		})

	for i in DUST_COUNT:
		dust.append({
			"position": Vector2(rng.randf(), rng.randf()),
			"radius": rng.randf_range(0.25, 0.7),
			"alpha": rng.randf_range(0.025, 0.14)
		})

	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	var size := get_viewport_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return

	draw_rect(Rect2(Vector2.ZERO, size), Color("070b16"))
	_draw_nebula(size)
	_draw_folds(size)
	_draw_grain(size)
	_draw_dust(size)
	_draw_stars(size)

func _draw_nebula(size: Vector2) -> void:
	var short_side: float = minf(size.x, size.y)
	var clouds: Array[Dictionary] = [
		{ "position": Vector2(0.18, 0.27), "radius": 0.43, "color": Color(0.16, 0.15, 0.38) },
		{ "position": Vector2(0.78, 0.70), "radius": 0.50, "color": Color(0.08, 0.24, 0.34) },
		{ "position": Vector2(0.54, 0.12), "radius": 0.28, "color": Color(0.26, 0.12, 0.30) }
	]

	for cloud in clouds:
		var center: Vector2 = cloud["position"] * size
		var radius: float = cloud["radius"] * short_side
		var base: Color = cloud["color"]
		for layer in range(5, 0, -1):
			var layer_radius: float = radius * (0.38 + float(layer) * 0.14)
			var alpha: float = 0.018 + (6.0 - float(layer)) * 0.006
			draw_circle(center, layer_radius, Color(base.r, base.g, base.b, alpha))

func _draw_folds(size: Vector2) -> void:
	var fold_scale: float = minf(size.x, size.y)

	for fold in folds:
		var center: Vector2 = fold["position"] * size
		var direction: Vector2 = Vector2.from_angle(float(fold["angle"]))
		var perpendicular: Vector2 = direction.orthogonal()
		var length: float = fold["length"] * fold_scale
		var bend: float = fold["bend"] * fold_scale
		var phase: float = fold["phase"]
		var strength: float = fold["strength"]
		var points: PackedVector2Array = PackedVector2Array()

		for point_index in 12:
			var t: float = float(point_index) / 11.0
			var along: float = (t - 0.5) * length
			var sideways: float = sin(t * PI * 2.5 + phase) * bend
			points.append(center + direction * along + perpendicular * sideways)

		draw_polyline(points, Color(0.015, 0.02, 0.07, 0.10 * strength), 5.0, true)
		draw_polyline(points, Color(0.52, 0.60, 0.82, 0.08 * strength), 1.2, true)

func _draw_grain(size: Vector2) -> void:
	for mark in grain:
		var from: Vector2 = mark["from"] * size
		var to: Vector2 = mark["to"] * size
		var alpha: float = mark["alpha"]
		draw_line(from, to, Color(0.72, 0.78, 0.94, alpha), 1.0, true)

func _draw_dust(size: Vector2) -> void:
	for speck in dust:
		var speck_position: Vector2 = speck["position"] * size
		var radius: float = speck["radius"]
		var alpha: float = speck["alpha"]
		draw_circle(speck_position, radius, Color(0.46, 0.55, 0.72, alpha))

func _draw_stars(size: Vector2) -> void:
	for star in stars:
		var star_position: Vector2 = star["position"] * size
		var radius: float = star["radius"]
		var alpha: float = star["alpha"]
		var color: Color = Color(0.76, 0.86, 1.0, alpha)

		if star["layer"] == 0:
			color.a *= 0.55
		elif star["layer"] == 2:
			radius *= 1.2

		if star["bright"]:
			var diamond: PackedVector2Array = PackedVector2Array([
				star_position + Vector2(0.0, -radius * 2.5),
				star_position + Vector2(radius * 0.8, 0.0),
				star_position + Vector2(0.0, radius * 2.5),
				star_position + Vector2(-radius * 0.8, 0.0)
			])
			draw_colored_polygon(diamond, color)
		else:
			draw_circle(star_position, radius, color)
