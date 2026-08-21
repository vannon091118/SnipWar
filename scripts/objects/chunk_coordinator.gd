class_name ChunkCoordinator
extends Node

## Manages the infinite procedural chunk-grid world. Each chunk is a square of
## chunk_size × chunk_size planet slots. Chunks are generated lazily when the
## FoV region demands them, and planets outside the FoV are freed via a
## one-frame Halt-Phase to avoid signal gaps.
##
## The lightweight cache stores ChunkPlanetData (not Node instances), so the
## active node count stays bounded. Everything is seed-deterministic: the same
## layout_seed + chunk_coord always produces the same positions, IDs and
## compositions.

signal planet_added(planet: Planet)
signal planet_removed(planet: Planet)

const PLANET_SCENE: PackedScene = preload("res://scenes/objects/planets/planet.tscn")
const DEFAULT_WORLD_CONFIG: WorldConfig = preload("res://resources/config/world_default.tres")
const DEFAULT_PLANET_CATALOG: PlanetCatalog = preload("res://resources/config/planet_catalog.tres")

var _world_config: WorldConfig
var _base_catalog: PlanetCatalog
var _size_profiles: Array[PlanetSizeProfile] = []
var _layout_seed: int = 0

# Chunk cache: Vector2i -> Array[ChunkPlanetData]
var _chunk_cache: Dictionary = {}
# Fast planet_id -> ChunkPlanetData lookup (O(1))
var _planet_id_to_data: Dictionary = {}
# Active planet nodes: Vector2i (cell) -> Planet
var _active_planets: Dictionary = {}
# LRU ordering: Array[Vector2i] (most-recently-used at end)
var _lru_order: Array[Vector2i] = []

var _navigation: NavigationField
var _field: Node2D
var _is_configured := false

func configure(field: Node2D, navigation: NavigationField, world_config: WorldConfig, base_catalog: PlanetCatalog, size_profiles: Array[PlanetSizeProfile], layout_seed: int) -> void:
	_field = field
	_navigation = navigation
	_world_config = world_config if world_config != null else DEFAULT_WORLD_CONFIG
	_base_catalog = base_catalog if base_catalog != null else DEFAULT_PLANET_CATALOG
	_size_profiles = size_profiles
	_layout_seed = layout_seed
	_is_configured = true

func set_layout_seed(value: int) -> void:
	_layout_seed = value

func reset_for_layout_seed(value: int) -> void:
	_layout_seed = value
	for cell in _active_planets.keys():
		var planet: Planet = _active_planets[cell]
		if planet != null and is_instance_valid(planet):
			planet.set_meta("pending_free", true)
			planet_removed.emit(planet)
			if _navigation != null and _navigation.has_planet(planet):
				_navigation.remove_planet(planet)
			planet.queue_free()
	_active_planets.clear()
	_chunk_cache.clear()
	_planet_id_to_data.clear()
	_lru_order.clear()
	if _navigation != null:
		_navigation.rebuild()

func get_active_planets() -> Array:
	var result: Array = []
	for planet in _active_planets.values():
		if is_instance_valid(planet):
			result.append(planet)
	return result

func get_active_bounds() -> Rect2:
	if _active_planets.is_empty():
		if _world_config != null:
			return Rect2(Vector2.ZERO, _world_config.design_size)
		return Rect2(Vector2.ZERO, Vector2(960, 540))
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for planet in _active_planets.values():
		if not is_instance_valid(planet):
			continue
		var pos: Vector2 = planet.global_position
		min_pos.x = minf(min_pos.x, pos.x)
		min_pos.y = minf(min_pos.y, pos.y)
		max_pos.x = maxf(max_pos.x, pos.x)
		max_pos.y = maxf(max_pos.y, pos.y)
	return Rect2(min_pos, max_pos - min_pos)

func is_infinite_world() -> bool:
	return _world_config != null and _world_config.is_infinite_world()

