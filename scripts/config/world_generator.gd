@tool
class_name WorldGenerator
extends RefCounted

## How many planets the world should contain. A positive
## WorldConfig.target_planet_count wins, otherwise the catalog defines it.
static func target_planet_count(config: WorldConfig, base_catalog: PlanetCatalog) -> int:
	if config != null and config.target_planet_count > 0:
		return config.target_planet_count
	if base_catalog != null:
		return base_catalog.planets.size()
	return 0

## Returns a runtime duplicate of `base_config` with the WorldConfig growth
## contract fully applied: design_size scales by sqrt(growth_factor) so total
## area grows linearly with growth_factor, target_planet_count scales linearly
## when no explicit override was authored, and columns falls back to auto
## resolution. The authored .tres stays untouched — only this duplicate carries
## the live values for the active scene.
static func resolve_runtime_world(base_config: WorldConfig, base_catalog: PlanetCatalog) -> WorldConfig:
	if base_config == null:
		return null
	var resolved: WorldConfig = base_config.duplicate(true) as WorldConfig
	if resolved == null:
		return null
	var growth: float = resolved.growth_factor
	if growth > 1.0001:
		var scale := sqrt(growth)
		resolved.design_size = Vector2(resolved.design_size.x * scale, resolved.design_size.y * scale)
		resolved.columns = 0
		if resolved.target_planet_count <= 0 and base_catalog != null and base_catalog.planets.size() > 0:
			resolved.target_planet_count = resolved.resolved_target_planet_count(base_catalog.planets.size())
	return resolved

## Generates the sector's planet catalog deterministically from the world's
## building-block pool (base textures + tint palettes + decals). The first two
## planets are the player and CPU homeworlds; the remaining planets are neutral
## worlds. This replaces the hand-authored planet catalog: identities, names,
## textures and factions all come from `compose_planet()`/`generate_planet_name()`
## under the layout seed, so every seed yields a fresh but reproducible sector.
static func generate_catalog(config: WorldConfig, seed_value: int, target_count: int) -> PlanetCatalog:
	var catalog := PlanetCatalog.new()
	if config == null or target_count <= 0:
		return catalog
	var definitions: Array[PlanetDefinition] = []
	var used_names: Dictionary = {}
	for index in target_count:
		var planet_seed := slot_seed(seed_value, index)
		var definition := PlanetDefinition.new()
		definition.planet_id = StringName("p%d" % index)
		definition.display_name = _unique_generated_name(planet_seed, index, used_names)
		definition.generated_name = definition.display_name
		definition.planet_role = &"homeworld" if index < 2 else &"planet"
		definition.faction = &"a" if index == 0 else (&"b" if index == 1 else &"neutral")
		var composition := compose_planet(
			planet_seed,
			config.composition_base_textures,
			config.composition_tint_palettes,
			config.composition_decal_pool
		)
		definition.composition_base_texture = composition.get("base_texture", null) as Texture2D
		definition.composition_tint = composition.get("tint", Color.WHITE) as Color
		definition.composition_decal_textures = _texture_array(composition.get("decal_textures", []))
		# Keep planet_texture in sync so legacy consumers (conquest replay path
		# resolution, PlanetDefinition.validate) can resolve generated planets.
		definition.planet_texture = definition.composition_base_texture
		definition.detail_profile = DEFAULT_DETAIL_PROFILE
		definitions.append(definition)
	catalog.planets = definitions
	return catalog

## Generated display names are drawn from a bounded adjective+noun space, so two
## planets in a small sector can collide. Keep the seeded name but suffix the
## colliding one deterministically so the catalog always passes uniqueness
## validation.
static func _unique_generated_name(planet_seed: int, index: int, used_names: Dictionary) -> String:
	var candidate := generate_planet_name(planet_seed)
	if used_names.has(candidate):
		candidate = "%s %d" % [candidate, index]
	used_names[candidate] = true
	return candidate

