extends Node
class_name McpInputScheduler

## Persistent input lane. It survives RefCounted tool instances, scene changes,
## pause state and unfocused windows.

signal action_completed(action_id: String, receipt: Dictionary)

const MAX_PENDING := 256
const VIRTUAL_EVENT_META := &"mcp_virtual_input"
const VIRTUAL_POSITION_META := &"mcp_virtual_position"

var _queue: Array[Dictionary] = []
var _sequence := 0
var _last_receipt: Dictionary = {}
var _virtual_mouse_active := false
var _physical_mouse_blocked := false
var _virtual_mouse_position := Vector2.ZERO
var _virtual_mouse_bounds := Vector2.ZERO
var _virtual_mouse_session := ""
var _last_mouse_action := ""
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _mouse_mode_overridden := false
var _blocked_physical_mouse_events := 0
var _cursor_layer: CanvasLayer
var _virtual_cursor: Control
var _cursor_visible := true
var _cursor_size := 32.0

# Deterministic frame-freeze: the game tree pauses after every delivered
# frame so an agent can read state before stepping again.
var _freeze_mode := false
var _step_pending := false
var _step_countdown := 0
var _frames_stepped := 0
var _was_paused_before_freeze := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	set_process_input(true)


static func get_or_create() -> McpInputScheduler:
	var main_loop := Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return null
	var root := (main_loop as SceneTree).root
	if root == null:
		return null
	var existing := root.get_node_or_null("McpInputScheduler") as McpInputScheduler
	if existing != null:
		return existing
	var scheduler := McpInputScheduler.new()
	scheduler.name = "McpInputScheduler"
	root.add_child(scheduler)
	return scheduler


func activate_virtual_mouse(session_id: String = "", initial_position: Vector2 = Vector2(-1.0, -1.0), block_physical_mouse: bool = true, show_cursor: bool = true) -> Dictionary:
	_virtual_mouse_active = true
	_physical_mouse_blocked = block_physical_mouse
	_virtual_mouse_session = session_id
	_create_virtual_cursor(show_cursor)
	_queue.clear()
	_last_receipt = {}
	_last_mouse_action = "activate"
	_blocked_physical_mouse_events = 0
	if block_physical_mouse and not _mouse_mode_overridden:
		_previous_mouse_mode = Input.get_mouse_mode()
		Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
		_mouse_mode_overridden = true
	var bounds := _viewport_size()
	_virtual_mouse_bounds = bounds
	if initial_position.x < 0.0 or initial_position.y < 0.0:
		_virtual_mouse_position = bounds * 0.5
	else:
		_virtual_mouse_position = _clamp_position(initial_position, bounds)
	_queue_cursor_redraw()
	return get_virtual_mouse_status()


func deactivate_virtual_mouse() -> Dictionary:
	_virtual_mouse_active = false
	_physical_mouse_blocked = false
	_virtual_mouse_session = ""
	# Also exit freeze mode so the game resumes normally.
	set_freeze(false)
	_queue.clear()
	_last_mouse_action = "deactivate"
	_destroy_virtual_cursor()
	if _mouse_mode_overridden:
		Input.set_mouse_mode(_previous_mouse_mode)
		_mouse_mode_overridden = false
	return get_virtual_mouse_status()


func move_virtual_mouse(position: Vector2) -> Dictionary:
	if not _virtual_mouse_active:
		return {"moved": false, "error": "virtual mouse is not active", "active": false}
	var bounds := _viewport_size()
	_virtual_mouse_bounds = bounds
	_virtual_mouse_position = _clamp_position(position, bounds)
	_last_mouse_action = "move"
	_reposition_cursor()
	_queue_cursor_redraw()
	return {"moved": true, "position": _vector_status(_virtual_mouse_position), "bounds": _vector_status(bounds)}


func is_physical_mouse_blocked() -> bool:
	return _virtual_mouse_active and _physical_mouse_blocked


func record_blocked_physical_mouse_event() -> void:
	_blocked_physical_mouse_events += 1


func get_virtual_mouse_status() -> Dictionary:
	var bounds := _viewport_size()
	if bounds.x > 0.0 and bounds.y > 0.0:
		_virtual_mouse_bounds = bounds
	return {
		"active": _virtual_mouse_active,
		"physical_mouse_blocked": _physical_mouse_blocked,
		"session": _virtual_mouse_session,
		"position": _vector_status(_virtual_mouse_position),
		"bounds": _vector_status(_virtual_mouse_bounds),
		"last_action": _last_mouse_action,
		"blocked_physical_events": _blocked_physical_mouse_events,
		"cursor_visible": _virtual_cursor != null and _virtual_cursor.visible,
	}


static func is_virtual_event(event: InputEvent) -> bool:
	return event != null and event.has_meta(VIRTUAL_EVENT_META) and bool(event.get_meta(VIRTUAL_EVENT_META, false))


