class_name MapCamera
extends Camera2D

signal planet_drag_dropped(source: Node2D, destination: Node2D)
## QS-5: LoD-Stufen-Signal — feuert bei Zoom-Level-Wechsel (0=Nah, 1=Mittel,
## 2=Weit/Sternenkarte). PlanetNetwork/FoW können darauf reagieren.
signal lod_level_changed(level: int)

const PLANET_CLICK_RADIUS := 120.0

@export_range(0.5, 1.0, 0.05) var min_zoom: float = 1.0
## QS-5: max_zoom erweitert (2.5 → 6.0) — ermöglicht Herauszoomen auf die
## Sternenkarte. @export_range erlaubte schon bis 6.0, nur der Default
## war zu klein.
@export_range(1.0, 6.0, 0.05) var max_zoom: float = 6.0
@export_range(0.05, 0.5, 0.05) var zoom_step: float = 0.15
@export_range(2.0, 32.0, 1.0) var drag_threshold: float = 6.0
@export_range(100.0, 800.0, 10.0) var keyboard_pan_speed: float = 400.0
@export_range(100.0, 800.0, 10.0) var edge_scroll_speed: float = 300.0
@export_range(4.0, 64.0, 1.0) var edge_scroll_margin: float = 16.0

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
var _home_tween: Tween
var _home_center_done := false
var _home_center_retries := 0
## QS-5: Aktueller LoD-Level (0=Nah <2.0, 1=Mittel 2.0–4.0, 2=Weit ≥4.0).
var _lod_level := 0

func _ready() -> void:
	var background: Node = get_parent()
	if background != null:
		_planet_field = background.get_node_or_null("PlanetField") as SeededLayout
	make_current()
	_read_world_bounds()
	position = _map_bounds.get_center()
	zoom = Vector2.ONE
	_sync_infinite_world()
	# On world start the camera should glide to the player's homeworld at a
	# zoom that frames the first few neighbours — not sit on empty space.
	if _planet_field != null and _planet_field.has_signal("layout_completed") and not _planet_field.layout_completed.is_connected(_try_home_center):
		_planet_field.layout_completed.connect(_try_home_center)
	var coordinator: ChunkCoordinator = _planet_field.get_chunk_coordinator() if _planet_field != null else null
	if coordinator != null and coordinator.has_signal("planet_added") and not coordinator.planet_added.is_connected(_try_home_center):
		coordinator.planet_added.connect(_try_home_center)
	_try_home_center()

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
	var edge_dir := _edge_scroll_vector()
	if edge_dir.length_squared() > 0.01:
		pan_dir += edge_dir
	if pan_dir.length_squared() > 0.01:
		pan_dir = pan_dir.normalized()
		position += pan_dir * keyboard_pan_speed * delta / zoom.x
		_clamp_position()
		_sync_infinite_world()

func _input_mouse_position() -> Vector2:
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		var root := (tree as SceneTree).root
		# 1) MCP server mode — check McpRuntime autoload.
		var mcp_runtime := root.get_node_or_null("McpRuntime")
		if mcp_runtime != null and mcp_runtime.has_method("get_virtual_mouse_status"):
			var status: Dictionary = mcp_runtime.call("get_virtual_mouse_status")
			if bool(status.get("active", false)):
				var raw_position: Dictionary = status.get("position", {})
				return Vector2(float(raw_position.get("x", 0.0)), float(raw_position.get("y", 0.0)))
		# 2) Standalone E2E driver mode — check McpInputScheduler directly.
		var scheduler := root.get_node_or_null("McpInputScheduler")
		if scheduler != null and scheduler.has_method("get_virtual_mouse_status"):
			var status: Dictionary = scheduler.call("get_virtual_mouse_status")
			if bool(status.get("active", false)):
				var raw_position: Dictionary = status.get("position", {})
				return Vector2(float(raw_position.get("x", 0.0)), float(raw_position.get("y", 0.0)))
	return get_viewport().get_mouse_position()

func _edge_scroll_vector() -> Vector2:
	# Godot 4 headless runs pin the mouse at (0,0) with no display server.
	if DisplayServer.get_name() == "headless":
		return Vector2.ZERO
	var mouse_pos := _input_mouse_position()
	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return Vector2.ZERO
	var margin := edge_scroll_margin
	var result := Vector2.ZERO
	if mouse_pos.x < margin:
		result.x = -(1.0 - mouse_pos.x / margin)
	elif mouse_pos.x > vp_size.x - margin:
		result.x = 1.0 - (vp_size.x - mouse_pos.x) / margin
	if mouse_pos.y < margin:
		result.y = -(1.0 - mouse_pos.y / margin)
	elif mouse_pos.y > vp_size.y - margin:
		result.y = 1.0 - (vp_size.y - mouse_pos.y) / margin
	return result * (edge_scroll_speed / keyboard_pan_speed)

