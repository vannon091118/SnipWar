@tool
extends Node2D

const DEFAULT_WORLD_CONFIG: WorldConfig = preload("res://resources/config/world_default.tres")
const DEFAULT_BACKGROUND_CONFIG: BackgroundConfig = preload("res://resources/config/background_default.tres")
const DEFAULT_SCENARIO_CATALOG: ScenarioCatalog = preload("res://resources/config/scenario_catalog.tres")
const DEFAULT_UI_THEME: UIThemeConfig = preload("res://resources/config/ui_theme_default.tres")

@export var world_config: WorldConfig = DEFAULT_WORLD_CONFIG
@export var background_config: BackgroundConfig = DEFAULT_BACKGROUND_CONFIG
@export var scenario_catalog: ScenarioCatalog = DEFAULT_SCENARIO_CATALOG
@export var active_scenario_id: StringName = &""

var active_scenario: ScenarioDefinition
# The catalog the world actually runs on — generated from the world's
# building-block pool under the finalized layout seed. GameState, the
# PlanetField and the resource deal must all share this single catalog.
var active_catalog: PlanetCatalog
# Finalized per-run layout seed (authored seed for fixed scenarios, random for
# randomized ones). Finalized in _enter_tree so the generated catalog and the
# planet layout share one deterministic seed before either is built.
var active_layout_seed: int = 0

var stars: Array[Dictionary] = []
var folds: Array[Dictionary] = []
var grain: Array[Dictionary] = []
var dust: Array[Dictionary] = []

var _batch_nodes: Array[MultiMeshInstance2D] = []
var _circle_texture: Texture2D
var _diamond_texture: Texture2D
var _shape_texture_size := 0
var _main_menu_backdrop: Sprite2D
## Visible region for infinite world (follows FoV). Only updated on chunk
## boundary change, not per frame, to avoid star regeneration overhead.
var _visible_region := Rect2(Vector2.ZERO, Vector2(960, 540))

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
	var runtime_world: WorldConfig = WorldGenerator.resolve_runtime_world(map.world_config, null)
	if runtime_world != null:
		runtime_world.route_mode = scenario.resolved_route_mode()
	world_config = map.world_config if map.world_config != null else world_config
	background_config = scenario.background_config if scenario.background_config != null else background_config
	_finalize_layout_seed(scenario, runtime_world)
	var live_world: WorldConfig = runtime_world if runtime_world != null else map.world_config
	active_catalog = WorldGenerator.generate_catalog(
		live_world,
		active_layout_seed,
		WorldGenerator.target_planet_count(live_world, null)
	)

	_configure_game_state(map)
	_configure_planet_field(map, scenario, runtime_world)
	_configure_meteor_field(map, scenario, runtime_world)

# Drops the runtime duplicate onto the planet field/navigation so that the
# authored .tres is never written into. The duplicate carries the growth
# contract (sqrt-scaled design_size, scaled target_planet_count, auto-columns).
func _configure_planet_field(map: MapDefinition, scenario: ScenarioDefinition, runtime_world: WorldConfig) -> void:
	var field: SeededLayout = get_node_or_null("PlanetField") as SeededLayout
	if field == null or map == null or scenario == null:
		return
	field.position = Vector2.ZERO
	field.world_config = runtime_world if runtime_world != null else map.world_config
	field.planet_catalog = active_catalog
	field.size_profiles = map.size_profiles
	var navigation: NavigationField = field.get_node_or_null("NavigationField") as NavigationField
	if navigation != null:
		navigation.world_config = runtime_world if runtime_world != null else map.world_config
		navigation.navigation_config = map.navigation_config
	var network: Node = field.get_node_or_null("PlanetNetwork")
	if network != null:
		network.set("transit_config", scenario.transit_config)
		network.set("ui_theme_config", scenario.ui_theme_config)
	var worker_manager: Node = field.get_node_or_null("WorkerManager")
	if worker_manager != null:
		worker_manager.set("transit_config", scenario.transit_config)

func _configure_game_state(map: MapDefinition) -> void:
	var state: Node = get_node_or_null("/root/GameState")
	if state != null and map != null and active_catalog != null:
		state.reset_from_catalog(active_catalog)

func _configure_meteor_field(map: MapDefinition, scenario: ScenarioDefinition, runtime_world: WorldConfig = null) -> void:
	var meteor_field: Node2D = get_node_or_null("MeteorField") as Node2D
	if meteor_field != null and map != null and scenario != null:
		meteor_field.position = Vector2.ZERO
		meteor_field.set("world_config", runtime_world if runtime_world != null else map.world_config)
		meteor_field.set("meteor_config", scenario.meteor_config)

func get_active_scenario() -> ScenarioDefinition:
	return active_scenario