## Ensures all chunks overlapping the given FoV regions are active (planets
## instantiated). Planets outside all regions are culled via Halt-Phase.
func ensure_chunks_active(fov_regions: Array, max_size_class: StringName) -> void:
	if not _is_configured or not is_infinite_world():
		return
	var needed_cells: Dictionary = {}
	for region in fov_regions:
		var rect: Rect2 = region as Rect2
		if rect == null:
			continue
		var cells := _cells_in_rect(rect)
		for cell in cells:
			needed_cells[cell] = true
	var chunks_to_generate: Dictionary = {}
	for cell in needed_cells:
		var chunk_coord := _cell_to_chunk(cell)
		if not _chunk_cache.has(chunk_coord):
			chunks_to_generate[chunk_coord] = true
	for chunk_coord in chunks_to_generate:
		_generate_chunk(chunk_coord, max_size_class)

	for cell in needed_cells:
		if not _active_planets.has(cell):
			_instantiate_planet(cell)
		else:
			# Planet exists but may be in Halt-Phase (pending free) — re-enable it.
			var existing: Planet = _active_planets.get(cell)
			if existing != null and is_instance_valid(existing) and existing.get_meta("pending_free", false):
				existing.remove_meta("pending_free")
				existing.visible = true
				existing.process_mode = Node.PROCESS_MODE_INHERIT

	var to_cull: Array = []
	for cell in _active_planets.keys():
		if not needed_cells.has(cell):
			to_cull.append(cell)
	for cell in to_cull:
		_cull_planet(cell)
	if _navigation != null:
		_navigation.rebuild()
		var network: Node = _navigation.get_parent().get_node_or_null("PlanetNetwork")
		if not Engine.is_editor_hint() and network != null and network.has_method("invalidate_neighbor_cache"):
			network.call("invalidate_neighbor_cache")

## Synchronously generates chunks containing the given cells (for route plotting).
func generate_chunks_sync(cells: Array) -> void:
	if not _is_configured or not is_infinite_world():
		return
	for cell_value in cells:
		var cell: Vector2i = cell_value
		var chunk_coord := _cell_to_chunk(cell)
		if not _chunk_cache.has(chunk_coord):
			_generate_chunk(chunk_coord, &"variable")
		if not _active_planets.has(cell):
			_instantiate_planet(cell)
	if _navigation != null:
		_navigation.rebuild()
		var network: Node = _navigation.get_parent().get_node_or_null("PlanetNetwork")
		if not Engine.is_editor_hint() and network != null and network.has_method("invalidate_neighbor_cache"):
			network.call("invalidate_neighbor_cache")

## Returns the cell key for a planet position.
func planet_cell(world_position: Vector2) -> Vector2i:
	var cs := _world_config.resolved_cell_size()
	return Vector2i(floori(world_position.x / cs.x), floori(world_position.y / cs.y))

func _cell_to_chunk(cell: Vector2i) -> Vector2i:
	var cs: int = _world_config.chunk_size
	# Use floori for correct negative-coordinate chunk mapping
	# (int() truncates toward zero, which would map cell -1 to chunk 0).
	return Vector2i(floori(float(cell.x) / float(cs)), floori(float(cell.y) / float(cs)))

func _chunk_to_cell_base(chunk_coord: Vector2i) -> Vector2i:
	var cs: int = _world_config.chunk_size
	return Vector2i(chunk_coord.x * cs, chunk_coord.y * cs)

func _cells_in_rect(rect: Rect2) -> Array[Vector2i]:
	var cs := _world_config.resolved_cell_size()
	# floori for the inclusive lower bound, ceili(end) - 1 for the exclusive
	# upper bound. floori(rect.end / cs) over-includes the cell whose origin sits
	# exactly on the exclusive Rect2.end (the initial FoV region aligns end to a
	# cell boundary, so this generated one extra ring).
	var min_col := floori(rect.position.x / cs.x)
	var min_row := floori(rect.position.y / cs.y)
	var max_col := ceili(rect.end.x / cs.x) - 1
	var max_row := ceili(rect.end.y / cs.y) - 1
	var cells: Array[Vector2i] = []
	for col in range(min_col, max_col + 1):
		for row in range(min_row, max_row + 1):
			cells.append(Vector2i(col, row))
	return cells