## Pure grid layout: one cell-center position per planet slot, ordered by slot.
## Jitter and padding clamping stay in SeededLayout so the math is easy to test.
static func grid_cell_positions(config: WorldConfig, planet_count: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if config == null or planet_count <= 0:
		return positions
	var resolved_size := config.resolved_design_size()
	var column_count := config.resolved_columns(planet_count)
	var row_count := ceili(float(planet_count) / float(column_count))
	var cell_size := Vector2(
		resolved_size.x / float(column_count),
		resolved_size.y / float(row_count)
	)
	for slot in planet_count:
		var column := slot % column_count
		var row := floori(float(slot) / float(column_count))
		positions.append(Vector2(
			(float(column) + 0.5) * cell_size.x,
			(float(row) + 0.5) * cell_size.y
		))
	return positions

## Deterministic K-nearest edge builder for layered navigation graphs.
## Returns an array of [first_planet, second_planet] pairs (planet refs, not
## indices), with symmetric deduplication, ordered by source planet index then
## neighbour distance then neighbour identity. Each source contributes at most
## `ceil((planet_count - 1) * ratio)` neighbours; the global cap is enforced
## entirely by ratio * planet_count * (planet_count - 1) unless max_extra_edges
## is provided, in which case the cap wins as soon as the running total exceeds
## it.
static func build_knn_edges(planets: Array, ratio: float, max_edges: int = 0, grid_edges: Array = []) -> Array:
	var result: Array = []
	if planets.size() < 2 or ratio <= 0.0:
		return result
	var k_per_source: int = clampi(int(ceil(float(planets.size() - 1) * clampf(ratio, 0.0, 1.0))), 0, planets.size() - 1)
	if k_per_source <= 0:
		return result
	# Deterministic symmetric edge set: keyed by min/max planet id so a pair is
	# recorded once even when both directions would request it.
	var edge_set: Dictionary = {}
	if not grid_edges.is_empty():
		for edge in grid_edges:
			if edge is Array and edge.size() == 2:
				edge_set[_edge_key(edge[0], edge[1])] = true
	var running_cap: int = max_edges if max_edges > 0 else 0
	for source_index in planets.size():
		var source: Node2D = planets[source_index] as Node2D
		if source == null:
			continue
		var ranked: Array = []
		for other_index in planets.size():
			if other_index == source_index:
				continue
			var other: Node2D = planets[other_index] as Node2D
			if other == null:
				continue
			ranked.append({
				"index": other_index,
				"planet": other,
				"distance": source.global_position.distance_to(other.global_position),
			})
		ranked.sort_custom(func(a, b):
			if a["distance"] != b["distance"]:
				return a["distance"] < b["distance"]
			return int(a["index"]) < int(b["index"])
		)
		ranked = ranked.slice(0, k_per_source)
		# Sort chosen neighbours by identity so the resulting edge order is
		# stable across rebuilds even when distances tie.
		ranked.sort_custom(func(a, b):
			var ai := int(a["index"])
			var bi := int(b["index"])
			if ai == bi:
				return false
			return ai < bi
		)
		for entry in ranked:
			var target: Node2D = entry["planet"] as Node2D
			var key := _edge_key(source, target)
			if edge_set.has(key):
				continue
			edge_set[key] = true
			result.append([source, target])
			if running_cap > 0 and result.size() >= running_cap:
				return result
	return result

static func _edge_key(first: Node2D, second: Node2D) -> String:
	# Use node identity values as the deterministic tie-breaker so two Node2Ds
	# hash to a stable key without round-tripping through Resource refs.
	var first_id := first.get_instance_id()
	var second_id := second.get_instance_id()
	if first_id <= second_id:
		return "%d-%d" % [first_id, second_id]
	return "%d-%d" % [second_id, first_id]

## --- Infinite chunk-grid world ---

## Pure position for one chunk slot. Cluster membership and slot assignment are
## derived from layout seed, chunk coordinate, and slot; no generation-order
## state participates.
static func deterministic_chunk_position(
	config: WorldConfig,
	layout_seed: int,
	chunk_x: int,
	chunk_y: int,
	slot: int,
	chunk_size: int
) -> Vector2:
	var cell := Vector2i(chunk_x * chunk_size + slot % chunk_size, chunk_y * chunk_size + int(slot / float(chunk_size)))
	var cell_size := config.resolved_cell_size()
	var base_pos := Vector2((float(cell.x) + 0.5) * cell_size.x, (float(cell.y) + 0.5) * cell_size.y)
	if config == null or not config.is_cluster_generation_enabled():
		return base_pos
	var clusters := generate_clusters(config, layout_seed, config.resolved_design_size(), chunk_size * chunk_size)
	if clusters.is_empty():
		return base_pos
	var nearest = null
	var nearest_dist := INF
	for cluster in clusters:
		var distance: float = base_pos.distance_to(cluster.center_position)
		if distance < nearest_dist:
			nearest_dist = distance
			nearest = cluster
	if nearest == null or nearest_dist > nearest.radius:
		var jitter_rng := RandomNumberGenerator.new()
		jitter_rng.seed = slot_seed(chunk_seed(layout_seed, chunk_x, chunk_y), slot) + 99999
		return base_pos + Vector2(
			jitter_rng.randf_range(-cell_size.x * 0.6, cell_size.x * 0.6),
			jitter_rng.randf_range(-cell_size.y * 0.6, cell_size.y * 0.6)
		)
	var local_seed := slot_seed(chunk_seed(layout_seed, chunk_x, chunk_y), slot)
	var slot_index := int(local_seed % nearest.planet_slots.size()) if not nearest.planet_slots.is_empty() else 0
	if slot_index < nearest.planet_slots.size():
		return nearest.planet_slots[slot_index]
	var overflow_rng := RandomNumberGenerator.new()
	overflow_rng.seed = local_seed + 17791
	var angle: float = overflow_rng.randf() * TAU
	var radius: float = overflow_rng.randf_range(10.0, nearest.radius * 0.9)
	return nearest.center_position + Vector2(cos(angle), sin(angle)) * radius

## LCNG-based chunk seed. Avoids XOR/abs() overflow pitfalls; int64 math with
## positive masking so the result is always a valid RNG seed.
static func chunk_seed(layout_seed: int, chunk_x: int, chunk_y: int) -> int:
	var s: int = layout_seed
	s = (s * 6364136223846793005 + chunk_x * 1442695040888963407) & 0x7FFFFFFFFFFFFFFF
	s = (s * 6364136223846793005 + chunk_y * 1442695040888963407) & 0x7FFFFFFFFFFFFFFF
	return int(s)

## Deterministic slot seed within a chunk.
static func slot_seed(chunk_seed_value: int, slot: int) -> int:
	return int((chunk_seed_value * 1103515245 + slot * 12345) & 0x7FFFFFFFFFFFFFFF)

## Deterministic planet composition from a seed and the world's asset pool.
## Returns a lightweight Dictionary with base_texture, tint, and decal_textures.
static func _texture_array(value: Variant) -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	if value is Array:
		for entry in value:
			var texture: Texture2D = entry as Texture2D
			if texture != null:
				result.append(texture)
	return result

static func compose_planet(seed_value: int, base_textures: Array[Texture2D], tint_palettes: Array[Color], decal_pool: Array[Texture2D], max_decals: int = 3) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Dictionary = {}
	if base_textures.is_empty():
		result["base_texture"] = null
	else:
		result["base_texture"] = base_textures[rng.randi_range(0, base_textures.size() - 1)]
	if tint_palettes.is_empty():
		result["tint"] = Color.WHITE
	else:
		result["tint"] = tint_palettes[rng.randi_range(0, tint_palettes.size() - 1)]
	var decal_textures: Array[Texture2D] = []
	if not decal_pool.is_empty() and max_decals > 0:
		var count := rng.randi_range(0, mini(max_decals, decal_pool.size()))
		for _i in count:
			decal_textures.append(decal_pool[rng.randi_range(0, decal_pool.size() - 1)])
	result["decal_textures"] = decal_textures
	return result

const DEFAULT_DETAIL_PROFILE: PlanetDetailProfile = preload("res://resources/config/planet_details/default.tres")

const _NAME_ADJECTIVES: Array[String] = [
	"Void", "Crystal", "Ember", "Frost", "Storm", "Dust", "Iron", "Neon",
	"Ash", "Mist", "Solar", "Lunar", "Astral", "Shadow", "Verdant", "Crimson",
	"Azure", "Golden", "Silent", "Hidden", "Lost", "Distant", "Ancient",
	"Broken", "Sacred", "Wild", "Dark", "Pale", "Rusted", "Shattered",
	"Hollow", "Radiant", "Veiled", "Harsh", "Tranquil", "Bitter", "Lone",
	"Far", "Deep", "Bright", "Cold", "Burning", "Still", "Vast", "Remote",
	"Wandering", "Drifting", "Forgotten", "Cursed", "Blessed", "Silent",
]
const _NAME_NOUNS: Array[String] = [
	"Drifter", "Reef", "Bastion", "Hollow", "Reach", "Spire", "Cradle",
	"Wreck", "Veil", "Garden", "Forge", "Haven", "Wastes", "Eye", "Maw",
	"Crown", "Gate", "Anchor", "Shoal", "Ridge", "Vault", "Throne",
	"Echo", "Expanse", "Tide", "Mark", "Node", "Post", "Crossing", "Drop",
	"Dawn", "Dusk", "Mire", "Step", "Ledge", "Marrow", "Husk", "Shell",
	"Pulse", "Flare", "Crest", "Maw", "Bloom", "Ridge", "Hinge", "Pylon",
	"Wellspring", "Threshold", "Sanctum", "Rift",
]

## Deterministic planet name from ~2500 unique adjective+noun combinations.
static func generate_planet_name(seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var adj := _NAME_ADJECTIVES[rng.randi_range(0, _NAME_ADJECTIVES.size() - 1)]
	var noun := _NAME_NOUNS[rng.randi_range(0, _NAME_NOUNS.size() - 1)]
	return "%s %s" % [adj, noun]

## Returns the two deterministic homeworld cells in the origin chunk. Diagonal
## corners keep them non-adjacent for every supported chunk size (>= 2).
static func homeworld_cells(chunk_size: int) -> Array[Vector2i]:
	if chunk_size < 2:
		return []
	return [Vector2i.ZERO, Vector2i(chunk_size - 1, chunk_size - 1)]

## --- Cluster Generation (Makulatur System) ---

## Generates clusters of planets around suns with void spaces between.
## Each cluster has a central sun that scales with cluster size.
static func generate_clusters(
	config: WorldConfig,
	layout_seed: int,
	world_size: Vector2,
	planet_count: int
) -> Array[ClusterData]:
	var clusters: Array[ClusterData] = []
	if config == null or not config.is_cluster_generation_enabled():
		return clusters

	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed

	# Calculate target cluster count based on planet count and cluster sizes
	var target_clusters := config.resolved_cluster_count(planet_count)
	var target_cluster_area := world_size.x * world_size.y * (1.0 - config.void_ratio)
	var area_per_cluster := target_cluster_area / float(target_clusters)

	# Generate cluster centers using Poisson-Disk-like sampling
	var cluster_centers := _generate_cluster_centers(
		config, rng, world_size, target_clusters, area_per_cluster
	)

	# Assign planet counts to clusters (weighted random)
	var planets_per_cluster := _distribute_planets_to_clusters(
		config, rng, cluster_centers.size(), planet_count
	)

	# Create cluster data
	for i in cluster_centers.size():
		var cluster := ClusterData.new()
		cluster.cluster_id = StringName("cluster_%d" % i)
		cluster.center_position = cluster_centers[i]
		cluster.planet_count = planets_per_cluster[i]
		cluster.radius = _calculate_cluster_radius(config, rng, planets_per_cluster[i])

		# Generate sun
		cluster.sun = _generate_sun(config, rng, cluster)

		# Generate planet positions within cluster
		cluster.planet_slots = _generate_planet_positions(
			rng, cluster.center_position, cluster.radius, cluster.planet_count
		)

		# Distribute resources — pass cluster index as seed component for variety
		var resource_dist := ClusterData.ResourceDistribution.new()
		resource_dist.distribute(cluster.planet_count, config.resolved_resource_bias(), layout_seed + i)
		cluster.resource_bias = resource_dist.get_bias()

		clusters.append(cluster)

	return clusters

## Poisson-Disk-like sampling for cluster centers
static func _generate_cluster_centers(
	config: WorldConfig,
	rng: RandomNumberGenerator,
	world_size: Vector2,
	target_count: int,
	area_per_cluster: float
) -> Array[Vector2]:
	var centers: Array[Vector2] = []
	var min_distance := sqrt(area_per_cluster) * 0.5  # Minimum distance between clusters
	var max_attempts := target_count * 20
	var attempts := 0

	while centers.size() < target_count and attempts < max_attempts:
		var candidate := Vector2(
			rng.randf_range(config.padding, world_size.x - config.padding),
			rng.randf_range(config.padding, world_size.y - config.padding)
		)

		# Check distance to existing centers
		var valid := true
		for center in centers:
			if candidate.distance_to(center) < min_distance:
				valid = false
				break

		if valid:
			centers.append(candidate)

		attempts += 1

	# If we couldn't place enough, fill with grid-based fallback
	if centers.size() < target_count:
		var grid_cols := ceili(sqrt(float(target_count) * world_size.x / world_size.y))
		var grid_rows := ceili(float(target_count) / float(grid_cols))
		var cell_width := world_size.x / float(grid_cols)
		var cell_height := world_size.y / float(grid_rows)

		for row in grid_rows:
			for col in grid_cols:
				if centers.size() >= target_count:
					break
				var grid_center := Vector2(
					(float(col) + 0.5) * cell_width,
					(float(row) + 0.5) * cell_height
				)
				# Add jitter
				var jitter := Vector2(
					rng.randf_range(-cell_width * 0.2, cell_width * 0.2),
					rng.randf_range(-cell_height * 0.2, cell_height * 0.2)
				)
				centers.append(grid_center + jitter)

	return centers

## Distribute planets to clusters with weighted randomness
static func _distribute_planets_to_clusters(
	config: WorldConfig,
	rng: RandomNumberGenerator,
	cluster_count: int,
	total_planets: int
) -> Array[int]:
	var distribution: Array[int] = []
	var remaining := total_planets

	# First cluster gets player homeworld (minimum size)
	var first_cluster_size := mini(config.max_cluster_size, maxi(config.min_cluster_size, remaining))
	distribution.append(first_cluster_size)
	remaining -= first_cluster_size

	# Distribute remaining planets
	for i in range(1, cluster_count):
		if remaining <= 0:
			distribution.append(0)
			continue

		# Weighted random: smaller clusters more likely for variety
		var weight := rng.randf()
		var cluster_size: int
		if weight < 0.3:  # 30% chance: small cluster
			cluster_size = rng.randi_range(config.min_cluster_size, maxi(config.min_cluster_size, int(config.max_cluster_size * 0.5)))
		elif weight < 0.7:  # 40% chance: medium cluster
			cluster_size = rng.randi_range(int(config.max_cluster_size * 0.333), int(config.max_cluster_size * 0.666))
		else:  # 30% chance: large cluster
			cluster_size = rng.randi_range(int(config.max_cluster_size * 0.666), config.max_cluster_size)

		cluster_size = mini(cluster_size, remaining)
		distribution.append(cluster_size)
		remaining -= cluster_size

	# Distribute any remaining planets to random clusters (with safety guard)
	var safety := 0
	var max_safety := remaining * maxi(distribution.size(), 1) + 100
	while remaining > 0 and safety < max_safety:
		safety += 1
		var target := rng.randi_range(0, distribution.size() - 1)
		if distribution[target] < config.max_cluster_size:
			distribution[target] += 1
			remaining -= 1

	return distribution

## Calculate cluster radius based on planet count and config
static func _calculate_cluster_radius(
	config: WorldConfig,
	rng: RandomNumberGenerator,
	planet_count: int
) -> float:
	if planet_count <= 0:
		return 0.0

	# Base radius scales with sqrt of planet count
	var base_radius := sqrt(float(planet_count)) * 50.0

	# Add randomness within config bounds
	var min_radius := config.cluster_radius_min
	var max_radius := config.cluster_radius_max

	return rng.randf_range(
		maxf(min_radius, base_radius * 0.7),
		minf(max_radius, base_radius * 1.3)
	)

## Generate a sun for a cluster
static func _generate_sun(
	config: WorldConfig,
	rng: RandomNumberGenerator,
	cluster: ClusterData
) -> ClusterData.SunData:
	var sun := ClusterData.SunData.new()
	sun.cluster_id = cluster.cluster_id
	sun.position = cluster.center_position

	# Mass scales with sqrt of cluster size
	var mass := config.resolved_sun_mass(cluster.planet_count)
	sun.mass = mass * rng.randf_range(0.8, 1.2)  # Add slight variation

	# Glow radius scales with mass
	var glow := config.resolved_sun_glow(cluster.planet_count)
	sun.glow_radius = glow * rng.randf_range(0.9, 1.1)

	# Temperature variation (3000-30000 K)
	sun.temperature = rng.randf_range(3000.0, 30000.0)

	# Color from temperature
	sun.color = sun.get_visual_color()

	return sun

## Generate planet positions within a cluster (dense packing)
static func _generate_planet_positions(
	rng: RandomNumberGenerator,
	center: Vector2,
	radius: float,
	count: int
) -> Array[Vector2]:
	var positions: Array[Vector2] = []
	if count <= 0:
		return positions

	# First planet near center
	positions.append(center + Vector2(
		rng.randf_range(-radius * 0.1, radius * 0.1),
		rng.randf_range(-radius * 0.1, radius * 0.1)
	))

	# Remaining planets in rings
	for i in range(1, count):
		var ring := ceili(float(i) / 6.0)  # 6 planets per ring
		var angle_offset := rng.randf() * TAU
		var angle := angle_offset + (float(i % 6) / 6.0) * TAU
		var ring_radius := radius * (float(ring) / float(ceili(float(count) / 6.0)))

		var pos := center + Vector2(
			cos(angle) * ring_radius,
			sin(angle) * ring_radius
		)

		# Add jitter for organic feel
		pos += Vector2(
			rng.randf_range(-radius * 0.05, radius * 0.05),
			rng.randf_range(-radius * 0.05, radius * 0.05)
		)

		positions.append(pos)

	return positions

## Generates planet definitions for a single chunk deterministically. The
## origin chunk owns the two persistent homeworld identities; every other slot
## is a neutral procedural planet derived from the supplied template catalog.
static func generate_chunk_planets(
	base_catalog: PlanetCatalog,
	chunk_x: int, chunk_y: int,
	chunk_seed_value: int,
	chunk_size: int,
	config: WorldConfig,
	_max_size_class: StringName
) -> Array[PlanetDefinition]:
	var definitions: Array[PlanetDefinition] = []
	if base_catalog == null or base_catalog.planets.is_empty() or chunk_size <= 0 or config == null:
		return definitions
	var base_size := base_catalog.planets.size()
	var origin_chunk := chunk_x == 0 and chunk_y == 0
	var home_cells := homeworld_cells(chunk_size)
	for slot in chunk_size * chunk_size:
		var slot_s := slot_seed(chunk_seed_value, slot)
		var source: PlanetDefinition = base_catalog.planets[slot % base_size]
		if source == null:
			continue
		var definition: PlanetDefinition = source.duplicate(true) as PlanetDefinition
		var local_col := slot % chunk_size
		var local_row := int(slot / float(chunk_size))
		var is_homeworld := origin_chunk and home_cells.has(Vector2i(local_col, local_row))
		if is_homeworld:
			var home_index := home_cells.find(Vector2i(local_col, local_row))
			definition.planet_id = StringName("p%d" % home_index)
			definition.planet_role = &"homeworld"
			definition.faction = &"a" if home_index == 0 else &"b"
			definition.display_name = "Player Homeworld" if home_index == 0 else "CPU Homeworld"
			definition.generated_name = definition.display_name
		else:
			# Chunk-specific planet ID prevents cross-chunk collisions.
			definition.planet_id = StringName("c%d_%d_%s_%d" % [chunk_x, chunk_y, source.planet_id, slot])
			definition.display_name = generate_planet_name(slot_s)
			definition.planet_role = &"planet"
			definition.faction = &"neutral"
		definition.generated_name = definition.display_name
		var composition := compose_planet(
			slot_s,
			config.composition_base_textures,
			config.composition_tint_palettes,
			config.composition_decal_pool
		)
		definition.composition_base_texture = composition.get("base_texture", null) as Texture2D
		definition.composition_tint = composition.get("tint", Color.WHITE) as Color
		definition.composition_decal_textures = _texture_array(composition.get("decal_textures", []))
		definition.planet_texture = definition.composition_base_texture
		# Homeworlds also use generated composition, but use a separate stable
		# seed offset so their visuals do not duplicate the first neutral slot.
		if is_homeworld:
			var home_composition := compose_planet(slot_s + 7919, config.composition_base_textures, config.composition_tint_palettes, config.composition_decal_pool)
			definition.composition_base_texture = home_composition.get("base_texture", null) as Texture2D
			definition.composition_tint = home_composition.get("tint", Color.WHITE) as Color
			definition.composition_decal_textures = _texture_array(home_composition.get("decal_textures", []))
			definition.planet_texture = definition.composition_base_texture
		# The template carries the detail profile; the coordinator resolves the
		# size profile separately from the world config.
		definition.detail_profile = source.detail_profile if source.detail_profile != null else DEFAULT_DETAIL_PROFILE
		definitions.append(definition)
	return definitions
