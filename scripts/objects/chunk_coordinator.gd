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
# Density-field sector cache (opt-in; recomputed when the layout seed changes).
var _sector_anchors: Array[SectorAnchor] = []
var _sector_noise: FastNoiseLite
var _sector_cache_ready := false
# Cluster-Void generation (Makulatur system) — untyped to avoid alphabetical
# load-order issues (chunk_coordinator.gd loads before cluster_data.gd).
var _clusters: Array = []  # Array[ClusterData]
var _cluster_cache_ready := false
var _sun_nodes: Dictionary = {}  # cluster_id -> Sun node

func configure(field: Node2D, navigation: NavigationField, world_config: WorldConfig, base_catalog: PlanetCatalog, size_profiles: Array[PlanetSizeProfile], layout_seed: int) -> void:
	_field = field
	_navigation = navigation
	_world_config = world_config if world_config != null else DEFAULT_WORLD_CONFIG
	_base_catalog = base_catalog if base_catalog != null else DEFAULT_PLANET_CATALOG
	_size_profiles = size_profiles
	_layout_seed = layout_seed
	_is_configured = true
	_cluster_cache_ready = false

func set_layout_seed(value: int) -> void:
	if _layout_seed != value:
		_sector_cache_ready = false
		_sector_anchors = [] as Array[SectorAnchor]
		_sector_noise = null
	_layout_seed = value

func reset_for_layout_seed(value: int) -> void:
	_layout_seed = value
	_sector_cache_ready = false
	_sector_anchors = [] as Array[SectorAnchor]
	_sector_noise = null
	_cluster_cache_ready = false
	_clusters = []
	# Free sun nodes
	for cluster_id in _sun_nodes:
		var sun_node = _sun_nodes[cluster_id]
		if sun_node != null and is_instance_valid(sun_node):
			sun_node.queue_free()
	_sun_nodes.clear()
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

## Returns the largest FoV radius among active player-owned planets. The
## Planet facade includes researched scanner bonuses, so infinite-world
## activation follows the same upgrade-aware rule as the planet itself.
func player_fov_radius() -> int:
	var radius: int = _world_config.planet_fov_radius if _world_config != null else 2
	for planet_value in _active_planets.values():
		var planet: Planet = planet_value as Planet
		if planet != null and is_instance_valid(planet) and planet.get_faction() == GameState.FACTION_PLAYER:
			radius = maxi(radius, planet.get_fov_radius())
	return radius

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

## Returns the cell key for a planet position.
func planet_cell(world_position: Vector2) -> Vector2i:
	var cs := _world_config.resolved_cell_size()
	return Vector2i(floori(world_position.x / cs.x), floori(world_position.y / cs.y))

func _cell_to_chunk(cell: Vector2i) -> Vector2i:
	var cs: int = _world_config.chunk_size
	return Vector2i(floori(float(cell.x) / float(cs)), floori(float(cell.y) / float(cs)))

func _chunk_to_cell_base(chunk_coord: Vector2i) -> Vector2i:
	var cs: int = _world_config.chunk_size
	return Vector2i(chunk_coord.x * cs, chunk_coord.y * cs)

