class_name MapCamera
extends Camera2D

signal planet_drag_dropped(source: Node2D, destination: Node2D)

const PLANET_CLICK_RADIUS := 120.0

@export_range(0.5, 1.0, 0.05) var min_zoom: float = 1.0
@export_range(1.0, 6.0, 0.05) var max_zoom: float = 2.5
@export_range(0.05, 0.5, 0.05) var zoom_step: float = 0.15
@export_range(2.0, 32.0, 1.0) var drag_threshold: float = 6.0
@export_range(100.0, 800.0, 10.0) var keyboard_pan_speed: float = 400.0

var _map_bounds: Rect2 = Rect2(Vector2.ZERO, Vector2(960.0, 540.0))
var _planet_field: SeededLayout
var _drag_origin: Vector2 = Vector2.ZERO
var _camera_at_drag_start: Vector2 = Vector2.ZERO
var _panning: bool = false
var _drag_source_planet: Node2D
var _touches: Dictionary = {}
var _pinch_distance: float = 0.0
var _pinch_zoom_start: float = 1.0
var _input_blocked := false

func _ready() -> void:
	var background: Node = get_parent()
	if background != null:
		_planet_field = background.get_node_or_null("PlanetField") as SeededLayout
	make_current()
	_read_world_bounds()
	position = _map_bounds.get_center()
	zoom = Vector2.ONE
	_sync_infinite_world()

func _read_world_bounds() -> void:
	# In infinite world mode, query the field-owned ChunkCoordinator for active bounds.
	var coordinator: ChunkCoordinator = _planet_field.get_chunk_coordinator() if _planet_field != null else null
	if coordinator != null:
		var bounds: Rect2 = coordinator.get_active_bounds()
		if bounds.size.x > 0.0 and bounds.size.y > 0.0:
			_map_bounds = bounds
			return
	if _planet_field == null:
		return
	var config: WorldConfig = _planet_field.world_config
	if config != null and config.design_size.x > 0.0 and config.design_size.y > 0.0:
		_map_bounds = Rect2(Vector2.ZERO, config.design_size)

## Blocks pan/zoom/selection while a fullscreen modal (e.g. PaperDossier) is open.
func set_input_blocked(blocked: bool) -> void:
	_input_blocked = blocked

func _process(delta: float) -> void:
	if _input_blocked:
		return
	var pan_dir := Vector2.ZERO
	if Input.is_action_pressed(&"camera_pan_left"):
		pan_dir.x -= 1.0
	if Input.is_action_pressed(&"camera_pan_right"):
		pan_dir.x += 1.0
	if Input.is_action_pressed(&"camera_pan_up"):
		pan_dir.y -= 1.0
	if Input.is_action_pressed(&"camera_pan_down"):
		pan_dir.y += 1.0
	if pan_dir.length_squared() > 0.01:
		pan_dir = pan_dir.normalized()
		position += pan_dir * keyboard_pan_speed * delta / zoom.x
		_clamp_position()
		_sync_infinite_world()

func _unhandled_input(event: InputEvent) -> void:
	if _input_blocked:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				var planet: Node2D = _planet_at(event.position)
				if planet != null:
					_drag_source_planet = planet
					_panning = false
				else:
					_drag_source_planet = null
					_drag_origin = event.position
					_camera_at_drag_start = position
					_panning = false
			else:
				if _drag_source_planet != null:
					var destination: Node2D = _planet_at(event.position)
					if destination != null and destination != _drag_source_planet:
						planet_drag_dropped.emit(_drag_source_planet, destination)
					_drag_source_planet = null
				_panning = false
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom_by(zoom_step, get_global_mouse_position())
				get_viewport().set_input_as_handled()
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom_by(-zoom_step, get_global_mouse_position())
				get_viewport().set_input_as_handled()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _drag_source_planet != null:
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_apply_pan(event.position)

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_drag_origin = event.position
			_camera_at_drag_start = position
			_panning = false
		elif _touches.size() == 2:
			_pinch_distance = _current_pinch_distance()
			_pinch_zoom_start = zoom.x
			_panning = false
	else:
		_touches.erase(event.index)
		_panning = false

func _handle_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	if _touches.size() == 1:
		_apply_pan(event.position)
	elif _touches.size() >= 2:
		_apply_pinch()

