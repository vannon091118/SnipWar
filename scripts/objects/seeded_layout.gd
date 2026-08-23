@tool
class_name SeededLayout
extends Node2D

const PLANET_SCENE: PackedScene = preload("res://scenes/objects/planets/planet.tscn")
const PLANET_ECONOMY_MANAGER_SCRIPT: Script = preload("res://scripts/objects/planets/economy_manager.gd")
const CPU_DISPATCH_AI_SCRIPT: Script = preload("res://scripts/objects/planets/cpu_dispatch_ai.gd")
const SHIP_MANAGER_SCRIPT: Script = preload("res://scripts/objects/ships/ship_manager.gd")
const CONFLICT_MANAGER_SCRIPT: Script = preload("res://scripts/objects/conflict_manager.gd")
const DEFAULT_TRANSIT_CONFIG: TransitConfig = preload("res://resources/config/transit_default.tres")
const DEFAULT_WORLD_CONFIG: WorldConfig = preload("res://resources/config/world_default.tres")
const DEFAULT_PLANET_CATALOG: PlanetCatalog = preload("res://resources/config/planet_catalog.tres")
const DEFAULT_ECONOMY_CONFIG: EconomyConfig = preload("res://resources/config/economy_default.tres")
const DEFAULT_CPU_DISPATCH_CONFIG: CpuDispatchConfig = preload("res://resources/config/cpu_dispatch_default.tres")
const DEFAULT_SHIP_CONFIG: ShipConfig = preload("res://resources/config/ship_default.tres")
const DEFAULT_TECHNOLOGY_CATALOG: TechnologyCatalog = preload("res://resources/config/technology_catalog_default.tres")
const CHUNK_COORDINATOR_SCRIPT: Script = preload("res://scripts/objects/chunk_coordinator.gd")

@export var world_config: WorldConfig = DEFAULT_WORLD_CONFIG:
	set(value):
		world_config = value if value != null else DEFAULT_WORLD_CONFIG
		_queue_layout()

@export var planet_catalog: PlanetCatalog = DEFAULT_PLANET_CATALOG
@export var size_profiles: Array[PlanetSizeProfile] = []:
	set(value):
		size_profiles = value
		_queue_layout()
@export var economy_config: EconomyConfig = DEFAULT_ECONOMY_CONFIG
@export var cpu_dispatch_config: CpuDispatchConfig = DEFAULT_CPU_DISPATCH_CONFIG
@export var ship_config: ShipConfig = DEFAULT_SHIP_CONFIG
@export var technology_catalog: TechnologyCatalog = DEFAULT_TECHNOLOGY_CATALOG

signal layout_completed(planets: Array[Planet])

var _catalog_generated := false
var _runtime_modules_created: bool = false
var _chunk_coordinator: ChunkCoordinator

func get_chunk_coordinator() -> ChunkCoordinator:
	return _chunk_coordinator

func _enter_tree() -> void:
	if world_config != null and world_config.is_infinite_world():
		_setup_chunk_coordinator()
		# In infinite world mode, ChunkCoordinator handles planet generation.
		# Skip _generate_catalog_planets() — chunk (0,0) gets homeworlds
		# via the coordinator's lazy generation path.
		_catalog_generated = true
		return
	_generate_catalog_planets()

func _ready() -> void:
	if world_config != null and world_config.is_infinite_world() and _chunk_coordinator != null:
		_chunk_coordinator.set_layout_seed(world_config.layout_seed)
		# Restore a saved chunk cache (factions, coords) before the start chunk
		# is instantiated, so planet nodes reflect the restored run.
		_apply_pending_chunk_load()
		# Generate start chunk (0,0) which has the homeworlds.
		_chunk_coordinator.ensure_chunks_active(_initial_fov_regions(), &"xl")
	else:
		regenerate()
	_create_runtime_modules()

