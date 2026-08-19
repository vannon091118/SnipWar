@tool
extends Node2D

const DEFAULT_WORLD_CONFIG: WorldConfig = preload("res://resources/config/world_default.tres")
const DEFAULT_BACKGROUND_CONFIG: BackgroundConfig = preload("res://resources/config/background_default.tres")
const DEFAULT_SCENARIO_CATALOG: ScenarioCatalog = preload("res://resources/config/scenario_catalog.tres")

@export var world_config: WorldConfig = DEFAULT_WORLD_CONFIG
@export var background_config: BackgroundConfig = DEFAULT_BACKGROUND_CONFIG
@export var scenario_catalog: ScenarioCatalog = DEFAULT_SCENARIO_CATALOG
@export var active_scenario_id: StringName = &""

var active_scenario: ScenarioDefinition

var stars: Array[Dictionary] = []
var folds: Array[Dictionary] = []
var grain: Array[Dictionary] = []
var dust: Array[Dictionary] = []

var _batch_nodes: Array[MultiMeshInstance2D] = []
var _circle_texture: Texture2D
var _diamond_texture: Texture2D
var _shape_texture_size := 0

func _enter_tree() -> void:
	_apply_active_scenario()

func _apply_active_scenario() -> void:
	var catalog: ScenarioCatalog = scenario_catalog if scenario_catalog != null else DEFAULT_SCENARIO_CATALOG
	var scenario: ScenarioDefinition = catalog.resolve(active_scenario_id)
	if scenario == null or scenario.map_definition == null:
		return
	active_scenario = scenario
	active_scenario_id = scenario.id
	var map: MapDefinition = scenario.map_definition
	world_config = map.world_config if map.world_config != null else world_config
	background_config = scenario.background_config if scenario.background_config != null else background_config

	var field: SeededLayout = get_node_or_null("PlanetField") as SeededLayout
	if field != null:
		field.world_config = map.world_config
		field.planet_catalog = map.planet_catalog
		field.size_profiles = map.size_profiles
		var navigation: NavigationField = field.get_node_or_null("NavigationField") as NavigationField
		if navigation != null:
			navigation.world_config = map.world_config
			navigation.navigation_config = map.navigation_config
		var network: Node = field.get_node_or_null("PlanetNetwork")
		if network != null:
			network.set("transit_config", scenario.transit_config)
			network.set("ui_theme_config", scenario.ui_theme_config)
		var worker_manager: Node = field.get_node_or_null("WorkerManager")
		if worker_manager != null:
			worker_manager.set("transit_config", scenario.transit_config)

	var meteor_field: Node = get_node_or_null("MeteorField")
	if meteor_field != null:
		meteor_field.set("world_config", map.world_config)
		meteor_field.set("meteor_config", scenario.meteor_config)

func get_active_scenario() -> ScenarioDefinition:
	return active_scenario

func _ready() -> void:
	_generate_elements()
	_rebuild_render_batches()
	var viewport := get_viewport()
	if viewport != null:
		var resize_callable := Callable(self, "_on_viewport_size_changed")
		if not viewport.size_changed.is_connected(resize_callable):
			viewport.size_changed.connect(resize_callable)
	queue_redraw()