func _generate_chunk(chunk_coord: Vector2i, max_size_class: StringName) -> void:
	var cs: int = _world_config.chunk_size
	var c_seed := WorldGenerator.chunk_seed(_layout_seed, chunk_coord.x, chunk_coord.y)
	var definitions := WorldGenerator.generate_chunk_planets(
		_base_catalog, chunk_coord.x, chunk_coord.y, c_seed, cs, _world_config, max_size_class
	)
	var cell_base := _chunk_to_cell_base(chunk_coord)
	var data_array: Array = []
	for slot in definitions.size():
		var def: PlanetDefinition = definitions[slot]
		if def == null:
			continue
		var local_col := slot % cs
		var local_row := int(slot / float(cs))
		var cell := Vector2i(cell_base.x + local_col, cell_base.y + local_row)
		var world_pos := _cell_center(cell)
		var data := ChunkPlanetData.new()
		data.planet_id = def.planet_id
		data.display_name = def.display_name
		data.planet_role = def.planet_role
		data.faction = def.faction
		data.composition_base_texture = def.composition_base_texture
		data.composition_tint = def.composition_tint
		data.composition_decal_textures = def.composition_decal_textures
		data.detail_profile = def.detail_profile
		data.size_class = _resolve_size_class(slot, cs)
		data.resource_id = &""
		data.signature_resource = def.signature_resource
		data.signature_probability = def.signature_probability
		data.world_position = world_pos
		data.cell = cell
		data_array.append(data)
		_planet_id_to_data[data.planet_id] = data
	_chunk_cache[chunk_coord] = data_array
	_lru_touch(chunk_coord)
	_evict_if_needed()
	var state := _game_state()
	if state != null:
		for generated_data in data_array:
			var generated_planet_data: ChunkPlanetData = generated_data as ChunkPlanetData
			if generated_planet_data != null and generated_planet_data.planet_role == &"homeworld":
				state.register_homeworld(generated_planet_data.faction, generated_planet_data.planet_id)
		var pool: ResourcePool = null
		var map := _get_map_definition()
		if map != null:
			pool = map.resource_pool
		state.deal_resources_for_planets(data_array, pool, c_seed)

func _instantiate_planet(cell: Vector2i) -> void:
	var chunk_coord := _cell_to_chunk(cell)
	var data_array: Array = _chunk_cache.get(chunk_coord, [])
	var local_col := cell.x - chunk_coord.x * _world_config.chunk_size
	var local_row := cell.y - chunk_coord.y * _world_config.chunk_size
	var slot_index := local_row * _world_config.chunk_size + local_col
	if slot_index >= data_array.size():
		return
	var data: ChunkPlanetData = data_array[slot_index]
	if data == null:
		return
	var planet: Planet = PLANET_SCENE.instantiate()
	planet.name = data.display_name
	# Configure BEFORE add_child() so _ready() registers the real planet_id/
	# faction and applies the cached detail/size profiles (mirrors the finite
	# path, where apply_definition() runs during _enter_tree).
	var profile: PlanetSizeProfile = _resolve_size_profile(data.size_class)
	planet.configure_from_cache(data, profile)
	_field.add_child(planet)
	planet.global_position = data.world_position
	var state := _game_state()
	if state != null:
		state.seed_starting_workers(data.planet_id, profile)
		planet.set_initial_workers(state.starting_workers_of(data.planet_id))
	planet.set_meta("cell", cell)
	_active_planets[cell] = planet
	if _navigation != null:
		_navigation.add_planet(planet, cell)
	planet_added.emit(planet)

func _cull_planet(cell: Vector2i) -> void:
	var planet: Planet = _active_planets.get(cell)
	if planet == null or not is_instance_valid(planet):
		_active_planets.erase(cell)
		return
	# Halt-Phase: disable first, then deferred free
	planet.visible = false
	planet.process_mode = Node.PROCESS_MODE_DISABLED
	planet.set_meta("pending_free", true)
	call_deferred("_actually_free_planet", cell)

func _actually_free_planet(cell: Vector2i) -> void:
	var planet: Planet = _active_planets.get(cell)
	if planet == null or not is_instance_valid(planet):
		_active_planets.erase(cell)
		return
	# If the planet was re-enabled (meta cleared), don't free it.
	if not planet.get_meta("pending_free", false):
		return
	_active_planets.erase(cell)
	if _navigation != null and _navigation.has_planet(planet):
		_navigation.remove_planet(planet)
	planet_removed.emit(planet)
	planet.queue_free()

