@tool
class_name SeededLayout
extends Node2D

const PLANET_SCENE: PackedScene = preload("res://scenes/objects/planets/planet.tscn")
const DEFAULT_WORLD_CONFIG: WorldConfig = preload("res://resources/config/world_default.tres")
const DEFAULT_PLANET_CATALOG: PlanetCatalog = preload("res://resources/config/planet_catalog.tres")

@export var world_config: WorldConfig = DEFAULT_WORLD_CONFIG:
	set(value):
		world_config = value if value != null else DEFAULT_WORLD_CONFIG
		_queue_layout()

@export var planet_catalog: PlanetCatalog = DEFAULT_PLANET_CATALOG
@export var size_profiles: Array[PlanetSizeProfile] = []:
	set(value):
		size_profiles = value
		_queue_layout()

signal layout_completed(planets: Array[Planet])

var _catalog_generated := false

func _enter_tree() -> void:
	_generate_catalog_planets()

func _ready() -> void:
	regenerate()

func set_layout_seed(value: int) -> void:
	world_config.layout_seed = value
	_queue_layout()

func regenerate() -> void:
	var layout_items: Array[Planet] = []
	for child in get_children():
		if child is Planet:
			layout_items.append(child)

	if layout_items.is_empty():
		return

	var config: WorldConfig = world_config if world_config != null else DEFAULT_WORLD_CONFIG
	var rng := RandomNumberGenerator.new()
	rng.seed = config.layout_seed
	_assign_size_classes(layout_items, rng, config)

	var column_count := maxi(1, config.columns)
	var rows: int = ceili(float(layout_items.size()) / float(column_count))
	var cell_size := Vector2(
		config.design_size.x / float(column_count),
		config.design_size.y / float(rows)
	)
	var assigned_slots: Dictionary = {}
	var slots: Array[int] = []
	for slot in layout_items.size():
		slots.append(slot)
	_shuffle(slots, rng)
	for index in layout_items.size():
		assigned_slots[layout_items[index]] = slots[index]

	for item in layout_items:
		var slot: int = assigned_slots[item]
		var column: int = slot % column_count
		var row: int = floori(float(slot) / float(column_count))
		var cell_center := Vector2(
			(float(column) + 0.5) * cell_size.x,
			(float(row) + 0.5) * cell_size.y
		)
		var profile: PlanetSizeProfile = item.get_size_profile()
		var offset := Vector2(
			rng.randf_range(-cell_size.x * config.jitter * profile.jitter_factor, cell_size.x * config.jitter * profile.jitter_factor),
			rng.randf_range(-cell_size.y * config.jitter * profile.jitter_factor, cell_size.y * config.jitter * profile.jitter_factor)
		)
		var item_position := cell_center + offset
		item_position.x = clampf(item_position.x, config.padding, config.design_size.x - config.padding)
		item_position.y = clampf(item_position.y, config.padding, config.design_size.y - config.padding)
		item.set_meta("layout_slot", slot)
		item.position = item_position
		item.scale = Vector2.ONE * _scale_for(item, rng)

	layout_completed.emit(layout_items)

	var navigation: NavigationField = get_node_or_null("NavigationField") as NavigationField
	if navigation != null:
		navigation.world_config = config
		navigation.request_rebuild()
	if not Engine.is_editor_hint():
		var network: Node = get_node_or_null("PlanetNetwork")
		if network != null and network.has_method("invalidate_neighbor_cache"):
			network.call("invalidate_neighbor_cache")

func _generate_catalog_planets() -> void:
	if _catalog_generated:
		return
	for child in get_children():
		if child is Planet:
			_catalog_generated = true
			return

	var catalog: PlanetCatalog = planet_catalog if planet_catalog != null else DEFAULT_PLANET_CATALOG
	var insertion_index := _planet_insertion_index()
	for definition in catalog.planets:
		if definition == null:
			continue
		var planet: Planet = PLANET_SCENE.instantiate()
		planet.name = definition.display_name if not definition.display_name.is_empty() else String(definition.planet_id)
		planet.apply_definition(definition)
		add_child(planet)
		move_child(planet, insertion_index)
		insertion_index += 1
	_catalog_generated = true

func _planet_insertion_index() -> int:
	var network := get_node_or_null("PlanetNetwork")
	if network == null:
		return 0
	return get_children().find(network)

func _assign_size_classes(items: Array[Planet], rng: RandomNumberGenerator, config: WorldConfig) -> void:
	var profiles_by_id: Dictionary = {}
	for profile in size_profiles:
		if profile != null:
			profiles_by_id[profile.id] = profile

	var default_profile: PlanetSizeProfile = profiles_by_id.get(config.default_profile_id) as PlanetSizeProfile
	if default_profile == null:
		default_profile = Planet.DEFAULT_SIZE_PROFILE
	var large_profile: PlanetSizeProfile = profiles_by_id.get(config.large_profile_id) as PlanetSizeProfile
	if large_profile == null:
		large_profile = default_profile
	var extra_large_profile: PlanetSizeProfile = profiles_by_id.get(config.extra_large_profile_id) as PlanetSizeProfile
	if extra_large_profile == null:
		extra_large_profile = default_profile

	var assigned_profiles: Array[PlanetSizeProfile] = []
	for _index in mini(config.extra_large_count, items.size()):
		assigned_profiles.append(extra_large_profile)
	for _index in mini(config.large_count, maxi(0, items.size() - assigned_profiles.size())):
		assigned_profiles.append(large_profile)
	while assigned_profiles.size() < items.size():
		assigned_profiles.append(default_profile)

	var shuffled_items: Array[Planet] = items.duplicate()
	_shuffle(shuffled_items, rng)
	for index in shuffled_items.size():
		shuffled_items[index].set_size_profile(assigned_profiles[index])
		shuffled_items[index].set_detail_seed(rng.randi())
	_seed_initial_workers(shuffled_items)

func _seed_initial_workers(items: Array[Planet]) -> void:
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	var state: Node = get_tree().root.get_node_or_null("GameState")
	if state == null:
		return
	for item in items:
		state.seed_starting_workers(item.planet_id, item.get_size_profile())
		item.set_initial_workers(state.starting_workers_of(item.planet_id))

func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = value

func _scale_for(item: Planet, rng: RandomNumberGenerator) -> float:
	var profile: PlanetSizeProfile = item.get_size_profile()
	return rng.randf_range(profile.scale_range.x, profile.scale_range.y)

func _queue_layout() -> void:
	if is_inside_tree():
		call_deferred("regenerate")