func _cells_in_rect(rect: Rect2) -> Array[Vector2i]:
	var cs := _world_config.resolved_cell_size()
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
	# Ensure clusters are generated
	_ensure_clusters_generated()

	var cs: int = _world_config.chunk_size
	var c_seed := WorldGenerator.chunk_seed(_layout_seed, chunk_coord.x, chunk_coord.y)
	var definitions := WorldGenerator.generate_chunk_planets(
		_base_catalog, chunk_coord.x, chunk_coord.y, c_seed, cs, _world_config, max_size_class
	)
	var cell_base := _chunk_to_cell_base(chunk_coord)
	var data_array: Array = []

	# Per-chunk RNG for organic placement (breaks grid pattern)
	var chunk_rng := RandomNumberGenerator.new()
	chunk_rng.seed = c_seed + 99999  # Separate from planet composition seed

	# Track cluster-local slot usage per overlapping cluster
	var cluster_slot_counters: Dictionary = {}  # cluster_id -> next free slot index

	for slot in definitions.size():
		var def: PlanetDefinition = definitions[slot]
		if def == null:
			continue
		var local_col := slot % cs
		var local_row := int(slot / float(cs))
		var cell := Vector2i(cell_base.x + local_col, cell_base.y + local_row)
		var base_pos := _cell_center(cell)
		var world_pos := base_pos

		# --- Cluster-aware organic positioning ---
		if _world_config.is_cluster_generation_enabled() and not _clusters.is_empty():
			# Find the NEAREST cluster (not just contained — attraction model)
			var nearest_cluster = null
			var nearest_dist := INF
			for cluster in _clusters:
				var dist: float = base_pos.distance_to(cluster.center_position)
				if dist < nearest_dist:
					nearest_dist = dist
					nearest_cluster = cluster

			if nearest_cluster != null:
				var in_cluster_radius: bool = nearest_dist <= nearest_cluster.radius

				if in_cluster_radius:
					# Inside cluster: use next available cluster-local slot
					var cid: StringName = nearest_cluster.cluster_id
					if not cluster_slot_counters.has(cid):
						cluster_slot_counters[cid] = 0
					var slot_idx: int = cluster_slot_counters[cid]
					if slot_idx < nearest_cluster.planet_slots.size():
						world_pos = nearest_cluster.planet_slots[slot_idx]
					else:
						# Overflow: place around cluster center with organic jitter
						var angle: float = chunk_rng.randf() * TAU
						var dist_r: float = chunk_rng.randf_range(10.0, nearest_cluster.radius * 0.9)
						world_pos = nearest_cluster.center_position + Vector2(cos(angle), sin(angle)) * dist_r
					cluster_slot_counters[cid] = slot_idx + 1
					# Cluster resource bias must never assign ownership. Homeworld
					# identities come from the origin catalog; procedural planets
					# remain neutral until an explicit colonization action.
					if def.planet_role != &"homeworld":
						def.faction = _assign_faction_from_cluster(nearest_cluster, def.planet_role)
				else:
					# Outside cluster but attracted toward it — organic drift
					var to_cluster: Vector2 = nearest_cluster.center_position - base_pos
					var attract_strength: float = clampf(1.0 - (nearest_dist / (nearest_cluster.radius * 3.0)), 0.0, 0.4)
					var drift: Vector2 = to_cluster * attract_strength

					# Heavy organic jitter to break grid
					var cell_size: Vector2 = _world_config.resolved_cell_size()
					var jitter_x: float = chunk_rng.randf_range(-cell_size.x * 0.6, cell_size.x * 0.6)
					var jitter_y: float = chunk_rng.randf_range(-cell_size.y * 0.6, cell_size.y * 0.6)
					world_pos = base_pos + drift + Vector2(jitter_x, jitter_y)
			else:
				# No clusters at all — pure organic jitter
				var cell_size_fallback: Vector2 = _world_config.resolved_cell_size()
				var jx: float = chunk_rng.randf_range(-cell_size_fallback.x * 0.6, cell_size_fallback.x * 0.6)
				var jy: float = chunk_rng.randf_range(-cell_size_fallback.y * 0.6, cell_size_fallback.y * 0.6)
				world_pos = base_pos + Vector2(jx, jy)
		else:
			# Cluster system disabled — legacy grid (unchanged)
			pass

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
	# --- Density-field sector classification (opt-in, deterministic per seed) ---
	if _world_config.resolved_sector_count() > 0 and not _world_config.sector_flavors.is_empty():
		var anchors := _get_sector_anchors()
		var noise := _get_sector_noise()
		for data in data_array:
			var classification := SectorClassifier.classify_position(data.world_position, anchors, noise)
			data.sector_id = classification["sector_id"]
			data.sector_role = classification["role"]
			data.sector_depth = classification["depth"]
			data.sector_flavor_id = classification["sector_id"]
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
		var local_ids: Array = []
		for generated_data in data_array:
			var pd: ChunkPlanetData = generated_data as ChunkPlanetData
			if pd != null:
				local_ids.append(pd.planet_id)
		state.deal_local_resources(local_ids, pool, c_seed)

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
	var profile: PlanetSizeProfile = _resolve_size_profile(data.size_class)
	planet.configure_from_cache(data, profile)
	_field.add_child(planet)
	planet.global_position = data.world_position
	planet.scale = Vector2.ONE * _planet_render_scale(data, profile)
	planet.set_meta("sector_id", data.sector_id)
	planet.set_meta("sector_role", data.sector_role)
	planet.set_meta("sector_depth", data.sector_depth)
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
	planet.visible = false
	planet.process_mode = Node.PROCESS_MODE_DISABLED
	planet.set_meta("pending_free", true)
	call_deferred("_actually_free_planet", cell)

