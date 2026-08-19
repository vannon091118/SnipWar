@tool
class_name LodManager
extends Node2D

## Manages chunk-based loading and LOD for world placements.
## Attached to the camera or the world root; queries the ChunkGrid each frame
## to determine which placements should be loaded/unloaded/upgraded/downgraded.
##
## Usage:
##   1. Set `chunk_grid` and `lod_config` after generation.
##   2. Call `set_camera_node(camera)` to track position.
##   3. Each frame, updates LOD levels and creates/destroys visual nodes.

## The chunk grid to query (set after pipeline execution).
var chunk_grid: ChunkGrid

## LOD distance thresholds.
var lod_config: LodLevel

## The node under which visual representations are added.
var world_root: Node2D

## Camera reference for distance calculations.
var _camera: Camera2D

## Previously loaded chunks (Vector2i → true).
var _loaded_chunks: Dictionary = {}

## All active placements keyed by placement_id.
var _active_placements: Dictionary = {}

## Viewport margin in pixels (how far beyond the screen to load chunks).
@export var viewport_margin: float = 128.0

## How often to re-evaluate LOD (in seconds). 0 = every frame.
@export var update_interval: float = 0.1

var _update_timer: float = 0.0

## Signal emitted when a placement's LOD level changes.
signal lod_changed(placement: Placement, old_level: LodLevel.Level, new_level: LodLevel.Level)

## Signal emitted when a chunk is loaded.
signal chunk_loaded(coord: Vector2i, placements: Array)

## Signal emitted when a chunk is unloaded.
signal chunk_unloaded(coord: Vector2i)

func _ready() -> void:
	set_process(true)

func set_camera_node(camera: Camera2D) -> void:
	_camera = camera

func configure(grid: ChunkGrid, lod: LodLevel, root: Node2D) -> void:
	chunk_grid = grid
	lod_config = lod
	world_root = root

func _process(delta: float) -> void:
	_update_timer += delta
	if _update_timer < update_interval:
		return
	_update_timer = 0.0
	_evaluate()

func _evaluate() -> void:
	if chunk_grid == null or _camera == null or world_root == null:
		return

	var viewport_rect := _get_viewport_rect()
	var expanded := viewport_rect.grow(viewport_margin)
	var visible_chunks := _chunks_in_rect(expanded)

	# Unload chunks that are no longer visible.
	var to_unload: Array[Vector2i] = []
	for coord: Vector2i in _loaded_chunks.keys():
		if not visible_chunks.has(coord):
			to_unload.append(coord)
	for coord in to_unload:
		_unload_chunk(coord)

	# Load new chunks.
	for coord: Vector2i in visible_chunks:
		if not _loaded_chunks.has(coord):
			_load_chunk(coord)

	# Re-evaluate LOD for all active placements.
	var center := viewport_rect.position + viewport_rect.size * 0.5
	for placement_id: StringName in _active_placements.keys():
		var placement: Placement = _active_placements[placement_id]
		var distance: float = placement.distance_to(center)
		var new_level: LodLevel.Level = _resolve_lod(distance)
		_apply_lod(placement, new_level)


func _load_chunk(coord: Vector2i) -> void:
	_loaded_chunks[coord] = true
	var placements: Array = chunk_grid.get_chunk(coord)
	for p: Placement in placements:
		_active_placements[p.placement_id] = p
		# Node creation is delegated to subclass or factory —
		# base implementation just marks as loaded.
		p.is_loaded = true
	chunk_loaded.emit(coord, placements)


func _unload_chunk(coord: Vector2i) -> void:
	_loaded_chunks.erase(coord)
	var placements: Array = chunk_grid.get_chunk(coord)
	for p: Placement in placements:
		_active_placements.erase(p.placement_id)
		_free_node(p)
		p.is_loaded = false
		p.node = null
	chunk_unloaded.emit(coord)


func _apply_lod(placement: Placement, new_level: LodLevel.Level) -> void:
	# LOD changes are handled by subclasses/factories.
	# Base implementation emits the signal for observers.
	lod_changed.emit(placement, LodLevel.Level.FULL, new_level)


func _free_node(placement: Placement) -> void:
	if placement.node != null and is_instance_valid(placement.node):
		placement.node.queue_free()
	placement.node = null


func _resolve_lod(distance: float) -> LodLevel.Level:
	if lod_config != null:
		return lod_config.resolve_level(distance)
	# Default thresholds if no config.
	if distance < 200.0:
		return LodLevel.Level.FULL
	if distance < 500.0:
		return LodLevel.Level.REDUCED
	if distance < 1000.0:
		return LodLevel.Level.MINIMAL
	return LodLevel.Level.CULLED


func _get_viewport_rect() -> Rect2:
	if _camera != null:
		var viewport_size := get_viewport_rect().size
		var zoom := _camera.zoom
		var camera_pos := _camera.global_position
		var half_size := viewport_size / (zoom * 2.0)
		return Rect2(camera_pos - half_size, viewport_size / zoom)
	return get_viewport_rect()


func _chunks_in_rect(rect: Rect2) -> Dictionary:
	var result: Dictionary = {}
	if chunk_grid == null:
		return result
	var min_chunk := Placement.compute_chunk_coord(rect.position, chunk_grid.chunk_size)
	var max_chunk := Placement.compute_chunk_coord(rect.end, chunk_grid.chunk_size)
	for cx in range(min_chunk.x, max_chunk.x + 1):
		for cy in range(min_chunk.y, max_chunk.y + 1):
			result[Vector2i(cx, cy)] = true
	return result


## Get all currently loaded placements.
func loaded_placements() -> Array:
	return _active_placements.values()


## Get loaded placements of a specific type.
func loaded_placements_of_type(placement_type: StringName) -> Array:
	var results: Array = []
	for p: Placement in _active_placements.values():
		if p.placement_type == placement_type:
			results.append(p)
	return results


## Force a full re-evaluation (e.g. after camera teleport).
func force_update() -> void:
	_update_timer = update_interval
	_evaluate()
