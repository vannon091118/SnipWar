@tool
class_name WorldConfig
extends Resource

const ROUTE_MODE_ALL_PLANETS := "all_planets"
const ROUTE_MODE_NEIGHBORS_ONLY := "neighbors_only"

@export var design_size: Vector2
@export var layout_seed: int
@export var decorative_seed: int
# 0 = derive the column count from design_size aspect ratio and planet count.
@export_range(0, 256, 1) var columns: int
@export_range(0, 100000, 1) var target_planet_count: int = 0
## Multiplicative world-area growth. 1.0 keeps the authored size/planet count
## (sqrt-scaled design_size + linearly-scaled target_planet_count are applied to
## a runtime duplicate before the live tree reads them; the authored .tres is
## never mutated).
@export_range(1.0, 20.0, 0.05) var growth_factor: float = 1.0
## Fraction of `(planet_count - 1)` other planets that should be linked as
## K-nearest long-range edges on top of the slot grid (NavigationField enforces
## it).
@export_range(0.0, 0.5, 0.005) var graph_neighbor_ratio: float = 0.0
## Absolute cap on K-nearest edges, regardless of ratio. 0 means "no cap".
@export_range(0, 4096, 1) var max_extra_edges: int = 0
# Absolute size-class floors; used when the matching ratio below is zero.
@export_range(0, 20, 1) var extra_large_count: int
@export_range(0, 20, 1) var large_count: int
# Percentage size-class targets; when > 0 they override the absolute counts above.
@export_range(0.0, 1.0, 0.01) var extra_large_ratio: float = 0.0
@export_range(0.0, 1.0, 0.01) var large_ratio: float = 0.0
@export_range(0.0, 1.0, 0.01) var jitter: float
@export_range(0.0, 500.0, 1.0) var padding: float
@export_range(0.0, 500.0, 1.0) var meteor_edge_margin: float
@export var extra_large_profile_id: StringName
@export var large_profile_id: StringName
@export var default_profile_id: StringName
@export_enum("all_planets", "neighbors_only") var route_mode: String = ROUTE_MODE_ALL_PLANETS

## --- Density-field sectors (opt-in) ---
## 0 = disabled; planets stay on the plain grid, preserving the legacy seed
## contract. When > 0, SeededLayout/ChunkCoordinator classify planets against
## sector anchors and perturb spacing + render scale.
@export_range(0, 20, 1) var sector_count: int = 0
@export_range(50.0, 5000.0, 10.0) var sector_radius: float = 200.0
@export_range(0.0, 1.0, 0.05) var sector_noise_strength: float = 0.3
@export var sector_flavors: Array[SectorFlavor] = []
## Global render-scale multiplier applied to every planet so more fit on
## screen at once. 1.0 = authored scale (backward compatible).
@export_range(0.1, 2.0, 0.05) var planet_visual_scale: float = 1.0

## --- Infinite chunk-grid world ---
## When chunk_size > 0, the world expands procedurally as the player explores.
## When 0 (default), the world is finite and uses the legacy layout path.
@export_range(0, 50, 1) var chunk_size: int = 0
## Size of one chunk cell in world coordinates. Zero = derived from
## design_size / chunk_size so the start chunk (0,0) lines up with the
## authored layout.
@export var cell_size: Vector2 = Vector2.ZERO
## FoV radii in chunk cells for the three discovery sources.
@export_range(0, 10, 1) var ship_fov_radius: int = 1
@export_range(0, 10, 1) var planet_fov_radius: int = 2
@export_range(0, 10, 1) var orbital_watcher_fov_radius: int = 4
## Maximum chunks kept in the lightweight cache (LRU-evicted beyond this).
@export_range(10, 1000, 10) var max_cached_chunks: int = 200
## Building-block pool for procedural planet composition.
@export var composition_base_textures: Array[Texture2D] = []
@export var composition_tint_palettes: Array[Color] = []
@export var composition_decal_pool: Array[Texture2D] = []

func meteor_bounds() -> Rect2:
	return Rect2(Vector2.ZERO, design_size)

func is_infinite_world() -> bool:
	return chunk_size > 0

func resolved_cell_size() -> Vector2:
	if cell_size.x > 0.0 and cell_size.y > 0.0:
		return cell_size
	if chunk_size <= 0:
		return design_size
	return Vector2(design_size.x / float(chunk_size), design_size.y / float(chunk_size))

func resolved_columns(planet_count: int) -> int:
	if columns > 0:
		return columns
	if planet_count <= 0 or design_size.x <= 0.0 or design_size.y <= 0.0:
		return 1
	# Fit the grid to the world aspect ratio: columns/rows ~ width/height.
	var aspect := design_size.x / design_size.y
	return maxi(1, int(round(sqrt(float(planet_count) * aspect))))

func resolved_design_size(base_size: Vector2 = Vector2.ZERO) -> Vector2:
	if base_size == Vector2.ZERO:
		base_size = design_size
	if growth_factor <= 1.0001:
		return base_size
	var scale := sqrt(growth_factor)
	return Vector2(base_size.x * scale, base_size.y * scale)

