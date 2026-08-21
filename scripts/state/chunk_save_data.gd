@tool
class_name ChunkSaveData
extends Resource

## Lightweight save data for the infinite procedural world. Stores only
## cached chunk coordinates and per-planet state (factions, resources,
## upgrades, FoV state) — never Node instances. Nodes are re-instantiated
## from the seed-deterministic chunk cache on load.

@export var layout_seed: int = 0
@export var cached_chunk_coords: Array[Vector2i] = []
## planet_id -> {faction, resource_id, upgrades, fog_state}
@export var planet_states: Dictionary = {}