func _apply_pan(pointer_position: Vector2) -> void:
	var delta := pointer_position - _drag_origin
	if not _panning and delta.length() < drag_threshold:
		return
	_panning = true
	position = _camera_at_drag_start - delta / zoom.x
	_clamp_position()
	_sync_infinite_world()

func _apply_pinch() -> void:
	var distance := _current_pinch_distance()
	if distance <= 0.0 or _pinch_distance <= 0.0:
		return
	var new_zoom := clampf(_pinch_zoom_start * (distance / _pinch_distance), min_zoom, max_zoom)
	_set_zoom_at(new_zoom, _screen_to_world(_current_pinch_midpoint()))

func _zoom_by(step: float, world_point: Vector2) -> void:
	_set_zoom_at(zoom.x + step, world_point)

func _set_zoom_at(new_zoom: float, world_point: Vector2) -> void:
	new_zoom = clampf(new_zoom, min_zoom, max_zoom)
	if is_equal_approx(new_zoom, zoom.x):
		return
	var world_offset := world_point - position
	position = world_point - world_offset * (zoom.x / new_zoom)
	zoom = Vector2(new_zoom, new_zoom)
	_clamp_position()
	_sync_infinite_world()

func _screen_to_world(screen_point: Vector2) -> Vector2:
	var viewport_center := get_viewport().get_visible_rect().size * 0.5
	return (screen_point - viewport_center) / zoom + position

func _clamp_position() -> void:
	var coordinator: ChunkCoordinator = _planet_field.get_chunk_coordinator() if _planet_field != null else null
	if coordinator != null and coordinator.is_infinite_world():
		return
	var half_view := get_viewport().get_visible_rect().size * 0.5 / zoom
	var min_pos := _map_bounds.position + half_view
	var max_pos := _map_bounds.end - half_view
	if max_pos.x < min_pos.x:
		position.x = _map_bounds.get_center().x
	else:
		position.x = clampf(position.x, min_pos.x, max_pos.x)
	if max_pos.y < min_pos.y:
		position.y = _map_bounds.get_center().y
	else:
		position.y = clampf(position.y, min_pos.y, max_pos.y)

func _sync_infinite_world() -> void:
	if _planet_field == null:
		return
	var coordinator: ChunkCoordinator = _planet_field.get_chunk_coordinator()
	if coordinator == null or not coordinator.is_infinite_world():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var top_left := _screen_to_world(Vector2.ZERO)
	var bottom_right := _screen_to_world(viewport_size)
	var visible_rect := Rect2(top_left, bottom_right - top_left).abs()
	var world_config: WorldConfig = _planet_field.world_config
	var cell_size := world_config.resolved_cell_size() if world_config != null else Vector2(1.0, 1.0)
	var fov_margin := maxf(cell_size.x, cell_size.y) * float(world_config.planet_fov_radius if world_config != null else 1)
	var active_region := visible_rect.grow(fov_margin)
	coordinator.ensure_chunks_active([active_region], &"xl")
	_read_world_bounds()
	var background: Node = get_parent()
	if background != null and background.has_method("set_visible_region"):
		background.call("set_visible_region", visible_rect)

## Public entry point for external callers (e.g. FleetOverview drag-drop) that
## need to resolve a screen-space mouse position to the nearest planet.
func planet_at_screen(screen_position: Vector2) -> Node2D:
	return _planet_at(screen_position)

func _planet_at(screen_position: Vector2) -> Node2D:
	var world_position: Vector2 = _screen_to_world(screen_position)
	var best: Node2D = null
	var best_distance := PLANET_CLICK_RADIUS
	for planet in get_tree().get_nodes_in_group("planets"):
		var planet_node: Node2D = planet as Node2D
		if planet_node == null:
			continue
		var distance: float = world_position.distance_to(planet_node.global_position)
		if distance <= best_distance:
			best = planet_node
			best_distance = distance
	return best

func _current_pinch_distance() -> float:
	var positions: Array = _touches.values()
	if positions.size() < 2:
		return 0.0
	return (positions[0] as Vector2).distance_to(positions[1] as Vector2)

func _current_pinch_midpoint() -> Vector2:
	var positions: Array = _touches.values()
	if positions.size() < 2:
		return Vector2.ZERO
	return ((positions[0] as Vector2) + (positions[1] as Vector2)) * 0.5