func _actually_free_planet(cell: Vector2i) -> void:
	var planet: Planet = _active_planets.get(cell)
	if planet == null or not is_instance_valid(planet):
		_active_planets.erase(cell)
		return
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

## --- Cluster helpers (Makulatur system) ---

## Ensure clusters are generated if cluster generation is enabled
func _ensure_clusters_generated() -> void:
	if _cluster_cache_ready or not _world_config.is_cluster_generation_enabled():
		return
	_cluster_cache_ready = true

	# Get world size from config
	var world_size := _world_config.resolved_design_size()
	var planet_count := _world_config.resolved_target_planet_count(100)  # Estimate

	_clusters = WorldGenerator.generate_clusters(
		_world_config,
		_layout_seed,
		world_size,
		planet_count
	)

	# Spawn sun nodes
	for cluster in _clusters:
		if cluster.sun != null:
			var sun_scene: PackedScene = preload("res://scenes/objects/sun.tscn")
			var sun_node = sun_scene.instantiate()
			sun_node.configure_cluster(
				cluster.cluster_id,
				cluster.sun.mass,
				cluster.sun.glow_radius,
				cluster.sun.temperature,
				cluster.sun.position
			)
			sun_node.name = String(cluster.cluster_id) + "_Sun"
			_field.add_child(sun_node)
			_sun_nodes[cluster.cluster_id] = sun_node

## Find the cluster that contains a given position
func _find_cluster_for_position(position: Vector2):
	for cluster in _clusters:
		if cluster.contains_point(position):
			return cluster
	return null

## Get the index of a planet within a cluster based on position
func _get_cluster_planet_index(cluster, position: Vector2) -> int:
	var min_dist := INF
	var best_idx := -1
	for i in cluster.planet_slots.size():
		var slot_pos: Vector2 = cluster.planet_slots[i]
		var dist := position.distance_to(slot_pos)
		if dist < min_dist:
			min_dist = dist
			best_idx = i
	return best_idx

## Assign faction for a procedural planet. Resource bias describes resource
## distribution only; it must not grant ownership or discovery at world boot.
func _assign_faction_from_cluster(_cluster, planet_role: StringName) -> StringName:
	if planet_role == &"homeworld":
		return GameState.FACTION_PLAYER # Defensive fallback; caller excludes it.
	return GameState.FACTION_NEUTRAL

## Get all clusters (for LoD and other systems)
func get_clusters() -> Array:
	return _clusters

## Get sun nodes (for rendering and interaction)
func get_sun_nodes() -> Dictionary:
	return _sun_nodes

## Check if a position is in a void (no cluster)
func is_void_position(position: Vector2) -> bool:
	return _find_cluster_for_position(position) == null

## --- LoD System for distant clusters ---

## Get cluster LoD level based on distance from player
## Returns: 0 = full detail, 1 = simplified, 2 = minimal, 3 = void-simulated
func get_cluster_lod(cluster, player_position: Vector2) -> int:
	var distance: float = cluster.center_position.distance_to(player_position)
	var lod_radius := _world_config.resolved_cell_size().x * 5.0

	if distance < lod_radius:
		return 0  # Full detail - active simulation
	elif distance < lod_radius * 2:
		return 1  # Simplified - basic resource ticks
	elif distance < lod_radius * 4:
		return 2  # Minimal - faction state only
	else:
		return 3  # Void-simulated - time acceleration

## Check if a cluster should be fully simulated
func should_simulate_cluster(cluster, player_position: Vector2) -> bool:
	return get_cluster_lod(cluster, player_position) <= 1

## Get simplified cluster state for distant LoD
func get_cluster_lod_state(cluster, lod_level: int) -> Dictionary:
	var state := {
		"cluster_id": cluster.cluster_id,
		"lod_level": lod_level,
		"planet_count": cluster.planet_count,
		"resource_bias": cluster.resource_bias,
	}

	if lod_level >= 2:
		state["factions"] = _get_cluster_factions(cluster)
		state["time_acceleration"] = pow(2.0, float(lod_level - 1))

	return state