func _finalize_layout_seed(scenario: ScenarioDefinition, runtime_world: WorldConfig) -> void:
	var base_seed: int = runtime_world.layout_seed if runtime_world != null else 0
	if scenario != null and not scenario.randomize_layout_seed:
		active_layout_seed = base_seed
	else:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		active_layout_seed = rng.randi()
	if runtime_world != null:
		runtime_world.layout_seed = active_layout_seed

func _disable_collision_debug_overlay() -> void:
	# The editor's "Visible Collision Shapes" toggle draws cyan circles around every
	# ClickArea. Force it off in the running game so faction rings stay readable.
	var tree := get_tree()
	if tree != null:
		tree.set("debug_collisions_hint", false)

func _ready() -> void:
	_disable_collision_debug_overlay()
	_generate_elements()
	_ensure_main_menu_backdrop()
	_rebuild_render_batches()
	var viewport := get_viewport()
	if viewport != null:
		var resize_callable := Callable(self, "_on_viewport_size_changed")
		if not viewport.size_changed.is_connected(resize_callable):
			viewport.size_changed.connect(resize_callable)
	queue_redraw()

func _ensure_main_menu_backdrop() -> void:
	if _main_menu_backdrop != null and is_instance_valid(_main_menu_backdrop):
		_update_main_menu_backdrop()
		return
	var texture: Texture2D = DEFAULT_UI_THEME.main_menu_background_texture
	if texture == null:
		return
	_main_menu_backdrop = Sprite2D.new()
	_main_menu_backdrop.name = "MainMenuBackdrop"
	_main_menu_backdrop.texture = texture
	_main_menu_backdrop.centered = false
	# Keep the backdrop above the root's procedural draw and below the map
	# children; a negative relative z would place it behind the Background node.
	_main_menu_backdrop.z_index = 0
	_main_menu_backdrop.modulate = Color(1.0, 1.0, 1.0, 0.35)
	add_child(_main_menu_backdrop)
	_update_main_menu_backdrop()

func _update_main_menu_backdrop() -> void:
	if _main_menu_backdrop == null or not is_instance_valid(_main_menu_backdrop) or _main_menu_backdrop.texture == null:
		return
	var size: Vector2 = _world_size()
	var texture_size: Vector2 = _main_menu_backdrop.texture.get_size()
	if size.x <= 0.0 or size.y <= 0.0 or texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	_main_menu_backdrop.scale = Vector2(size.x / texture_size.x, size.y / texture_size.y)

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
	_update_main_menu_backdrop()
	_rebuild_render_batches()
	queue_redraw()

func _world_size() -> Vector2:
	var world: WorldConfig = world_config if world_config != null else DEFAULT_WORLD_CONFIG
	if world.is_infinite_world():
		return _visible_region.size if _visible_region.size.x > 0.0 else world.design_size
	if world.design_size.x > 0.0 and world.design_size.y > 0.0:
		return world.design_size
	return get_viewport_rect().size

func _rebuild_render_batches() -> void:
	_clear_render_batches()
	var size := _world_size()
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

func _add_batch(batch_name: StringName, texture: Texture2D, transforms: Array[Transform2D], colors: Array[Color]) -> void:
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
	batch.name = String(batch_name)
	batch.multimesh = multimesh
	batch.texture = texture
	add_child(batch)
	_batch_nodes.append(batch)

func _transform_for(point_position: Vector2, point_scale: Vector2) -> Transform2D:
	var result_transform := Transform2D()
	result_transform.origin = point_position
	result_transform.x *= point_scale.x
	result_transform.y *= point_scale.y
	return result_transform

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
	var size := _world_size()
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
	if folds.is_empty():
		return
	var fold_scale: float = minf(size.x, size.y)
	var bucket_count: int = maxi(1, config.fold_alpha_bucket_count)
	var shadow_segments: Array = []
	var highlight_segments: Array = []
	for _bucket in bucket_count:
		shadow_segments.append(PackedVector2Array())
		highlight_segments.append(PackedVector2Array())

	for fold in folds:
		var center: Vector2 = fold["position"] * size
		var direction: Vector2 = Vector2.from_angle(float(fold["angle"]))
		var perpendicular: Vector2 = direction.orthogonal()
		var length: float = float(fold["length"]) * fold_scale
		var bend: float = float(fold["bend"]) * fold_scale
		var phase: float = float(fold["phase"])
		var strength: float = float(fold["strength"])
		var bucket_index: int = _alpha_bucket_index(strength, config.fold_strength_range, bucket_count)
		var points := PackedVector2Array()
		for point_index in config.fold_point_count:
			var t: float = float(point_index) / float(config.fold_point_count - 1)
			var along: float = (t - 0.5) * length
			var sideways: float = sin(t * PI * 2.5 + phase) * bend
			points.append(center + direction * along + perpendicular * sideways)
			if point_index > 0:
				var shadow_points: PackedVector2Array = shadow_segments[bucket_index]
				shadow_points.append(points[point_index - 1])
				shadow_points.append(points[point_index])
				shadow_segments[bucket_index] = shadow_points
				var highlight_points: PackedVector2Array = highlight_segments[bucket_index]
				highlight_points.append(points[point_index - 1])
				highlight_points.append(points[point_index])
				highlight_segments[bucket_index] = highlight_points

	for bucket_index in bucket_count:
		var bucket_strength: float = _alpha_bucket_value(bucket_index, bucket_count, config.fold_strength_range)
		var shadow_lines: PackedVector2Array = shadow_segments[bucket_index]
		if shadow_lines.size() >= 2:
			var shadow_color := config.fold_shadow_color
			shadow_color.a = config.fold_shadow_alpha * bucket_strength
			draw_multiline(shadow_lines, shadow_color, config.fold_shadow_width, true)
		var highlight_lines: PackedVector2Array = highlight_segments[bucket_index]
		if highlight_lines.size() >= 2:
			var highlight_color := config.fold_highlight_color
			highlight_color.a = config.fold_highlight_alpha * bucket_strength
			draw_multiline(highlight_lines, highlight_color, config.fold_highlight_width, true)

