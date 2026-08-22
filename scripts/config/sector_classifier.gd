class_name SectorClassifier
extends RefCounted

## Single source of truth for sector membership, role classification, position
## perturbation, render-scale modulation and edge typing. Pure RefCounted with
## static methods so SeededLayout, ChunkCoordinator and NavigationField can all
## consume it without node coupling. Fully seed-deterministic.

const ROLE_CORE := &"core"
const ROLE_MID := &"mid"
const ROLE_EDGE := &"edge"
const ROLE_VOID := &"void"

const EDGE_INTRA := &"intra_sector"
const EDGE_INTER := &"inter_sector"
const EDGE_VOID := &"void_edge"

## Generates a deterministic set of sector anchors via Poisson-disk sampling.
## sector_count <= 0 returns an empty array (sector system disabled). When
## base_radius <= 0 it is derived from world size + sector count.
static func generate_anchors(seed_value: int, sector_count: int, world_size: Vector2, flavors: Array[SectorFlavor], base_radius: float = -1.0) -> Array[SectorAnchor]:
	var anchors: Array[SectorAnchor] = []
	if sector_count <= 0 or world_size.x <= 0.0 or world_size.y <= 0.0:
		return anchors
	var effective_flavors: Array[SectorFlavor] = []
	for flavor in flavors:
		if flavor != null:
			effective_flavors.append(flavor)
	if effective_flavors.is_empty():
		return anchors

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Base radius scales with world area and the number of requested sectors.
	var radius: float = base_radius if base_radius > 0.0 else 0.5 * sqrt(world_size.x * world_size.y) / maxf(1.0, sqrt(float(sector_count)))
	var min_separation := radius * 1.5
	var positions := _poisson_disk_sample(seed_value, world_size, min_separation)
	var count := mini(sector_count, positions.size())
	for index in range(count):
		var anchor := SectorAnchor.new()
		anchor.position = positions[index]
		anchor.flavor = effective_flavors[index % effective_flavors.size()]
		anchor.seed_offset = rng.randi()
		anchor.radius = radius * rng.randf_range(0.7, 1.3)
		anchors.append(anchor)
	return anchors

## Classifies a world position against the anchors. Returns
## {sector_index, sector_id, role, depth, radius, flavor}. depth 0.0 = center,
## > 1.0 = outside every anchor (void / inter-sector space).
static func classify_position(pos: Vector2, anchors: Array[SectorAnchor], noise: FastNoiseLite = null) -> Dictionary:
	var result := {
		"sector_index": -1,
		"sector_id": &"",
		"role": ROLE_VOID,
		"depth": 1.0,
		"radius": 0.0,
		"flavor": null,
	}
	var best_index := -1
	var best_score := -INF
	for index in range(anchors.size()):
		var anchor: SectorAnchor = anchors[index]
		if anchor == null:
			continue
		var dist := pos.distance_to(anchor.position)
		var score := _sector_falloff(dist, anchor.radius)
		if score > best_score:
			best_score = score
			best_index = index
	if best_index < 0:
		return result

	var anchor: SectorAnchor = anchors[best_index]
	var radius := maxf(anchor.radius, 0.001)
	var noisy_radius := radius
	if noise != null and anchor.flavor != null:
		noisy_radius = radius * (1.0 + noise.get_noise_2d(pos.x, pos.y) * anchor.flavor.noise_amplitude)
	var depth := pos.distance_to(anchor.position) / maxf(noisy_radius, 0.001)
	result["sector_index"] = best_index
	result["sector_id"] = anchor.flavor.id if anchor.flavor != null else &""
	result["flavor"] = anchor.flavor
	result["radius"] = radius
	result["depth"] = depth
	if depth <= 0.45:
		result["role"] = ROLE_CORE
	elif depth <= 0.85:
		result["role"] = ROLE_MID
	elif depth <= 1.0:
		result["role"] = ROLE_EDGE
	else:
		result["role"] = ROLE_VOID
	return result

## Perturbs a planet position based on its sector role. Core planets stay
## tightly packed, edge planets drift outward, void planets stay put. Uses a
## caller-supplied RNG so the main layout RNG stream is never disturbed.
static func adjust_position(pos: Vector2, classification: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	var role: StringName = classification.get("role", ROLE_VOID)
	var radius: float = float(classification.get("radius", 100.0))
	var amplitude: float
	match role:
		ROLE_CORE:
			amplitude = radius * 0.06
		ROLE_MID:
			amplitude = radius * 0.14
		ROLE_EDGE:
			amplitude = radius * 0.25
		_:
			return pos
	var angle := rng.randf_range(0.0, TAU)
	var distance := rng.randf_range(0.0, amplitude)
	return pos + Vector2(cos(angle), sin(angle)) * distance

## Render-scale multiplier derived from sector role. Purely visual: it never
## changes the gameplay size_profile (spawn interval, workers, build slots).
static func scale_multiplier(classification: Dictionary) -> float:
	var role: StringName = classification.get("role", ROLE_VOID)
	var depth: float = float(classification.get("depth", 1.0))
	match role:
		ROLE_CORE:
			return 1.5 - depth * 0.3
		ROLE_MID:
			return 1.1
		ROLE_EDGE:
			return 0.8
		_:
			return 0.5

## Classifies an edge between two sector ids. Empty / &"void" ids count as
## inter-sector void; equal non-void ids are intra-sector; otherwise inter.
static func edge_type(sector_a: StringName, sector_b: StringName) -> StringName:
	if _is_void_sector(sector_a) or _is_void_sector(sector_b):
		return EDGE_VOID
	if sector_a == sector_b:
		return EDGE_INTRA
	return EDGE_INTER

## Deterministic boundary noise shared by both layout paths.
static func create_noise(seed_value: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.01
	return noise

static func _is_void_sector(sector_id: StringName) -> bool:
	return String(sector_id).is_empty() or sector_id == &"void"

static func _sector_falloff(dist: float, radius: float) -> float:
	var normalized := dist / maxf(radius, 0.001)
	return maxf(0.0, 1.0 - normalized * normalized)

static func _poisson_disk_sample(seed_value: int, world_size: Vector2, min_distance: float, max_attempts: int = 30) -> Array[Vector2]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var points: Array[Vector2] = []
	if min_distance <= 0.0 or world_size.x <= 0.0 or world_size.y <= 0.0:
		return points
	points.append(Vector2(rng.randf_range(0.0, world_size.x), rng.randf_range(0.0, world_size.y)))
	var active: Array[int] = [0]
	while not active.is_empty():
		var active_pos: int = rng.randi_range(0, active.size() - 1)
		var center_index: int = active[active_pos]
		var center: Vector2 = points[center_index]
		var placed := false
		for _attempt in range(max_attempts):
			var angle := rng.randf_range(0.0, TAU)
			var radius := rng.randf_range(min_distance, min_distance * 2.0)
			var candidate := center + Vector2(cos(angle), sin(angle)) * radius
			if candidate.x < 0.0 or candidate.x > world_size.x or candidate.y < 0.0 or candidate.y > world_size.y:
				continue
			if _has_nearby_point(candidate, points, min_distance):
				continue
			points.append(candidate)
			active.append(points.size() - 1)
			placed = true
			break
		if not placed:
			active.remove_at(active_pos)
	return points

static func _has_nearby_point(candidate: Vector2, points: Array[Vector2], min_distance: float) -> bool:
	for point in points:
		if candidate.distance_squared_to(point) < min_distance * min_distance:
			return true
	return false
