@tool
class_name ChunkGrid
extends RefCounted

## Spatial partition for deterministic world placements.
## Divides the world into fixed-size chunks and indexes placements by chunk.
## Supports efficient viewport queries and LOD distance lookups.

@export var chunk_size: Vector2 = Vector2(512.0, 512.0)

## Maps chunk_coord (Vector2i) → Array[Placement].
var _chunks: Dictionary = {}

## Total number of placements across all chunks.
var _total_count: int = 0

func clear() -> void:
	_chunks.clear()
	_total_count = 0

func total_count() -> int:
	return _total_count

func chunk_count() -> int:
	return _chunks.size()

## Insert a placement into the grid (computes chunk coord automatically).
func insert(placement: Placement) -> void:
	if placement == null:
		return
	placement.chunk_coord = Placement.compute_chunk_coord(placement.position, chunk_size)
	var coord: Vector2i = placement.chunk_coord
	if not _chunks.has(coord):
		_chunks[coord] = []
	_chunks[coord].append(placement)
	_total_count += 1

## Remove a placement by reference.
func remove(placement: Placement) -> void:
	var coord: Vector2i = placement.chunk_coord
	if _chunks.has(coord):
		var bucket: Array = _chunks[coord]
		var idx := bucket.find(placement)
		if idx >= 0:
			bucket.remove_at(idx)
			_total_count -= 1
		if bucket.is_empty():
			_chunks.erase(coord)

## Get all placements in a specific chunk.
func get_chunk(coord: Vector2i) -> Array:
	return _chunks.get(coord, []) as Array

## Get all chunk coordinates that exist.
func all_chunk_coords() -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for coord: Vector2i in _chunks.keys():
		coords.append(coord)
	return coords

## Query all placements whose chunks intersect a world-space rect (with margin).
func query_rect(rect: Rect2, margin: float = 0.0) -> Array:
	var expanded := rect.grow(margin)
	var min_chunk := Placement.compute_chunk_coord(expanded.position, chunk_size)
	var max_chunk := Placement.compute_chunk_coord(expanded.end, chunk_size)

	var results: Array = []
	for cx in range(min_chunk.x, max_chunk.x + 1):
		for cy in range(min_chunk.y, max_chunk.y + 1):
			var coord := Vector2i(cx, cy)
			if _chunks.has(coord):
				for placement: Placement in _chunks[coord]:
					if expanded.has_point(placement.position):
						results.append(placement)
	return results

## Query all placements within a radius of a center point.
func query_radius(center: Vector2, radius: float) -> Array:
	var rect := Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
	var candidates := query_rect(rect, 0.0)
	var results: Array = []
	var r_sq := radius * radius
	for p: Placement in candidates:
		if center.distance_squared_to(p.position) <= r_sq:
			results.append(p)
	return results

## Get all placements (flat array across all chunks).
func all_placements() -> Array:
	var results: Array = []
	for bucket: Array in _chunks.values():
		for p: Placement in bucket:
			results.append(p)
	return results

## Filter placements by type across all chunks.
func filter_by_type(placement_type: StringName) -> Array:
	var results: Array = []
	for bucket: Array in _chunks.values():
		for p: Placement in bucket:
			if p.placement_type == placement_type:
				results.append(p)
	return results

## Check if any existing placement of the given type is within exclusion_distance.
func has_nearby_type(pos: Vector2, placement_type: StringName, exclusion_distance: float) -> bool:
	var candidates := query_radius(pos, exclusion_distance)
	for p: Placement in candidates:
		if p.placement_type == placement_type:
			return true
	return false

## Check if any required nearby type exists within range.
func has_required_nearby(pos: Vector2, required_types: Array[StringName], range_sq: float) -> bool:
	if required_types.is_empty():
		return true
	var candidates := query_radius(pos, sqrt(range_sq))
	for p: Placement in candidates:
		if required_types.has(p.placement_type):
			return true
	return false

## Check if any forbidden nearby type exists within range.
func has_forbidden_nearby(pos: Vector2, forbidden_types: Array[StringName], range_sq: float) -> bool:
	if forbidden_types.is_empty():
		return false
	var candidates := query_radius(pos, sqrt(range_sq))
	for p: Placement in candidates:
		if forbidden_types.has(p.placement_type):
			return true
	return false