func set_layout_seed(value: int) -> void:
	world_config.layout_seed = value
	if world_config != null and world_config.is_infinite_world() and _chunk_coordinator != null:
		var state: Node = _game_state()
		if state != null:
			state.reset_for_infinite_world()
			_chunk_coordinator.reset_for_layout_seed(value)
			call_deferred("_refresh_chunks")
			return
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

	var cell_positions: Array[Vector2] = WorldGenerator.grid_cell_positions(config, layout_items.size())
	var column_count := config.resolved_columns(layout_items.size())
	var row_count := ceili(float(layout_items.size()) / float(column_count))
	var cell_size := Vector2(
		config.design_size.x / float(column_count),
		config.design_size.y / float(row_count)
	)
	var assigned_slots: Dictionary = {}
	var slots: Array[int] = []
	for slot in layout_items.size():
		slots.append(slot)
	_shuffle(slots, rng)
	for index in layout_items.size():
		assigned_slots[layout_items[index]] = slots[index]
	# Generated sectors must not start the two factions adjacent: a corner
	# homeworld with the enemy homeworld as its second neighbour would have
	# only one neutral neighbour and stall the scout/first-scan progression.
	_separate_homeworlds(layout_items, assigned_slots, column_count, row_count)

	for item in layout_items:
		var slot: int = assigned_slots[item]
		var cell_center: Vector2 = cell_positions[slot]
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

	# --- Density-field sector pass (opt-in; separate RNG keeps the seed contract) ---
	if config.resolved_sector_count() > 0 and not config.sector_flavors.is_empty():
		_apply_sector_classification(layout_items, config)

	layout_completed.emit(layout_items)

	var navigation: NavigationField = get_node_or_null("NavigationField") as NavigationField
	if navigation != null:
		navigation.world_config = config
		navigation.request_rebuild()
	if not Engine.is_editor_hint():
		var network: Node = get_node_or_null("PlanetNetwork")
		if network != null and network.has_method("invalidate_neighbor_cache"):
			network.call("invalidate_neighbor_cache")

func _create_runtime_modules() -> void:
	if Engine.is_editor_hint() or _runtime_modules_created:
		return
	var network: Node = get_node_or_null("PlanetNetwork")
	var worker_manager: Node = get_node_or_null("WorkerManager")
	if network == null or worker_manager == null:
		return
	var economy_manager: Node = PLANET_ECONOMY_MANAGER_SCRIPT.new()
	economy_manager.name = "EconomyManager"
	economy_manager.set("economy_config", economy_config if economy_config != null else DEFAULT_ECONOMY_CONFIG)
	add_child(economy_manager)

	var cpu_ai: Node = CPU_DISPATCH_AI_SCRIPT.new()
	cpu_ai.name = "CpuDispatchAI"
	cpu_ai.call("configure", self, network, worker_manager, cpu_dispatch_config if cpu_dispatch_config != null else DEFAULT_CPU_DISPATCH_CONFIG)
	add_child(cpu_ai)

	var ship_manager: Node = SHIP_MANAGER_SCRIPT.new()
	ship_manager.name = "ShipManager"
	ship_manager.call("configure", self, get_node_or_null("NavigationField"), ship_config if ship_config != null else DEFAULT_SHIP_CONFIG, technology_catalog if technology_catalog != null else DEFAULT_TECHNOLOGY_CATALOG, network)
	add_child(ship_manager)

	var conflict_manager: Node = CONFLICT_MANAGER_SCRIPT.new()
	conflict_manager.name = "ConflictManager"
	conflict_manager.call("configure", self, get_node_or_null("NavigationField"), ship_manager, DEFAULT_TRANSIT_CONFIG)
	add_child(conflict_manager)
	_runtime_modules_created = true

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

	var size_counts := config.resolved_size_class_counts(items.size())
	var assigned_profiles: Array[PlanetSizeProfile] = []
	for _index in size_counts.x:
		assigned_profiles.append(extra_large_profile)
	for _index in size_counts.y:
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

func _separate_homeworlds(items: Array[Planet], assigned_slots: Dictionary, column_count: int, _row_count: int) -> void:
	var homeworlds: Array[Planet] = []
	for item in items:
		if item.planet_role == &"homeworld":
			homeworlds.append(item)
	if homeworlds.size() < 2:
		return
	var first: Planet = homeworlds[0]
	var second: Planet = homeworlds[1]
	var first_slot: int = assigned_slots[first]
	var second_slot: int = assigned_slots[second]
	if not _slots_adjacent(first_slot, second_slot, column_count):
		return
	# Swap the second homeworld with a neutral planet whose slot is not adjacent
	# to the first homeworld. Swapping after all shuffles keeps the RNG
	# consumption order (and therefore the seed contract) unchanged.
	for item in items:
		if item.planet_role == &"homeworld":
			continue
		var candidate_slot: int = assigned_slots[item]
		if _slots_adjacent(first_slot, candidate_slot, column_count):
			continue
		assigned_slots[second] = candidate_slot
		assigned_slots[item] = second_slot
		return