func _input(event: InputEvent) -> void:
	if not _physical_mouse_blocked or is_virtual_event(event):
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		record_blocked_physical_mouse_event()
		get_viewport().set_input_as_handled()


func _viewport_size() -> Vector2:
	var main_loop := Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return Vector2.ZERO
	var root := (main_loop as SceneTree).root
	return root.get_visible_rect().size if root != null else Vector2.ZERO


func _clamp_position(position: Vector2, bounds: Vector2) -> Vector2:
	if bounds.x <= 0.0 or bounds.y <= 0.0:
		return Vector2.ZERO
	return Vector2(clampf(position.x, 0.0, bounds.x), clampf(position.y, 0.0, bounds.y))


func _vector_status(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


func _create_virtual_cursor(show_cursor: bool) -> void:
	_destroy_virtual_cursor()
	_cursor_visible = show_cursor
	if not show_cursor:
		return
	var main_loop := Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return
	var root := (main_loop as SceneTree).root
	if root == null:
		return
	_cursor_layer = CanvasLayer.new()
	_cursor_layer.name = "McpVirtualMouseLayer"
	_cursor_layer.layer = 200
	root.add_child(_cursor_layer)
	_virtual_cursor = Control.new()
	_virtual_cursor.name = "McpVirtualMouseCursor"
	_virtual_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Small positioned cursor — NOT full-rect, so it doesn't occlude the viewport or screenshots.
	_virtual_cursor.position = _virtual_mouse_position - Vector2(_cursor_size * 0.5, _cursor_size * 0.5)
	_virtual_cursor.size = Vector2(_cursor_size, _cursor_size)
	_virtual_cursor.draw.connect(_draw_virtual_cursor)
	_cursor_layer.add_child(_virtual_cursor)
	_queue_cursor_redraw()


func _destroy_virtual_cursor() -> void:
	_virtual_cursor = null
	if _cursor_layer != null:
		_cursor_layer.queue_free()
	_cursor_layer = null


func _queue_cursor_redraw() -> void:
	if _virtual_cursor != null and _cursor_visible:
		_virtual_cursor.visible = true
		_virtual_cursor.queue_redraw()

func _reposition_cursor() -> void:
	if _virtual_cursor != null:
		_virtual_cursor.position = _virtual_mouse_position - Vector2(_cursor_size * 0.5, _cursor_size * 0.5)

## Hide the cursor overlay temporarily (e.g. before screenshots).
func hide_cursor() -> void:
	if _virtual_cursor != null:
		_virtual_cursor.visible = false

## Show the cursor overlay after a temporary hide.
func show_cursor() -> void:
	if _virtual_cursor != null and _cursor_visible:
		_virtual_cursor.visible = true
		_queue_cursor_redraw()


func _draw_virtual_cursor() -> void:
	if _virtual_cursor == null or not _virtual_mouse_active:
		return
	var center := Vector2(_cursor_size * 0.5, _cursor_size * 0.5)
	_virtual_cursor.draw_circle(center, 9.0, Color(0.2, 0.95, 1.0, 0.18))
	_virtual_cursor.draw_arc(center, 9.0, 0.0, TAU, 24, Color(0.35, 0.95, 1.0, 0.95), 2.0, true)
	_virtual_cursor.draw_line(center - Vector2(14.0, 0.0), center + Vector2(14.0, 0.0), Color(0.9, 1.0, 1.0, 0.9), 1.0, true)
	_virtual_cursor.draw_line(center - Vector2(0.0, 14.0), center + Vector2(0.0, 14.0), Color(0.9, 1.0, 1.0, 0.9), 1.0, true)


func schedule_mouse_event(event: InputEvent, delay_frames: int, parse_mode: bool = false, virtual_position: Vector2 = Vector2(-1.0, -1.0)) -> Dictionary:
	if event == null:
		return {"scheduled": false, "error": "mouse event is null"}
	if virtual_position.x >= 0.0 and virtual_position.y >= 0.0:
		event.set_meta(VIRTUAL_POSITION_META, virtual_position)
	return _schedule(event, delay_frames, parse_mode)


func schedule_key_event(event: InputEventKey, delay_frames: int = 0) -> Dictionary:
	if event == null:
		return {"scheduled": false, "error": "key event is null"}
	if delay_frames <= 0:
		_deliver(event, true)
		return {"scheduled": true, "delivered": true, "delay_frames": 0}
	return _schedule(event, delay_frames, false)


func get_status() -> Dictionary:
	return {
		"pending": _queue.size(),
		"capacity": MAX_PENDING,
		"last_receipt": _last_receipt.duplicate(true),
		"virtual_mouse": get_virtual_mouse_status(),
		"freeze_mode": _freeze_mode,
		"step_pending": _step_pending,
		"frames_stepped": _frames_stepped,
		"tree_paused": _tree_paused(),
	}


func set_freeze(active: bool) -> Dictionary:
	var tree := get_tree()
	if tree == null:
		return {"ok": false, "error": "no scene tree"}
	if active and not _freeze_mode:
		_was_paused_before_freeze = tree.paused
		tree.paused = true
		_freeze_mode = true
		_step_pending = false
	elif not active and _freeze_mode:
		tree.paused = _was_paused_before_freeze
		_freeze_mode = false
		_step_pending = false
	return {"ok": true, "freeze_mode": _freeze_mode, "tree_paused": _tree_paused()}


func step_one_frame() -> Dictionary:
	if not _freeze_mode:
		return {"ok": false, "error": "freeze mode is not active — call runtime_freeze first"}
	var tree := get_tree()
	if tree == null:
		return {"ok": false, "error": "no scene tree"}
	tree.paused = false
	_step_pending = true
	_step_countdown = 1
	return {"ok": true, "frame": _frames_stepped, "tree_paused": false}


## Unpause the tree for `count` consecutive frames so tweens, scene
## transitions, and deferred calls can complete before re-freezing.
func step_frames(count: int) -> Dictionary:
	if not _freeze_mode:
		return {"ok": false, "error": "freeze mode is not active — call runtime_freeze first"}
	if count <= 0:
		return {"ok": false, "error": "count must be > 0"}
	var tree := get_tree()
	if tree == null:
		return {"ok": false, "error": "no scene tree"}
	tree.paused = false
	_step_pending = true
	_step_countdown = count
	return {"ok": true, "stepping": count, "tree_paused": false}


func get_freeze_status() -> Dictionary:
	return {
		"freeze_mode": _freeze_mode,
		"step_pending": _step_pending,
		"frames_stepped": _frames_stepped,
		"tree_paused": _tree_paused(),
		"pending_inputs": _queue.size(),
	}


func _tree_paused() -> bool:
	var tree := get_tree()
	return tree != null and tree.paused


func clear_pending() -> void:
	_queue.clear()


func _schedule(event: InputEvent, delay_frames: int, parse_mode: bool) -> Dictionary:
	if _queue.size() >= MAX_PENDING:
		return {"scheduled": false, "error": "input queue full", "pending": _queue.size()}
	_sequence += 1
	var action_id := "input_%d" % _sequence
	_queue.append({
		"action_id": action_id,
		"remaining": maxi(1, delay_frames),
		"event": event,
		"parse_mode": parse_mode,
	})
	return {
		"scheduled": true,
		"action_id": action_id,
		"delay_frames": maxi(1, delay_frames),
		"pending": _queue.size(),
	}


func _process(_delta: float) -> void:
	# Freeze mode: after step_one_frame() or step_frames() unpauses the tree,
	# this _process tick runs game logic (including tweens) for one frame.
	# If _step_countdown > 0, keep the tree unpaused; otherwise re-freeze.
	if _freeze_mode and _step_pending:
		_frames_stepped += 1
		_step_countdown -= 1
		# Deliver any queued inputs on every stepped frame.
		_deliver_ready_entries()
		if _step_countdown <= 0:
			_step_pending = false
			var tree := get_tree()
			if tree != null:
				tree.paused = true
		return
	if _queue.is_empty():
		return
	_deliver_ready_entries()


func _deliver_ready_entries() -> void:
	var ready: Array[Dictionary] = []
	for index in range(_queue.size() - 1, -1, -1):
		var entry: Dictionary = _queue[index]
		entry["remaining"] = int(entry.get("remaining", 1)) - 1
		if int(entry.get("remaining", 0)) <= 0:
			ready.append(entry)
			_queue.remove_at(index)
	ready.reverse()
	for entry in ready:
		_deliver(entry.get("event") as InputEvent, bool(entry.get("parse_mode", false)))
		var receipt := {
			"action_id": str(entry.get("action_id", "")),
			"delivered": true,
			"frame": Engine.get_process_frames(),
			"timestamp_ms": Time.get_ticks_msec(),
		}
		_last_receipt = receipt
		action_completed.emit(str(entry.get("action_id", "")), receipt)


func _deliver(event: InputEvent, parse_mode: bool) -> void:
	var main_loop := Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return
	if event != null:
		event.set_meta(VIRTUAL_EVENT_META, true)
		if event is InputEventMouse or event is InputEventMouseMotion or event is InputEventMouseButton:
			var virtual_position: Variant = event.get_meta(VIRTUAL_POSITION_META, null)
			if virtual_position is Vector2:
				move_virtual_mouse(virtual_position)
	var viewport := (main_loop as SceneTree).root
	if parse_mode:
		Input.parse_input_event(event)
	else:
		viewport.push_input(event)