func _draw_grain(size: Vector2, config: BackgroundConfig) -> void:
	if grain.is_empty():
		return
	var bucket_count: int = maxi(1, config.grain_alpha_bucket_count)
	var segments: Array = []
	for _bucket in bucket_count:
		segments.append(PackedVector2Array())
	for mark in grain:
		var bucket_index: int = _alpha_bucket_index(float(mark["alpha"]), config.grain_alpha_range, bucket_count)
		var lines: PackedVector2Array = segments[bucket_index]
		lines.append(mark["from"] * size)
		lines.append(mark["to"] * size)
		segments[bucket_index] = lines

	for bucket_index in bucket_count:
		var grain_lines: PackedVector2Array = segments[bucket_index]
		if grain_lines.size() < 2:
			continue
		var color := config.grain_color
		color.a = _alpha_bucket_value(bucket_index, bucket_count, config.grain_alpha_range)
		draw_multiline(grain_lines, color, config.grain_width, true)

func _alpha_bucket_index(value: float, value_range: Vector2, bucket_count: int) -> int:
	if bucket_count <= 1 or is_equal_approx(value_range.x, value_range.y):
		return 0
	var normalized: float = clampf(inverse_lerp(value_range.x, value_range.y, value), 0.0, 1.0)
	return clampi(int(floor(normalized * float(bucket_count))), 0, bucket_count - 1)

func _alpha_bucket_value(bucket_index: int, bucket_count: int, value_range: Vector2) -> float:
	if bucket_count <= 1:
		return (value_range.x + value_range.y) * 0.5
	var normalized: float = (float(bucket_index) + 0.5) / float(bucket_count)
	return lerpf(value_range.x, value_range.y, normalized)

func _non_empty_fold_alpha_buckets(config: BackgroundConfig) -> int:
	var buckets: Dictionary = {}
	var bucket_count: int = maxi(1, config.fold_alpha_bucket_count)
	for fold in folds:
		buckets[_alpha_bucket_index(float(fold["strength"]), config.fold_strength_range, bucket_count)] = true
	return buckets.size()

func _non_empty_grain_alpha_buckets(config: BackgroundConfig) -> int:
	var buckets: Dictionary = {}
	var bucket_count: int = maxi(1, config.grain_alpha_bucket_count)
	for mark in grain:
		buckets[_alpha_bucket_index(float(mark["alpha"]), config.grain_alpha_range, bucket_count)] = true
	return buckets.size()

func get_render_batch_stats() -> Dictionary:
	var batched_elements: int = 0
	for batch in _batch_nodes:
		if is_instance_valid(batch) and batch.multimesh != null:
			batched_elements += batch.multimesh.instance_count
	var config: BackgroundConfig = background_config if background_config != null else DEFAULT_BACKGROUND_CONFIG
	var fold_draw_calls: int = _non_empty_fold_alpha_buckets(config)
	var grain_draw_calls: int = _non_empty_grain_alpha_buckets(config)
	var estimated_draw_calls: int = 1
	estimated_draw_calls += config.nebula_clouds.size() * config.nebula_layer_count
	estimated_draw_calls += fold_draw_calls + grain_draw_calls
	estimated_draw_calls += _batch_nodes.size()
	return {
		"batch_count": _batch_nodes.size(),
		"batched_elements": batched_elements,
		"source_elements": stars.size() + folds.size() + grain.size() + dust.size(),
		"fold_alpha_draw_calls": fold_draw_calls,
		"grain_alpha_draw_calls": grain_draw_calls,
		"estimated_draw_calls": estimated_draw_calls
	}