func _cell_center(cell: Vector2i) -> Vector2:
	var cs := _world_config.resolved_cell_size()
	return Vector2(
		(float(cell.x) + 0.5) * cs.x,
		(float(cell.y) + 0.5) * cs.y
	)

func _resolve_size_class(slot: int, chunk_size: int) -> StringName:
	var total := chunk_size * chunk_size
	var size_counts := _world_config.resolved_size_class_counts(total)
	if slot < size_counts.x:
		return &"xl"
	elif slot < size_counts.x + size_counts.y:
		return &"l"
	return &"variable"

## Maps a resolved size class back to the WorldConfig size profile. Shared with
## PlanetProcedural so coordinator and planet never diverge.
func _resolve_size_profile(size_class: StringName) -> PlanetSizeProfile:
	return PlanetProcedural.resolve_size_profile(_world_config, _size_profiles, size_class)

func _lru_touch(chunk_coord: Vector2i) -> void:
	_lru_order.erase(chunk_coord)
	_lru_order.append(chunk_coord)

func _evict_if_needed() -> void:
	var max_chunks: int = _world_config.max_cached_chunks if _world_config != null else 200
	while _lru_order.size() > max_chunks:
		var oldest: Vector2i = _lru_order.pop_front()
		var data_array: Array = _chunk_cache.get(oldest, [])
		for data in data_array:
			if data != null:
				_planet_id_to_data.erase(data.planet_id)
		_chunk_cache.erase(oldest)

func _on_faction_changed(planet_id: StringName, _old_faction: StringName, new_faction: StringName) -> void:
	var data: Variant = _planet_id_to_data.get(planet_id)
	if data != null and data is ChunkPlanetData:
		(data as ChunkPlanetData).faction = new_faction

func _game_state() -> Node:
	return GameStateAccess.autoload(self)

func _get_map_definition() -> MapDefinition:
	var background := _field.get_parent() as Node2D
	if background == null:
		return null
	var scenario: ScenarioDefinition = background.get("active_scenario")
	if scenario != null and scenario.map_definition != null:
		return scenario.map_definition
	return null

## --- Save / Load ---

func save_state() -> ChunkSaveData:
	var data := ChunkSaveData.new()
	data.layout_seed = _layout_seed
	data.cached_chunk_coords = _chunk_cache.keys() as Array[Vector2i]
	var states: Dictionary = {}
	for planet_id in _planet_id_to_data:
		var pd = _planet_id_to_data[planet_id]
		if pd != null:
			states[planet_id] = {
				"faction": pd.faction,
				"resource_id": pd.resource_id,
			}
	data.planet_states = states
	return data

func load_state(data: ChunkSaveData) -> void:
	if data == null:
		return
	_layout_seed = data.layout_seed
	# Re-generate cached chunks from saved coordinates.
	for chunk_coord in data.cached_chunk_coords:
		if not _chunk_cache.has(chunk_coord):
			_generate_chunk(chunk_coord, &"xl")
	# Apply saved faction states.
	var state := _game_state()
	for planet_id in data.planet_states:
		var pd = _planet_id_to_data.get(planet_id)
		if pd != null:
			var entry: Dictionary = data.planet_states[planet_id]
			pd.faction = entry.get("faction", pd.faction)
			pd.resource_id = entry.get("resource_id", pd.resource_id)
			if state != null:
				state.set_faction(planet_id, pd.faction)

## Lightweight data for a generated planet (not a Node).
class ChunkPlanetData:
	extends RefCounted
	var planet_id: StringName
	var display_name: String
	var planet_role: StringName = &"planet"
	var composition_base_texture: Texture2D
	var composition_tint: Color
	var composition_decal_textures: Array[Texture2D] = []
	var detail_profile: PlanetDetailProfile
	var size_class: StringName
	var faction: StringName
	var resource_id: StringName
	var signature_resource: StringName
	var signature_probability: float
	var world_position: Vector2
	var cell: Vector2i