func _generate_elements() -> void:
	stars.clear()
	folds.clear()
	grain.clear()
	dust.clear()

	var world: WorldConfig = world_config if world_config != null else DEFAULT_WORLD_CONFIG
	var config: BackgroundConfig = background_config if background_config != null else DEFAULT_BACKGROUND_CONFIG
	var rng := RandomNumberGenerator.new()
	rng.seed = world.decorative_seed

	for _index in config.star_count:
		stars.append({
			"position": Vector2(rng.randf(), rng.randf()),
			"radius": rng.randf_range(config.star_radius_range.x, config.star_radius_range.y),
			"alpha": rng.randf_range(config.star_alpha_range.x, config.star_alpha_range.y),
			"bright": rng.randf() < config.star_bright_chance,
			"layer": rng.randi_range(config.star_layer_range.x, config.star_layer_range.y)
		})

	for _index in config.fold_count:
		folds.append({
			"position": Vector2(rng.randf(), rng.randf()),
			"angle": rng.randf_range(0.0, TAU),
			"length": rng.randf_range(config.fold_length_range.x, config.fold_length_range.y),
			"bend": rng.randf_range(config.fold_bend_range.x, config.fold_bend_range.y),
			"phase": rng.randf_range(0.0, TAU),
			"strength": rng.randf_range(config.fold_strength_range.x, config.fold_strength_range.y)
		})

	for _index in config.grain_count:
		var grain_start := Vector2(rng.randf(), rng.randf())
		var grain_direction := Vector2.from_angle(rng.randf_range(0.0, TAU))
		var grain_length := rng.randf_range(config.grain_length_range.x, config.grain_length_range.y)
		grain.append({
			"from": grain_start,
			"to": grain_start + grain_direction * grain_length,
			"alpha": rng.randf_range(config.grain_alpha_range.x, config.grain_alpha_range.y)
		})

	for _index in config.dust_count:
		dust.append({
			"position": Vector2(rng.randf(), rng.randf()),
			"radius": rng.randf_range(config.dust_radius_range.x, config.dust_radius_range.y),
			"alpha": rng.randf_range(config.dust_alpha_range.x, config.dust_alpha_range.y)
		})

func _on_viewport_size_changed() -> void:
	_rebuild_render_batches()
	queue_redraw()

func _rebuild_render_batches() -> void:
	_clear_render_batches()
	var size := get_viewport_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return

	var config: BackgroundConfig = background_config if background_config != null else DEFAULT_BACKGROUND_CONFIG
	if _shape_texture_size != config.batch_texture_size or _circle_texture == null or _diamond_texture == null:
		_shape_texture_size = config.batch_texture_size
		_circle_texture = _create_shape_texture(&"circle", _shape_texture_size)
		_diamond_texture = _create_shape_texture(&"diamond", _shape_texture_size)

	var texture_radius: float = maxf(float(_shape_texture_size) * 0.5 - 1.0, 1.0)
	var star_transforms: Array[Transform2D] = []
	var star_colors: Array[Color] = []
	var bright_transforms: Array[Transform2D] = []
	var bright_colors: Array[Color] = []
	for star in stars:
		var star_position: Vector2 = star["position"] * size
		var radius: float = float(star["radius"])
		var color := config.star_color
		color.a = float(star["alpha"])
		if int(star["layer"]) == config.star_layer_range.x:
			color.a *= config.far_star_alpha_multiplier
		elif int(star["layer"]) == config.star_layer_range.y:
			radius *= config.near_star_radius_multiplier

		if bool(star["bright"]):
			bright_transforms.append(_transform_for(
				star_position,
				Vector2(
					radius * config.bright_star_horizontal_ratio / texture_radius,
					radius * config.bright_star_vertical_ratio / texture_radius
				)
			))
			bright_colors.append(color)
		else:
			star_transforms.append(_transform_for(star_position, Vector2.ONE * radius / texture_radius))
			star_colors.append(color)

	var dust_transforms: Array[Transform2D] = []
	var dust_colors: Array[Color] = []
	for speck in dust:
		var dust_color := config.dust_color
		dust_color.a = float(speck["alpha"])
		dust_transforms.append(_transform_for(
			speck["position"] * size,
			Vector2.ONE * float(speck["radius"]) / texture_radius
		))
		dust_colors.append(dust_color)

	_add_batch("DustBatch", _circle_texture, dust_transforms, dust_colors)
	_add_batch("StarBatch", _circle_texture, star_transforms, star_colors)
	_add_batch("BrightStarBatch", _diamond_texture, bright_transforms, bright_colors)

func _clear_render_batches() -> void:
	for batch in _batch_nodes:
		if is_instance_valid(batch):
			batch.free()
	_batch_nodes.clear()

func _add_batch(name: StringName, texture: Texture2D, transforms: Array[Transform2D], colors: Array[Color]) -> void:
	if transforms.is_empty() or texture == null:
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(2.0, 2.0)
	multimesh.mesh = quad_mesh
	multimesh.instance_count = transforms.size()
	for index in transforms.size():
		multimesh.set_instance_transform_2d(index, transforms[index])
		multimesh.set_instance_color(index, colors[index])

	var batch := MultiMeshInstance2D.new()
	batch.name = String(name)
	batch.multimesh = multimesh
	batch.texture = texture
	add_child(batch)
	_batch_nodes.append(batch)

