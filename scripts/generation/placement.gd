@tool
class_name Placement
extends RefCounted

## A single deterministic placement in the world.
## Produced by GenerationPass implementations and stored in ChunkGrid.
## Contains everything the rendering/loading layer needs without coupling to nodes.

## Unique id for this placement (deterministic, e.g. "planet_ocean_0").
@export var placement_id: StringName = &""

## World-space position (local to PlanetField origin).
@export var position: Vector2 = Vector2.ZERO

## Chunk coordinate this placement belongs to.
@export var chunk_coord: Vector2i = Vector2i.ZERO

## Semantic type: "planet", "decoration", "meteor", "nebula", "station", etc.
@export var placement_type: StringName = &""

## Asset identifier for the primary representation.
@export var asset_id: StringName = &""

## Bounding radius in pixels — used for culling and distance checks.
@export var radius: float = 0.0

## Render priority (lower = drawn first, higher = drawn on top).
@export var priority: int = 0

## LOD-specific asset variants: maps LodLevel.Level → Texture2D (or null = skip).
var lod_textures: Dictionary = {}

## LOD-specific scale factors: maps LodLevel.Level → float multiplier.
var lod_scales: Dictionary = {}

## Type-specific metadata (faction, size_class, detail_profile_id, etc.).
var metadata: Dictionary = {}

## True after the node representation has been instantiated for a chunk.
var is_loaded: bool = false

## The live node handle (set by LodManager when loaded, cleared when unloaded).
var node: Node = null

## Compute the chunk coordinate for a world position given a chunk size.
static func compute_chunk_coord(pos: Vector2, chunk_size: Vector2) -> Vector2i:
	return Vector2i(
		floori(pos.x / chunk_size.x),
		floori(pos.y / chunk_size.y)
	)

## Distance from a viewpoint to this placement's center.
func distance_to(point: Vector2) -> float:
	return position.distance_to(point)