func _unhandled_input(event: InputEvent) -> void:
	if _input_blocked:
		return
	if event.is_action_pressed(&"camera_home"):
		_center_on_homeworld()
		get_viewport().set_input_as_handled()
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
	_update_lod_level()
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
	var fov_radius: int = coordinator.player_fov_radius()
	var fov_margin := maxf(cell_size.x, cell_size.y) * float(fov_radius)
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

## Moves the camera instantly to the player's homeworld planet.
func _center_on_homeworld() -> void:
	var target := _homeworld_node()
	if target == null:
		return
	position = target.global_position
	_sync_infinite_world()

func _homeworld_node() -> Node2D:
	var state: Node = GameStateAccess.autoload(self)
	if state == null:
		return null
	var homeworld_id: StringName = state.homeworld_for(GameState.FACTION_PLAYER)
	if String(homeworld_id).is_empty():
		return null
	for planet in get_tree().get_nodes_in_group("planets"):
		var planet_node: Node2D = planet as Node2D
		if planet_node != null and planet_node.get("planet_id") == homeworld_id:
			return planet_node
	return null

## Glides the camera to the player's homeworld (1.5s ease) and picks a zoom
## where the homeworld plus its nearest neighbours are visible.
func center_on_homeworld_animated(duration: float = 1.5) -> void:
	var target := _homeworld_node()
	if target == null:
		return
	var target_zoom := _zoom_for_framing(target.global_position, 5)
	if _home_tween != null and _home_tween.is_valid():
		_home_tween.kill()
	_home_tween = create_tween().set_parallel(true)
	_home_tween.tween_property(self, "position", target.global_position, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_home_tween.tween_property(self, "zoom", Vector2(target_zoom, target_zoom), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_home_tween.chain().tween_callback(_sync_infinite_world)


## Computes a zoom factor that frames `center` plus its `count` nearest
## neighbours in the current viewport (clamped to min_zoom/max_zoom).
func _zoom_for_framing(center: Vector2, count: int = 5) -> float:
	var planets := get_tree().get_nodes_in_group("planets")
	var distances: Array[Dictionary] = []
	for planet in planets:
		var p: Node2D = planet as Node2D
		if p == null:
			continue
		distances.append({"d": p.global_position.distance_to(center), "p": p})
	distances.sort_custom(func(a, b): return float(a.get("d")) < float(b.get("d")))
	var max_distance: float = 0.0
	for index in mini(count, distances.size()):
		max_distance = maxf(max_distance, float(distances[index].get("d")))
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0 or max_distance <= 0.0:
		return max_zoom
	# Visible world span at zoom Z is viewport/Z; require 2*max_distance to fit.
	var target_zoom := minf(viewport_size.x, viewport_size.y) * 0.85 / (max_distance * 2.0)
	return clampf(target_zoom, min_zoom, max_zoom)

## Deferred entry point (may also be invoked by layout_completed/planet_added
## signals): waits (with a frame budget) until the homeworld planet node
## exists, then runs the smooth centering once per run. Headless runs
## (preflight/E2E) keep the map-center framing so fixtures stay deterministic.
func _try_home_center(_planet: Node = null) -> void:
	if _home_center_done:
		return
	if DisplayServer.get_name() == "headless":
		_home_center_done = true
		return
	if _homeworld_node() != null:
		_home_center_done = true
		center_on_homeworld_animated()
		return
	if _home_center_retries < 60:
		_home_center_retries += 1
		call_deferred("_try_home_center")


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

# ── QS-5: LoD-Stufen + zoom-adaptive Sicht ──────────────────────────────

## Liefert den aktuellen LoD-Level: 0 (Nah, Details), 1 (Mittel), 2 (Weit/Sternenkarte).
func lod_level() -> int:
	return _lod_level

## Liefert die Zoom-Schwelle für eine LoD-Stufe (für FoW/Renderer).
func lod_zoom_threshold(level: int) -> float:
	match level:
		0: return 2.0
		1: return 4.0
		_: return 6.0

## Aktualisiert _lod_level und emittiert bei Wechsel lod_level_changed.
func _update_lod_level() -> void:
	var new_level := 0
	if zoom.x >= 4.0:
		new_level = 2
	elif zoom.x >= 2.0:
		new_level = 1
	if new_level != _lod_level:
		_lod_level = new_level
		lod_level_changed.emit(new_level)