func _slots_adjacent(slot_a: int, slot_b: int, column_count: int) -> bool:
	if column_count <= 0:
		return false
	var col_a := slot_a % column_count
	var row_a := int(slot_a / float(column_count))
	var col_b := slot_b % column_count
	var row_b := int(slot_b / float(column_count))
	return absi(col_a - col_b) + absi(row_a - row_b) == 1

func _shuffle(values: Array, rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var value: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = value

func _scale_for(item: Planet, rng: RandomNumberGenerator) -> float:
	var profile: PlanetSizeProfile = item.get_size_profile()
	var config: WorldConfig = world_config if world_config != null else DEFAULT_WORLD_CONFIG
	return rng.randf_range(profile.scale_range.x, profile.scale_range.y) * config.resolved_planet_visual_scale()

## Classifies planets against sector anchors, perturbs their positions by role,
## and modulates render scale. Uses a dedicated RNG (layout_seed + 9999) so the
## main layout RNG stream and therefore the seed contract stay untouched.
func _apply_sector_classification(items: Array[Planet], config: WorldConfig) -> void:
	var sector_rng := RandomNumberGenerator.new()
	sector_rng.seed = config.layout_seed + 9999
	var anchors := SectorClassifier.generate_anchors(
		config.layout_seed,
		config.resolved_sector_count(),
		config.design_size,
		config.sector_flavors,
		config.resolved_sector_radius()
	)
	var noise := SectorClassifier.create_noise(config.layout_seed)
	for item in items:
		var classification := SectorClassifier.classify_position(item.position, anchors, noise)
		item.set_meta("sector_id", classification["sector_id"])
		item.set_meta("sector_role", classification["role"])
		item.set_meta("sector_depth", classification["depth"])
		item.position = SectorClassifier.adjust_position(item.position, classification, sector_rng)
		item.scale = item.scale * SectorClassifier.scale_multiplier(classification)

func _queue_layout() -> void:
	if is_inside_tree():
		if world_config != null and world_config.is_infinite_world() and _chunk_coordinator != null:
			_chunk_coordinator.set_layout_seed(world_config.layout_seed)
			call_deferred("_refresh_chunks")
		else:
			call_deferred("regenerate")

func _refresh_chunks() -> void:
	if _chunk_coordinator != null:
		_chunk_coordinator.ensure_chunks_active(_initial_fov_regions(), &"xl")

## Hands a restored RunSaveData chunk payload to the coordinator before the
## start chunks are instantiated, so saved factions survive the rebuild.
func _apply_pending_chunk_load() -> void:
	if _chunk_coordinator == null:
		return
	var state: Node = _game_state()
	if state == null or not state.has_method("consume_pending_chunk_data"):
		return
	var data: ChunkSaveData = state.consume_pending_chunk_data()
	if data == null:
		return
	_chunk_coordinator.load_state(data)

func _game_state() -> Node:
	return GameStateAccess.autoload(self)

func _setup_chunk_coordinator() -> void:
	if _chunk_coordinator != null and is_instance_valid(_chunk_coordinator):
		return
	_chunk_coordinator = CHUNK_COORDINATOR_SCRIPT.new() as ChunkCoordinator
	_chunk_coordinator.name = "ChunkCoordinator"
	_chunk_coordinator.configure(
		self,
		get_node_or_null("NavigationField") as NavigationField,
		world_config if world_config != null else DEFAULT_WORLD_CONFIG,
		planet_catalog if planet_catalog != null else DEFAULT_PLANET_CATALOG,
		size_profiles,
		world_config.layout_seed if world_config != null else 0
	)
	add_child(_chunk_coordinator)
	var state: Node = get_tree().root.get_node_or_null("GameState")
	if state != null and not state.faction_changed.is_connected(_chunk_coordinator._on_faction_changed):
		state.faction_changed.connect(_chunk_coordinator._on_faction_changed)

func _initial_fov_regions() -> Array:
	if world_config == null:
		return []
	var cs := world_config.resolved_cell_size()
	var radius_cells: int = world_config.planet_fov_radius
	if _chunk_coordinator != null and is_instance_valid(_chunk_coordinator):
		radius_cells = _chunk_coordinator.player_fov_radius()
	var radius := float(radius_cells) * cs.x
	return [Rect2(Vector2.ZERO, world_config.design_size).grow(radius)]