## Get faction distribution for a cluster
func _get_cluster_factions(cluster) -> Dictionary:
	var factions := {&"a": 0, &"b": 0, &"neutral": 0}
	for cell in _active_planets:
		var planet: Planet = _active_planets[cell] as Planet
		if planet != null and is_instance_valid(planet) and cluster.contains_point(planet.global_position):
			var faction: StringName = planet.get_faction()
			if factions.has(faction):
				factions[faction] += 1
	return factions

## Deterministic per-planet render scale for the infinite path: size-profile
## midpoint × global visual multiplier × optional sector-scale multiplier.
func _planet_render_scale(data: ChunkPlanetData, profile: PlanetSizeProfile) -> float:
	var mid := (profile.scale_range.x + profile.scale_range.y) * 0.5
	var scale := mid * _world_config.resolved_planet_visual_scale()
	if _world_config.resolved_sector_count() > 0 and not _world_config.sector_flavors.is_empty():
		scale *= SectorClassifier.scale_multiplier({
			"role": data.sector_role,
			"depth": data.sector_depth,
		})
	return scale

## Cached sector anchors covering a virtual region centred on the world origin.
func _get_sector_anchors() -> Array[SectorAnchor]:
	if not _sector_cache_ready:
		_sector_cache_ready = true
		if _world_config.resolved_sector_count() <= 0 or _world_config.sector_flavors.is_empty():
			_sector_anchors = [] as Array[SectorAnchor]
		else:
			var cs := _world_config.resolved_cell_size()
			var span := _world_config.resolved_sector_radius() * float(_world_config.resolved_sector_count()) * 3.0
			var virtual_size := Vector2(maxf(span, cs.x), maxf(span, cs.y))
			_sector_anchors = SectorClassifier.generate_anchors(
				_layout_seed,
				_world_config.resolved_sector_count(),
				virtual_size,
				_world_config.sector_flavors,
				_world_config.resolved_sector_radius()
			)
			for anchor in _sector_anchors:
				anchor.position -= virtual_size * 0.5
	return _sector_anchors

func _get_sector_noise() -> FastNoiseLite:
	if _sector_noise == null:
		_sector_noise = SectorClassifier.create_noise(_layout_seed)
	return _sector_noise

func _resolve_size_class(slot: int, chunk_size: int) -> StringName:
	var total := chunk_size * chunk_size
	var size_counts := _world_config.resolved_size_class_counts(total)
	if slot < size_counts.x:
		return &"xl"
	elif slot < size_counts.x + size_counts.y:
		return &"l"
	return &"variable"

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
	var coords: Array[Vector2i] = []
	for key in _chunk_cache.keys():
		coords.append(key as Vector2i)
	data.cached_chunk_coords = coords
	var states: Dictionary = {}
	for planet_id in _planet_id_to_data:
		var pd = _planet_id_to_data[planet_id]
		if pd != null:
			states[planet_id] = {
				"faction": pd.faction,
				"resource_id": pd.resource_id,
				"sector_id": pd.sector_id,
				"sector_role": pd.sector_role,
				"sector_depth": pd.sector_depth,
				"sector_flavor_id": pd.sector_flavor_id,
			}
	data.planet_states = states
	return data

func load_state(data: ChunkSaveData) -> void:
	if data == null:
		return
	_layout_seed = data.layout_seed
	for chunk_coord in data.cached_chunk_coords:
		if not _chunk_cache.has(chunk_coord):
			_generate_chunk(chunk_coord, &"xl")
	var state := _game_state()
	for planet_id in data.planet_states:
		var pd = _planet_id_to_data.get(planet_id)
		if pd != null:
			var entry: Dictionary = data.planet_states[planet_id]
			pd.faction = entry.get("faction", pd.faction)
			pd.resource_id = entry.get("resource_id", pd.resource_id)
			pd.sector_id = entry.get("sector_id", pd.sector_id)
			pd.sector_role = entry.get("sector_role", pd.sector_role)
			pd.sector_depth = entry.get("sector_depth", pd.sector_depth)
			pd.sector_flavor_id = entry.get("sector_flavor_id", pd.sector_flavor_id)
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
	var sector_id: StringName = &""
	var sector_role: StringName = &"void"
	var sector_depth: float = 0.0
	var sector_flavor_id: StringName = &""