## Linear growth target. base_count is what the active catalog holds when no
## expansion was requested (typically the original authored PlanetCatalog plane).
func resolved_target_planet_count(base_count: int) -> int:
	if base_count <= 0:
		return target_planet_count
	if growth_factor <= 1.0001:
		return target_planet_count if target_planet_count > 0 else base_count
	return maxi(1, int(round(float(base_count) * growth_factor)))

func resolved_graph_neighbor_ratio() -> float:
	return clampf(graph_neighbor_ratio, 0.0, 0.5)

func resolved_max_extra_edges() -> int:
	return max(0, max_extra_edges)

func resolved_size_class_counts(planet_count: int) -> Vector2i:
	var resolved_extra_large: int
	var resolved_large: int
	if extra_large_ratio > 0.0 or large_ratio > 0.0:
		resolved_extra_large = mini(planet_count, int(round(float(planet_count) * extra_large_ratio)))
		resolved_large = mini(maxi(0, planet_count - resolved_extra_large), int(round(float(planet_count) * large_ratio)))
	else:
		resolved_extra_large = mini(extra_large_count, planet_count)
		resolved_large = mini(large_count, maxi(0, planet_count - resolved_extra_large))
	return Vector2i(resolved_extra_large, resolved_large)

## 0 = sector system disabled (opt-in, keeps the legacy seed contract intact).
func resolved_sector_count() -> int:
	return sector_count if sector_count > 0 else 0

func resolved_sector_radius() -> float:
	var authored := design_size
	if authored.x <= 0.0 or authored.y <= 0.0:
		return sector_radius
	var design := resolved_design_size()
	var scale := sqrt((design.x * design.y) / (authored.x * authored.y))
	return sector_radius * scale

func resolved_planet_visual_scale() -> float:
	return maxf(planet_visual_scale, 0.001)

func validate_for_planet_count(planet_count: int) -> PackedStringArray:
	var errors := PackedStringArray()
	if design_size.x <= 0.0 or design_size.y <= 0.0:
		errors.append("world design_size must be positive")
	if columns < 0:
		errors.append("world columns cannot be negative")
	if planet_count < 1:
		errors.append("world must contain at least one planet")
	if chunk_size > 0 and chunk_size < 2:
		errors.append("infinite world chunk_size must be at least two")
	if target_planet_count < 0:
		errors.append("world target_planet_count cannot be negative")
	if extra_large_count < 0 or large_count < 0:
		errors.append("world size class counts cannot be negative")
	if extra_large_ratio < 0.0 or extra_large_ratio > 1.0 or large_ratio < 0.0 or large_ratio > 1.0:
		errors.append("world size class ratios must stay between zero and one")
	if growth_factor < 1.0:
		errors.append("world growth_factor must be at least 1.0")
	if graph_neighbor_ratio < 0.0 or graph_neighbor_ratio > 0.5:
		errors.append("world graph_neighbor_ratio must stay between 0 and 0.5")
	if max_extra_edges < 0:
		errors.append("world max_extra_edges cannot be negative")
	if extra_large_ratio + large_ratio > 1.0:
		errors.append("world size class ratios cannot exceed one")
	if extra_large_ratio == 0.0 and large_ratio == 0.0 and extra_large_count + large_count > planet_count:
		errors.append("world size class counts exceed the planet count")
	if jitter < 0.0 or jitter > 1.0:
		errors.append("world jitter must stay between zero and one")
	if sector_count < 0:
		errors.append("world sector_count cannot be negative")
	if sector_count > 0 and sector_count >= planet_count:
		errors.append("world sector_count must be less than the planet count")
	if planet_visual_scale <= 0.0:
		errors.append("world planet_visual_scale must be positive")
	if sector_count > 0:
		if sector_flavors.is_empty():
			errors.append("world sector_flavors must not be empty when sector_count is set")
		var seen_sector_ids: Dictionary = {}
		for flavor in sector_flavors:
			if flavor == null:
				errors.append("world sector_flavors contains a null flavor")
				continue
			for flavor_error in flavor.validate():
				errors.append("sector flavor %s: %s" % [flavor.id, flavor_error])
			if seen_sector_ids.has(flavor.id):
				errors.append("world sector flavor ids must be unique")
			seen_sector_ids[flavor.id] = true
	if padding < 0.0:
		errors.append("world padding cannot be negative")
	if padding * 2.0 >= design_size.x or padding * 2.0 >= design_size.y:
		errors.append("world padding leaves no usable layout area")
	if meteor_edge_margin < 0.0:
		errors.append("meteor edge margin cannot be negative")
	if route_mode != ROUTE_MODE_ALL_PLANETS and route_mode != ROUTE_MODE_NEIGHBORS_ONLY:
		errors.append("world route_mode is invalid")
	return errors

func validate_profiles(profiles: Array[PlanetSizeProfile]) -> PackedStringArray:
	var errors := PackedStringArray()
	var profile_ids: Dictionary = {}
	for profile in profiles:
		if profile == null:
			errors.append("world contains a null planet size profile")
			continue
		for profile_error in profile.validate():
			errors.append("planet size profile %s: %s" % [profile.id, profile_error])
		if profile_ids.has(profile.id):
			errors.append("world planet size profile ids must be unique")
		profile_ids[profile.id] = true
	for required_id in [extra_large_profile_id, large_profile_id, default_profile_id]:
		if not profile_ids.has(required_id):
			errors.append("world is missing planet size profile %s" % required_id)
	return errors