func _transform_for(position: Vector2, scale: Vector2) -> Transform2D:
	var transform := Transform2D()
	transform.origin = position
	transform.x *= scale.x
	transform.y *= scale.y
	return transform

func _create_shape_texture(shape: StringName, texture_size: int) -> Texture2D:
	var image := Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	var center := (float(texture_size) - 1.0) * 0.5
	var radius: float = maxf(float(texture_size) * 0.5 - 1.0, 1.0)
	for y in texture_size:
		for x in texture_size:
			var normalized: float
			if shape == &"diamond":
				normalized = (absf(float(x) - center) + absf(float(y) - center)) / radius
			else:
				normalized = Vector2(float(x) - center, float(y) - center).length() / radius
			var alpha: float = clampf((1.0 - normalized) / 0.12, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)

func _draw() -> void:
	var size := get_viewport_rect().size
	if size.x <= 0.0 or size.y <= 0.0:
		return

	var config: BackgroundConfig = background_config if background_config != null else DEFAULT_BACKGROUND_CONFIG
	draw_rect(Rect2(Vector2.ZERO, size), config.background_color)
	_draw_nebula(size, config)
	_draw_folds(size, config)
	_draw_grain(size, config)

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
	var shadow_segments := PackedVector2Array()
	var highlight_segments := PackedVector2Array()
	var strength_sum: float = 0.0
	for fold in folds:
		var center: Vector2 = fold["position"] * size
		var direction: Vector2 = Vector2.from_angle(float(fold["angle"]))
		var perpendicular: Vector2 = direction.orthogonal()
		var length: float = float(fold["length"]) * fold_scale
		var bend: float = float(fold["bend"]) * fold_scale
		var phase: float = float(fold["phase"])
		strength_sum += float(fold["strength"])
		var points := PackedVector2Array()
		for point_index in config.fold_point_count:
			var t: float = float(point_index) / float(config.fold_point_count - 1)
			var along: float = (t - 0.5) * length
			var sideways: float = sin(t * PI * 2.5 + phase) * bend
			points.append(center + direction * along + perpendicular * sideways)
			if point_index > 0:
				shadow_segments.append(points[point_index - 1])
				shadow_segments.append(points[point_index])
				highlight_segments.append(points[point_index - 1])
				highlight_segments.append(points[point_index])

	if folds.is_empty():
		return
	var average_strength: float = strength_sum / float(folds.size())
	var shadow_color := config.fold_shadow_color
	shadow_color.a = config.fold_shadow_alpha * average_strength
	var highlight_color := config.fold_highlight_color
	highlight_color.a = config.fold_highlight_alpha * average_strength
	if shadow_segments.size() >= 2:
		draw_multiline(shadow_segments, shadow_color, config.fold_shadow_width, true)
	if highlight_segments.size() >= 2:
		draw_multiline(highlight_segments, highlight_color, config.fold_highlight_width, true)

func _draw_grain(size: Vector2, config: BackgroundConfig) -> void:
	if grain.is_empty():
		return
	var segments := PackedVector2Array()
	var alpha_sum: float = 0.0
	for mark in grain:
		segments.append(mark["from"] * size)
		segments.append(mark["to"] * size)
		alpha_sum += float(mark["alpha"])
	var color := config.grain_color
	color.a = alpha_sum / float(grain.size())
	draw_multiline(segments, color, config.grain_width, true)

func get_render_batch_stats() -> Dictionary:
	var batched_elements: int = 0
	for batch in _batch_nodes:
		if is_instance_valid(batch) and batch.multimesh != null:
			batched_elements += batch.multimesh.instance_count
	var config: BackgroundConfig = background_config if background_config != null else DEFAULT_BACKGROUND_CONFIG
	var estimated_draw_calls: int = 1
	estimated_draw_calls += config.nebula_clouds.size() * config.nebula_layer_count
	if not folds.is_empty():
		estimated_draw_calls += 2
	if not grain.is_empty():
		estimated_draw_calls += 1
	estimated_draw_calls += _batch_nodes.size()
	return {
		"batch_count": _batch_nodes.size(),
		"batched_elements": batched_elements,
		"source_elements": stars.size() + folds.size() + grain.size() + dust.size(),
		"estimated_draw_calls": estimated_draw_calls
	}
