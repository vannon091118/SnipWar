extends RefCounted
class_name McpRuntimeTools

## McpRuntimeTools — Runtime tool implementations (scene tree, node lookup,
## input simulation, expression eval, inspector).
##
## Input simulation is frame-accurate: a hover motion event is injected one
## frame before the press, the release is deferred by `hold_frames` so the
## engine's GUI pipeline sees a real press → release gesture (Button emits
## `pressed` on the release inside). Events are dispatched in-engine
## (Viewport.push_input or Input.parse_input_event — no OS calls, no focus
## requirement, works while the game window is unfocused).

const TOOL_PREFIX := "runtime_"
const INPUT_SCHEDULER_PATH := "res://addons/gdscript_mcp/runtime/tools/runtime/mcp_input_scheduler.gd"


# ═══════════════════════════════════════════════════════════════════════════
# Tool Definitions
# ═══════════════════════════════════════════════════════════════════════════

static func get_tool_defs() -> Array:
	return _basic_tools() + _inspector_tools()


static func _basic_tools() -> Array:
	return [
		_make("runtime_get_scene_tree", "Get a bounded, scoped slice of the running game scene tree",
			{"max_depth": {"type": "integer", "default": 4}, "root_path": {"type": "string", "default": "/root"}, "max_nodes": {"type": "integer", "default": 200}}),
		_make("runtime_find_node", "Find node in running game by path",
			{"path": {"type": "string"}}, ["path"]),
		_make("runtime_click", "Click a UI element or screen position in running game (engine-level mouse press+release). The virtual cursor travels smoothly to the target like a real mouse; press happens after the approach",
			{"path": {"type": "string", "description": "Node path or empty for screen coords"},
			 "x": {"type": "integer", "description": "Screen X (viewport coords), or -1 to resolve from path"},
			 "y": {"type": "integer", "description": "Screen Y (viewport coords), or -1 to resolve from path"},
			 "hold_frames": {"type": "integer", "default": 1, "description": "Frames between press and release events"},
			 "smooth": {"type": "boolean", "default": true, "description": "Smooth cursor approach (player-like); false = jump straight to target"},
			 "inject_mode": {"type": "string", "default": "auto", "description": "auto|push|parse (see index)"}}),
		_make("runtime_key", "Send key event to running game",
			{"keycode": {"type": "integer"}, "pressed": {"type": "boolean", "default": true}},
			["keycode"]),
		_make("runtime_key_gesture", "Send one complete visible key gesture (press, then release) to the running game",
			{"keycode": {"type": "integer"}, "hold_frames": {"type": "integer", "default": 1, "description": "Frames between press and release"}},
			["keycode"]),
		_make("runtime_mouse_move", "Move the MCP virtual mouse pointer to a position (hover). Default: smooth visible cursor travel over several frames — the cursor never teleports",
			{"x": {"type": "integer"}, "y": {"type": "integer"},
			 "smooth": {"type": "boolean", "default": true, "description": "Interpolated cursor travel; false = single jump event"},
			 "duration_ms": {"type": "integer", "default": 120, "description": "Approximate travel duration for smooth mode"}}, ["x", "y"]),
		_make("runtime_scroll", "Perform one visible virtual mouse-wheel scroll gesture over a control or position",
			{"path": {"type": "string", "default": ""}, "x": {"type": "integer", "default": -1}, "y": {"type": "integer", "default": -1}, "direction": {"type": "string", "enum": ["up", "down"], "default": "down"}, "steps": {"type": "integer", "default": 1}}, []),
		_make("runtime_virtual_mouse_status", "Read MCP virtual mouse position, bounds and physical mouse isolation state"),
		_make("runtime_drag", "Press, move over N steps, release (drag gesture)",
			{"x": {"type": "integer"}, "y": {"type": "integer"}, "dx": {"type": "integer", "default": 0},
			 "dy": {"type": "integer", "default": 0}, "steps": {"type": "integer", "default": 8},
			 "hold_frames": {"type": "integer", "default": 2}}, ["x", "y"]),
		_make("runtime_get_ui_state", "Get UI state from running game",
			{"path": {"type": "string"}}, ["path"]),
		_make("runtime_wait_frames", "Wait for N frames in running game",
			{"frames": {"type": "integer", "default": 1}}, [], true),
		_make("runtime_wait_ms", "Wait for N milliseconds (pauses do not extend the wait)",
			{"ms": {"type": "integer", "default": 250}}, ["ms"], true),
		_make("runtime_eval", "Evaluate GDScript expression in running game",
			{"code": {"type": "string"}}, ["code"]),
		_make("runtime_freeze", "Pause the game tree — no frames advance until step_frame or unfreeze"),
		_make("runtime_unfreeze", "Resume normal game execution after freeze"),
		_make("runtime_step_frame", "Advance exactly one frame in freeze mode, then re-freeze"),
		_make("runtime_step_frames", "Advance N consecutive frames in freeze mode (for tweens/transitions), then re-freeze",
			{"count": {"type": "integer", "default": 30}}, ["count"]),
		_make("runtime_freeze_status", "Read freeze mode state, frames stepped, pending inputs"),
		_make("runtime_camera_move_to", "Move MapCamera to x,y via tween (optional zoom, duration)",
			{"x": {"type": "number"}, "y": {"type": "number"},
			 "zoom": {"type": "number", "default": -1.0, "description": "Target zoom (skip if -1)"},
			 "duration": {"type": "number", "default": 0.5, "description": "Tween duration in seconds (0=instant)"}}, ["x", "y"], true),
	]


static func _inspector_tools() -> Array:
	return [
		_make("runtime_inspect_node", "Deep-inspect a node: properties, signals, children summary",
			{"path": {"type": "string"}}, ["path"]),
		_make("runtime_find_nodes_by_type", "Find all nodes of a given class in the running scene",
			{"type_name": {"type": "string"}, "max_results": {"type": "integer", "default": 100}},
			["type_name"]),
		_make("runtime_node_ancestry", "Get the full parent chain from a node to root",
			{"path": {"type": "string"}}, ["path"]),
	]


# ═══════════════════════════════════════════════════════════════════════════
# Dispatch
# ═══════════════════════════════════════════════════════════════════════════

## Synchronous dispatch. Returns Variant (Dictionary or error).
func dispatch_tool(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"runtime_get_scene_tree":
			return _rt_get_scene_tree(int(args.get("max_depth", 4)), str(args.get("root_path", "/root")), int(args.get("max_nodes", 200)))
		"runtime_find_node":
			return _rt_find_node(args.get("path", ""))
		"runtime_click":
			return _rt_click(args)
		"runtime_key":
			return _rt_key(_resolve_keycode(args.get("keycode", 0)), bool(args.get("pressed", true)))
		"runtime_key_gesture":
			return _rt_key_gesture(_resolve_keycode(args.get("keycode", 0)), int(args.get("hold_frames", 1)))
		"runtime_mouse_move":
			return _rt_mouse_move(int(args.get("x", 0)), int(args.get("y", 0)),
				bool(args.get("smooth", true)), int(args.get("duration_ms", 120)))
		"runtime_scroll":
			return _rt_scroll(args)
		"runtime_virtual_mouse_status":
			return _virtual_mouse_status()
		"runtime_drag":
			return _rt_drag(args)
		"runtime_get_ui_state":
			return _rt_get_ui_state(args.get("path", ""))
		"runtime_eval":
			return _rt_eval(args.get("code", "")) if _is_developer_mode() else {"error": "eval requires developer mode (--mcp-developer)"}
		"runtime_inspect_node":
			return _inspect_node(args.get("path", ""))
		"runtime_find_nodes_by_type":
			return _find_nodes_by_type(str(args.get("type_name", "")), int(args.get("max_results", 100)))
		"runtime_node_ancestry":
			return _node_ancestry(args.get("path", ""))
		"runtime_freeze":
			return _rt_freeze()
		"runtime_unfreeze":
			return _rt_unfreeze()
		"runtime_step_frame":
			return _rt_step_frame()
		"runtime_step_frames":
			return _rt_step_frames(int(args.get("count", 30)))
		"runtime_freeze_status":
			return _rt_freeze_status()
		_:
			return {"error": "Unknown runtime tool: " + tool_name}


## Async dispatch (for tools with await).
func dispatch_async(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"runtime_wait_frames":
			return await _rt_wait_frames(args.get("frames", 1))
		"runtime_wait_ms":
			return await _rt_wait_ms(int(args.get("ms", 300)))
		"runtime_camera_move_to":
			# Coroutine (await tween.finished) — must run on the async path.
			return await _rt_camera_move_to(args)
		_:
			return {"error": "Unknown async runtime tool: " + tool_name}


# ═══════════════════════════════════════════════════════════════════════════
# Scene Tree
# ═══════════════════════════════════════════════════════════════════════════

static func _rt_get_scene_tree(max_depth: int, root_path: String = "/root", max_nodes: int = 200) -> Dictionary:
	var safe_depth := clampi(max_depth, 0, 16)
	var safe_max_nodes := clampi(max_nodes, 1, 1000)
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"error": "No scene tree"}
	var root := (tree as SceneTree).root
	if not root:
		return {"error": "No root node"}
	var scoped_root: Node = root if root_path in ["", ".", "/root"] else root.get_node_or_null(NodePath(root_path))
	if scoped_root == null:
		return {"error": "Scene tree root path not found: " + root_path}
	var result: Array = []
	var budget := {"count": 0}
	_collect_nodes(scoped_root, result, 0, safe_depth, safe_max_nodes, budget)
	return {
		"root_path": String(scoped_root.get_path()),
		"tree": result,
		"count": int(budget.get("count", 0)),
		"truncated": int(budget.get("count", 0)) >= safe_max_nodes,
		"max_depth": safe_depth,
		"max_nodes": safe_max_nodes,
	}


static func _collect_nodes(node: Node, result: Array, depth: int, max_depth: int, max_nodes: int, budget: Dictionary) -> void:
	if depth > max_depth or int(budget.get("count", 0)) >= max_nodes:
		return
	var children = []
	var info = {
		"name": String(node.name),
		"type": node.get_class(),
		"path": node.get_path(),
		"child_count": node.get_child_count(),
		"children": children,
	}
	result.append(info)
	budget["count"] = int(budget.get("count", 0)) + 1
	for child in node.get_children():
		if int(budget.get("count", 0)) >= max_nodes:
			break
		_collect_nodes(child, children, depth + 1, max_depth, max_nodes, budget)


static func _rt_find_node(path: String) -> Dictionary:
	var rt = _get_root()
	if not rt:
		return {"error": "No scene root"}
	var node = rt.get_node_or_null(NodePath(path))
	if not node:
		return {"error": "Node not found: " + path}
	return {
		"name": String(node.name),
		"type": node.get_class(),
		"path": node.get_path(),
		"position": _node_pos(node),
		"visible": _node_vis(node),
	}


# ═══════════════════════════════════════════════════════════════════════════
# Input Simulation (frame-accurate)
# ═══════════════════════════════════════════════════════════════════════════

func _rt_click(args: Dictionary) -> Dictionary:
	var path: String = str(args.get("path", ""))
	var x: int = int(args.get("x", -1))
	var y: int = int(args.get("y", -1))
	var hold_frames: int = maxi(1, int(args.get("hold_frames", 1)))
	# Grundsatz: Klicks springen nie - der virtuelle Cursor faehrt immer smooth
	# zum Ziel (sichtbare Geste, kein Teleport), unabhaengig vom Agenten.
	var smooth := true
	var inject_mode: String = str(args.get("inject_mode", "auto"))

	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"error": "No scene tree"}
	var viewport: Window = (tree as SceneTree).root

	var resolved_from_path := false
	if path != "" and x < 0:
		var rt = _get_root()
		if not rt:
			return {"error": "No scene root"}
		var nd: Node = rt.get_node_or_null(NodePath(path))
		if not nd:
			return {"error": "Node not found: " + path, "clicked": false}
		if nd is Control:
			var control := nd as Control
			if not control.is_visible_in_tree():
				return {"error": "Control is not visible", "clicked": false}
			if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
				return {"error": "Control ignores mouse input", "clicked": false}
			if control is BaseButton and (control as BaseButton).disabled:
				return {"error": "Control is disabled", "clicked": false}
			var control_rect := control.get_global_rect()
			var center := control_rect.get_center()
			x = int(center.x)
			y = int(center.y)
			resolved_from_path = true
		elif nd is Node2D:
			var n2d := nd as Node2D
			var screen_pos := n2d.get_global_transform_with_canvas().origin
			x = int(screen_pos.x)
			y = int(screen_pos.y)
			resolved_from_path = true
		else:
			return {"error": "Node type does not support click position resolution", "type": nd.get_class()}

	if x < 0 or y < 0:
		return {"error": "No click position available", "clicked": false}

	var target_vp := Vector2(float(x), float(y))
	# Smoothes Cursor-Travel: Approach-Events von der aktuellen virtuellen
	# Mausposition zum Ziel, danach Press→Release (AGENTS: kein Teleport).
	var approach: Array = []
	if smooth:
		approach = _smooth_approach(target_vp)
	var mode := "push"

	# Coordinate spaces (Godot 4):
	#  - Viewport.push_input expects VIEWPORT-space coords (same space as
	#    Control.get_global_rect() and the screenshot) → use vp_pos unmodified.
	#  - Input.parse_input_event expects WINDOW-pixel coords → map through the
	#    content scale (window size / visible rect).
	# get_screen_transform() contains the window's desktop offset and must NOT
	# be used for in-engine input (that offset breaks click targets).
	var content_size := viewport.get_visible_rect().size
	var window_size := viewport.size
	var scale_x := 1.0
	var scale_y := 1.0
	if content_size.x > 0.0 and content_size.y > 0.0 and window_size.x > 0.0 and window_size.y > 0.0:
		scale_x = float(window_size.x) / content_size.x
		scale_y = float(window_size.y) / content_size.y

	var gesture_events := approach.size() + 2 + hold_frames
	if not _input_capacity_available(gesture_events):
		return {"clicked": false, "error": "input queue full", "pending": get_input_status().get("status", {}).get("pending", 0)}

	if inject_mode == "parse" or (inject_mode == "auto" and (absf(scale_x - 1.0) > 0.001 or absf(scale_y - 1.0) > 0.001)):
		mode = "parse"
		var window_target := Vector2(target_vp.x * scale_x, target_vp.y * scale_y)
		var scheduled := true
		for step_data in approach:
			var step_pos: Vector2 = step_data.get("pos")
			var window_pos := Vector2(step_pos.x * scale_x, step_pos.y * scale_y)
			scheduled = _schedule_mouse_move(false, _make_motion_event(window_pos),
				int(step_data.get("frame", 1)), true, step_pos) and scheduled
		var press_frame := approach.size() + 1
		scheduled = _schedule_mouse_move(false, _make_button_event(window_target, true), press_frame, true, target_vp) and scheduled
		scheduled = _schedule_mouse_move(false, _make_button_event(window_target, false), press_frame + hold_frames, true, target_vp) and scheduled
		if not scheduled:
			return {"clicked": false, "error": "input queue full"}
		return {"clicked": true, "x": int(window_target.x), "y": int(window_target.y),
			"mode": "parse", "resolved_from_path": resolved_from_path,
			"hold_frames": hold_frames, "smooth": approach.size() > 0,
			"approach_steps": approach.size(), "viewport_size": content_size,
			"scale": {"x": scale_x, "y": scale_y}}

	var scheduled := true
	for step_data in approach:
		scheduled = _schedule_mouse_move(false, _make_motion_event(step_data.get("pos")),
			int(step_data.get("frame", 1)), false, step_data.get("pos")) and scheduled
	var press_frame := approach.size() + 1
	scheduled = _schedule_mouse_move(false, _make_button_event(target_vp, true), press_frame, false, target_vp) and scheduled
	scheduled = _schedule_mouse_move(false, _make_button_event(target_vp, false), press_frame + hold_frames, false, target_vp) and scheduled
	if not scheduled:
		return {"clicked": false, "error": "input queue full"}
	return {"clicked": true, "x": x, "y": y, "mode": "push",
		"resolved_from_path": resolved_from_path, "hold_frames": hold_frames,
		"smooth": approach.size() > 0, "approach_steps": approach.size(),
		"viewport_size": content_size, "scale": {"x": 1.0, "y": 1.0}}


func _rt_scroll(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	var x := int(args.get("x", -1))
	var y := int(args.get("y", -1))
	var direction := str(args.get("direction", "down")).to_lower()
	var steps := clampi(int(args.get("steps", 1)), 1, 12)
	if direction not in ["up", "down"]:
		return {"scrolled": false, "error": "direction must be up or down"}
	var tree := Engine.get_main_loop()
	if not tree is SceneTree:
		return {"scrolled": false, "error": "No scene tree"}
	var viewport: Window = (tree as SceneTree).root
	if path != "" and (x < 0 or y < 0):
		var node := _get_root().get_node_or_null(NodePath(path))
		if node == null:
			return {"scrolled": false, "error": "Node not found: " + path}
		if not node is Control or not (node as Control).is_visible_in_tree():
			return {"scrolled": false, "error": "Scroll target is not a visible Control", "path": path}
		var rect := (node as Control).get_global_rect()
		var center := rect.get_center()
		x = int(center.x)
		y = int(center.y)
	if x < 0 or y < 0:
		return {"scrolled": false, "error": "Scroll requires path or x/y"}
	var virtual_pos := _set_virtual_mouse_position(Vector2(float(x), float(y)))
	var parse_mode := _needs_parse_mode(viewport)
	var event_pos := virtual_pos if not parse_mode else _viewport_to_window(viewport, virtual_pos)
	var button := MOUSE_BUTTON_WHEEL_UP if direction == "up" else MOUSE_BUTTON_WHEEL_DOWN
	if not _input_capacity_available(steps):
		return {"scrolled": false, "error": "input queue full", "pending": get_input_status().get("status", {}).get("pending", 0)}
	var scheduled := true
	for index in range(steps):
		scheduled = _schedule_mouse_move(false, _make_wheel_event(event_pos, button), 1 + index, parse_mode, virtual_pos) and scheduled
	if not scheduled:
		return {"scrolled": false, "error": "input queue full"}
	return {"scrolled": true, "path": path, "position": _vector_dict(virtual_pos), "direction": direction, "steps": steps, "mode": "parse" if parse_mode else "push"}


func _make_motion_event(pos: Vector2, button_mask: MouseButtonMask = 0) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = Vector2.ZERO
	e.button_mask = button_mask
	return e


func _make_button_event(pos: Vector2, pressed: bool, button_index: int = MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button_index
	e.position = pos
	e.global_position = pos
	e.pressed = pressed
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button_index == MOUSE_BUTTON_LEFT else 0
	return e


func _make_wheel_event(pos: Vector2, button_index: int) -> InputEventMouseButton:
	var event := _make_button_event(pos, true, button_index)
	event.factor = 1.0
	return event


func _rt_mouse_move(x: int, y: int, smooth: bool = true, duration_ms: int = 120) -> Dictionary:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"error": "No scene tree"}
	var viewport: Window = (tree as SceneTree).root
	var target_vp := _clamp_to_virtual_bounds(Vector2(float(x), float(y)))
	if not smooth:
		if not _input_capacity_available(1):
			return {"moved": false, "requested": {"x": x, "y": y}, "error": "input queue full", "virtual_mouse": _virtual_mouse_status()}
		var virtual_position := _set_virtual_mouse_position(target_vp)
		var event_position := virtual_position
		var parse_mode := _needs_parse_mode(viewport)
		if parse_mode:
			event_position = _viewport_to_window(viewport, virtual_position)
		var moved := _schedule_mouse_move(false, _make_motion_event(event_position), 1, parse_mode, virtual_position)
		return {"moved": moved, "requested": {"x": x, "y": y}, "position": _vector_dict(virtual_position), "mode": "parse" if parse_mode else "push", "smooth": false, "virtual_mouse": _virtual_mouse_status()}
	var travel := _smooth_travel_from_current(target_vp, duration_ms)
	if travel.is_empty():
		# Kein Scheduler / keine virtuelle Maus: Einzel-Event-Fallback.
		if not _input_capacity_available(1):
			return {"moved": false, "requested": {"x": x, "y": y}, "error": "input queue full", "virtual_mouse": _virtual_mouse_status()}
		var virtual_position := _set_virtual_mouse_position(target_vp)
		var event_position := virtual_position
		var parse_mode := _needs_parse_mode(viewport)
		if parse_mode:
			event_position = _viewport_to_window(viewport, virtual_position)
		var moved := _schedule_mouse_move(false, _make_motion_event(event_position), 1, parse_mode, virtual_position)
		return {"moved": moved, "requested": {"x": x, "y": y}, "position": _vector_dict(virtual_position), "mode": "parse" if parse_mode else "push", "smooth": false, "virtual_mouse": _virtual_mouse_status()}
	if not _input_capacity_available(travel.size()):
		return {"moved": false, "requested": {"x": x, "y": y}, "error": "input queue full", "virtual_mouse": _virtual_mouse_status()}
	var parse_mode := _needs_parse_mode(viewport)
	var scheduled := true
	var last_position := target_vp
	for step_data in travel:
		var step_pos: Vector2 = step_data.get("pos")
		last_position = step_pos
		var event_position := step_pos
		if parse_mode:
			event_position = _viewport_to_window(viewport, step_pos)
		scheduled = _schedule_mouse_move(false, _make_motion_event(event_position),
			int(step_data.get("frame", 1)), parse_mode, step_pos) and scheduled
	if not scheduled:
		return {"moved": false, "requested": {"x": x, "y": y}, "error": "input queue full"}
	return {"moved": true, "requested": {"x": x, "y": y}, "position": _vector_dict(last_position),
		"smooth": true, "steps": travel.size(), "from": _vector_dict(_current_virtual_position()),
		"mode": "parse" if parse_mode else "push", "virtual_mouse": _virtual_mouse_status()}


func _rt_drag(args: Dictionary) -> Dictionary:
	var x: int = int(args.get("x", 0))
	var y: int = int(args.get("y", 0))
	var dx: int = int(args.get("dx", 0))
	var dy: int = int(args.get("dy", 0))
	var steps: int = maxi(1, int(args.get("steps", 8)))
	var hold_frames: int = maxi(1, int(args.get("hold_frames", 2)))

	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"error": "No scene tree"}
	var viewport: Window = (tree as SceneTree).root
	var parse_mode := _needs_parse_mode(viewport)
	var requested_start_pos := Vector2(float(x), float(y))
	var gesture_events := steps + 3
	if not _input_capacity_available(gesture_events):
		return {"dragging": false, "error": "input queue full", "pending": get_input_status().get("status", {}).get("pending", 0)}
	var virtual_start_pos := _set_virtual_mouse_position(requested_start_pos)
	var virtual_end_pos := _set_virtual_mouse_position(virtual_start_pos + Vector2(float(dx), float(dy)))
	var start_event_pos := virtual_start_pos if not parse_mode else _viewport_to_window(viewport, virtual_start_pos)
	var scheduled := _schedule_mouse_move(false, _make_motion_event(start_event_pos), 1, parse_mode, virtual_start_pos)
	scheduled = _schedule_mouse_move(false, _make_button_event(start_event_pos, true), 2, parse_mode, virtual_start_pos) and scheduled
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var virtual_position := virtual_start_pos.lerp(virtual_end_pos, t)
		var event_position := virtual_position if not parse_mode else _viewport_to_window(viewport, virtual_position)
		scheduled = _schedule_mouse_move(false, _make_motion_event(event_position, MOUSE_BUTTON_MASK_LEFT), 2 + i, parse_mode, virtual_position) and scheduled
	var end_event_pos := virtual_end_pos if not parse_mode else _viewport_to_window(viewport, virtual_end_pos)
	scheduled = _schedule_mouse_move(false, _make_button_event(end_event_pos, false), 2 + steps + hold_frames, parse_mode, virtual_end_pos) and scheduled
	if not scheduled:
		return {"dragging": false, "error": "input queue full"}
	return {"dragging": true, "from": _vector_dict(virtual_start_pos), "to": _vector_dict(virtual_end_pos),
		"steps": steps, "viewport_size": viewport.get_visible_rect().size, "mode": "parse" if parse_mode else "push"}


## Resolve keycode: accepts int directly, or string name like "KEY_ESCAPE".
static func _resolve_keycode(raw) -> int:
	if raw is int:
		return raw as int
	if raw is float:
		var numeric_keycode: float = raw
		return int(numeric_keycode) if is_equal_approx(numeric_keycode, round(numeric_keycode)) else 0
	if raw is String:
		var s: String = raw as String
		# Map common string key names to Godot Key constants
		match s:
			"KEY_ESCAPE": return KEY_ESCAPE
			"KEY_ENTER": return KEY_ENTER
			"KEY_SPACE": return KEY_SPACE
			"KEY_TAB": return KEY_TAB
			"KEY_BACKSPACE": return KEY_BACKSPACE
			"KEY_DELETE": return KEY_DELETE
			"KEY_LEFT": return KEY_LEFT
			"KEY_RIGHT": return KEY_RIGHT
			"KEY_UP": return KEY_UP
			"KEY_DOWN": return KEY_DOWN
			"KEY_A": return KEY_A
			"KEY_B": return KEY_B
			"KEY_C": return KEY_C
			"KEY_D": return KEY_D
			"KEY_E": return KEY_E
			"KEY_F": return KEY_F
			"KEY_G": return KEY_G
			"KEY_H": return KEY_H
			"KEY_I": return KEY_I
			"KEY_J": return KEY_J
			"KEY_K": return KEY_K
			"KEY_L": return KEY_L
			"KEY_M": return KEY_M
			"KEY_N": return KEY_N
			"KEY_O": return KEY_O
			"KEY_P": return KEY_P
			"KEY_Q": return KEY_Q
			"KEY_R": return KEY_R
			"KEY_S": return KEY_S
			"KEY_T": return KEY_T
			"KEY_U": return KEY_U
			"KEY_V": return KEY_V
			"KEY_W": return KEY_W
			"KEY_X": return KEY_X
			"KEY_Y": return KEY_Y
			"KEY_Z": return KEY_Z
			"KEY_F1": return KEY_F1
			"KEY_F2": return KEY_F2
			"KEY_F3": return KEY_F3
			"KEY_F4": return KEY_F4
			"KEY_F5": return KEY_F5
			"KEY_F6": return KEY_F6
			"KEY_F7": return KEY_F7
			"KEY_F8": return KEY_F8
			"KEY_F9": return KEY_F9
			"KEY_F10": return KEY_F10
			"KEY_F11": return KEY_F11
			"KEY_F12": return KEY_F12
			"KEY_SHIFT": return KEY_SHIFT
			"KEY_CTRL": return KEY_CTRL
			"KEY_ALT": return KEY_ALT
			"KEY_HOME": return KEY_HOME
			"KEY_END": return KEY_END
			"KEY_PAGEUP": return KEY_PAGEUP
			"KEY_PAGEDOWN": return KEY_PAGEDOWN
			_: return 0
	return 0

func _make_key_event(keycode: int, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	return event


func _rt_key(keycode: int, pressed: bool) -> Dictionary:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"error": "No scene tree"}
	if keycode <= 0:
		return {"error": "Invalid keycode", "sent": false}
	var viewport: Window = (tree as SceneTree).root

	var ke = _make_key_event(keycode, pressed)
	# Engine-level, focus-independent injection (remote testing while window unfocused).
	var scheduler := _get_input_scheduler()
	if scheduler == null:
		Input.parse_input_event(ke)
		return {"keycode": keycode, "pressed": pressed, "sent": true, "scheduler": "fallback"}
	var scheduled: Dictionary = scheduler.call("schedule_key_event", ke, 0)
	return {"keycode": keycode, "pressed": pressed, "sent": bool(scheduled.get("scheduled", false)), "scheduler": scheduled}


func _rt_key_gesture(keycode: int, hold_frames: int = 1) -> Dictionary:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"error": "No scene tree", "sent": false}
	if keycode <= 0:
		return {"error": "Invalid keycode", "sent": false}
	var safe_hold := clampi(hold_frames, 1, 120)
	var scheduler := _get_input_scheduler()
	if scheduler == null:
		var press := _rt_key(keycode, true)
		var release := _rt_key(keycode, false)
		return {"keycode": keycode, "sent": bool(press.get("sent", false)) and bool(release.get("sent", false)), "gesture": true, "hold_frames": safe_hold, "scheduler": "fallback"}
	if not _input_capacity_available(1):
		return {"keycode": keycode, "sent": false, "gesture": true, "error": "input queue full"}
	var press_result: Dictionary = _rt_key(keycode, true)
	if not bool(press_result.get("sent", false)):
		return {"keycode": keycode, "sent": false, "gesture": true, "press": press_result}
	var release_event := _make_key_event(keycode, false)
	var release_result: Dictionary = scheduler.call("schedule_key_event", release_event, safe_hold)
	return {
		"keycode": keycode,
		"sent": bool(release_result.get("scheduled", false)),
		"gesture": true,
		"hold_frames": safe_hold,
		"press": press_result,
		"release": release_result,
	}


# ── Frame queue ────────────────────────────────────────────────────────────

func _schedule_mouse_move(_instant: bool, event: InputEvent, delay_frames: int, use_parse: bool = false, virtual_position: Vector2 = Vector2(-1.0, -1.0)) -> bool:
	var scheduler := _get_input_scheduler()
	if scheduler == null:
		_deliver_mouse_event(event, use_parse)
		return true
	var scheduled: Dictionary = scheduler.call("schedule_mouse_event", event, delay_frames, use_parse, virtual_position)
	return bool(scheduled.get("scheduled", false))


func _input_capacity_available(event_count: int) -> bool:
	var scheduler := _get_input_scheduler()
	if scheduler == null:
		return true
	var status: Dictionary = scheduler.call("get_status")
	return int(status.get("pending", 0)) + maxi(0, event_count) <= int(status.get("capacity", 0))


func _deliver_mouse_event(event: InputEvent, use_parse: bool) -> void:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return
	var viewport: Window = (tree as SceneTree).root
	if event != null:
		event.set_meta(&"mcp_virtual_input", true)
	if use_parse:
		Input.parse_input_event(event)
	else:
		viewport.push_input(event)


func get_input_status() -> Dictionary:
	var scheduler := _get_input_scheduler()
	if scheduler == null:
		return {"available": false, "pending": 0}
	return {"available": true, "status": scheduler.call("get_status"), "virtual_mouse": _virtual_mouse_status()}


func _virtual_mouse_status() -> Dictionary:
	var scheduler := _get_input_scheduler()
	if scheduler == null or not scheduler.has_method("get_virtual_mouse_status"):
		return {"active": false, "physical_mouse_blocked": false, "reason": "scheduler_unavailable"}
	return scheduler.call("get_virtual_mouse_status")


func _set_virtual_mouse_position(position: Vector2) -> Vector2:
	var scheduler := _get_input_scheduler()
	if scheduler == null or not scheduler.has_method("get_virtual_mouse_status"):
		return position
	var status: Dictionary = scheduler.call("get_virtual_mouse_status")
	if not bool(status.get("active", false)):
		return position
	var moved: Dictionary = scheduler.call("move_virtual_mouse", position)
	var actual: Dictionary = moved.get("position", {})
	return Vector2(float(actual.get("x", position.x)), float(actual.get("y", position.y)))


func _vector_dict(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}


# ── Smooth cursor travel (player-like movement, no teleport) ────────────────

## Interpolierte Travel-Schritte von `from` nach `to`. Schrittanzahl hängt von
## der Distanz ab (~36 px pro Schritt, mindestens 3, maximal 96) und wird durch
## duration_ms sanft gedeckelt. Statisch und testbar.
static func smooth_travel(from: Vector2, to: Vector2, duration_ms: int = 120) -> Array:
	var dist := from.distance_to(to)
	if dist <= 0.5:
		return []
	# Grundsatz: Der virtuelle Cursor SPRINGT NIE. Die Schrittzahl richtet sich
	# nach der Distanz (~32 px pro Frame, sichtbar weich), mit Mindest-Schritten,
	# damit auch kurze Bewegungen als fließende Geste erscheinen. duration_ms
	# wirkt als Untergrenze (niemals schneller als min_frames Frames).
	var duration_steps := clampi(int(ceil(float(maxi(1, duration_ms)) / 16.0)), 8, 96)
	var distance_steps := clampi(int(ceil(dist / 32.0)), 8, 96)
	var steps := maxi(duration_steps, distance_steps)
	var travel: Array = []
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		travel.append({"pos": from.lerp(to, t), "frame": i, "t": t})
	return travel


func _current_virtual_position() -> Vector2:
	var scheduler := _get_input_scheduler()
	if scheduler != null and scheduler.has_method("get_virtual_mouse_status"):
		var status: Dictionary = scheduler.call("get_virtual_mouse_status")
		if bool(status.get("active", false)):
			var position: Dictionary = status.get("position", {})
			return Vector2(float(position.get("x", 0.0)), float(position.get("y", 0.0)))
	return Vector2(-1.0, -1.0)


func _clamp_to_virtual_bounds(position: Vector2) -> Vector2:
	var scheduler := _get_input_scheduler()
	if scheduler != null and scheduler.has_method("get_virtual_mouse_status"):
		var status: Dictionary = scheduler.call("get_virtual_mouse_status")
		if bool(status.get("active", false)):
			var bounds: Dictionary = status.get("bounds", {})
			var bounds_v := Vector2(float(bounds.get("x", 0.0)), float(bounds.get("y", 0.0)))
			if bounds_v.x > 0.0 and bounds_v.y > 0.0:
				return Vector2(clampf(position.x, 0.0, bounds_v.x), clampf(position.y, 0.0, bounds_v.y))
	return position


## Travel von der aktuellen virtuellen Mausposition zum Ziel (smoothes Hover).
## Liefert [] wenn keine aktive virtuelle Maus existiert (Fallback = Einzel-Event).
func _smooth_travel_from_current(target: Vector2, duration_ms: int = 120) -> Array:
	var current := _current_virtual_position()
	if current.x < 0.0 or current.y < 0.0:
		return []
	var travel := smooth_travel(current, target, duration_ms)
	if travel.is_empty():
		# Ziel == aktuelle Position: ein einzelnes Motion-Event reicht (Position stimmt schon).
		travel = [{"pos": target, "frame": 1, "t": 1.0}]
	return travel


## Approach für Klicks: kurze interpolierte Bewegung zur Zielposition.
func _smooth_approach(target: Vector2) -> Array:
	return _smooth_travel_from_current(target, 90)


func _get_input_scheduler() -> Node:
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return null
	var root := (tree as SceneTree).root
	if root == null:
		return null
	var existing := root.get_node_or_null("McpInputScheduler")
	if existing != null:
		return existing
	var script: Resource = load(INPUT_SCHEDULER_PATH)
	if script == null:
		return null
	var scheduler := script.new() as Node
	if scheduler == null:
		return null
	scheduler.name = "McpInputScheduler"
	root.add_child(scheduler)
	return scheduler


func _needs_parse_mode(viewport: Window) -> bool:
	var visible_size := viewport.get_visible_rect().size
	var window_size := viewport.size
	return visible_size.x > 0.0 and visible_size.y > 0.0 and (
		absf(float(window_size.x) / visible_size.x - 1.0) > 0.001 or
		absf(float(window_size.y) / visible_size.y - 1.0) > 0.001
	)


func _viewport_to_window(viewport: Window, position: Vector2) -> Vector2:
	var visible_size := viewport.get_visible_rect().size
	var window_size := viewport.size
	if visible_size.x <= 0.0 or visible_size.y <= 0.0:
		return position
	return Vector2(
		position.x * float(window_size.x) / visible_size.x,
		position.y * float(window_size.y) / visible_size.y
	)


# ═══════════════════════════════════════════════════════════════════════════
# UI State
# ═══════════════════════════════════════════════════════════════════════════

static func _rt_get_ui_state(path: String) -> Dictionary:
	var rt = _get_root()
	if not rt:
		return {"error": "No scene root"}
	var node = rt.get_node_or_null(NodePath(path))
	if not node:
		return {"error": "Node not found: " + path}

	var state = {
		"path": path,
		"name": String(node.name),
		"type": node.get_class(),
		"visible": _node_vis(node),
		"position": _node_pos(node),
	}

	if node is Control:
		var c = node as Control
		state["rect"] = {"x": c.get_global_position().x, "y": c.get_global_position().y,
			"w": c.get_rect().size.x, "h": c.get_rect().size.y}
		state["focus_mode"] = c.focus_mode
		state["has_focus"] = c.has_focus()

	if node is BaseButton:
		state["disabled"] = (node as BaseButton).disabled
		state["pressed"] = (node as BaseButton).button_pressed
		if node is Button:
			state["text"] = (node as Button).text
	elif node is Label:
		state["text"] = (node as Label).text
	elif node is LineEdit:
		state["text"] = (node as LineEdit).text
		state["placeholder"] = (node as LineEdit).placeholder_text

	return state


static func _rt_wait_frames(frames: int) -> Dictionary:
	var safe_frames := clampi(frames, 0, 600000)
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"error": "No scene tree"}
	for _i in range(safe_frames):
		await (tree as SceneTree).process_frame
	return {"waited": true, "frames": safe_frames}


static func _rt_wait_ms(ms: int) -> Dictionary:
	var tree = Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"error": "No scene tree"}
	var clamped := clampi(ms, 1, 600000)
	await (tree as SceneTree).create_timer(float(clamped) / 1000.0, true).timeout
	return {"waited": true, "ms": clamped}


# ═══════════════════════════════════════════════════════════════════════════
# Expression Eval
# ═══════════════════════════════════════════════════════════════════════════

static func _is_developer_mode() -> bool:
	# Accept --mcp-developer cmdline flag OR MCP_DEVELOPER env-var (any non-empty value)
	if "--mcp-developer" in OS.get_cmdline_args() or "--mcp-developer" in OS.get_cmdline_user_args():
		return true
	var env_val: String = OS.get_environment("MCP_DEVELOPER")
	return env_val != "" and env_val != "0"


static func _rt_eval(code: String) -> Variant:
	var expr = Expression.new()
	var err = expr.parse(code, [])
	if err != OK:
		return {"error": "Parse error: " + error_string(err)}
	var result = expr.execute([], null, true)
	if expr.has_execute_failed():
		return {"error": "Runtime error: " + expr.get_error_text()}
	return {"result": _to_serializable(result)}


# ═══════════════════════════════════════════════════════════════════════════
# Inspector (shared with McpDebug domain but tree-dependent)
# ═══════════════════════════════════════════════════════════════════════════

static func _inspect_node(path: String) -> Dictionary:
	var rt = _get_root()
	if not rt:
		return {"error": "No scene tree"}
	var node = rt.get_node_or_null(NodePath(path))
	if not node:
		return {"error": "Node not found: " + path}

	var properties = []
	var plist = node.get_property_list()
	for p in plist:
		var pd: Dictionary = p
		var usage: int = pd.usage
		var pname: String = pd.name
		if pname == "script":
			continue
		if usage & (PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var entry = {"name": pname, "type": pd.type}
		if usage & PROPERTY_USAGE_STORAGE:
			entry["value"] = _to_serializable(node.get(pname))
		properties.append(entry)

	var slist = []
	var sigs = node.get_signal_list()
	for s in sigs:
		var sd: Dictionary = s
		slist.append({"name": sd.name})

	var ctypes = {}
	for child in node.get_children():
		var t: String = child.get_class()
		ctypes[t] = ctypes.get(t, 0) + 1

	return {
		"name": String(node.name),
		"type": node.get_class(),
		"path": node.get_path(),
		"child_count": node.get_child_count(),
		"child_types": ctypes,
		"properties": properties,
		"signals": slist,
	}


static func _find_nodes_by_type(type_name: String, max_results: int) -> Dictionary:
	var safe_max_results := clampi(max_results, 1, 10000)
	var rt = _get_root()
	if not rt:
		return {"error": "No scene tree"}
	var results = []
	_find_nodes_recursive(rt, type_name, results, safe_max_results)
	return {"nodes": results, "count": results.size(), "truncated": results.size() >= safe_max_results}


static func _find_nodes_recursive(node: Node, type_name: String, results: Array, max_results: int) -> void:
	if results.size() >= max_results:
		return
	if node.get_class() == type_name:
		results.append({"name": String(node.name), "path": node.get_path(), "type": node.get_class()})
	for child in node.get_children():
		_find_nodes_recursive(child, type_name, results, max_results)


static func _node_ancestry(path: String) -> Dictionary:
	var rt = _get_root()
	if not rt:
		return {"error": "No scene tree"}
	var node = rt.get_node_or_null(NodePath(path))
	if not node:
		return {"error": "Node not found: " + path}

	var chain = []
	var current: Node = node
	while current:
		chain.append({"name": String(current.name), "type": current.get_class(), "path": current.get_path()})
		current = current.get_parent()

	return {"chain": chain, "depth": chain.size()}


# ═══════════════════════════════════════════════════════════════════════════
# Shared helpers
# ═══════════════════════════════════════════════════════════════════════════

static func _get_root() -> Window:
	var ml = Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root
	return null


static func _node_pos(n: Node) -> Dictionary:
	if n is CanvasItem:
		var v = (n as CanvasItem).get_global_position()
		return {"x": v.x, "y": v.y}
	elif n is Node3D:
		return {"x": (n as Node3D).global_position.x, "y": (n as Node3D).global_position.y, "z": (n as Node3D).global_position.z}
	return {"x": 0, "y": 0}


static func _node_vis(node: Node) -> bool:
	if node is CanvasItem:
		return (node as CanvasItem).visible
	if node is Node3D:
		return (node as Node3D).visible
	return true


static func _to_serializable(v: Variant) -> Variant:
	if v == null:
		return null
	if v is int or v is float or v is bool or v is String:
		return v
	if v is StringName:
		return String(v)
	if v is Array:
		var arr = []
		for item in v:
			arr.append(_to_serializable(item))
		return arr
	if v is Dictionary:
		var d = {}
		for key in v:
			d[str(key)] = _to_serializable(v[key])
		return d
	if v is Vector2:
		return {"x": v.x, "y": v.y}
	if v is Rect2:
		return {"x": v.position.x, "y": v.position.y, "w": v.size.x, "h": v.size.y}
	if v is Color:
		return {"r": v.r, "g": v.g, "b": v.b, "a": v.a}
	if v is Object:
		return {"_class": "<Object>", "_id": -1}
	return str(v)


static func _make(name: String, description: String, properties: Dictionary = {},
		required: Array = [], async_tool: bool = false) -> Dictionary:
	var schema = {"type": "object", "properties": properties}
	if not required.is_empty():
		schema["required"] = required
	var tool = {"name": name, "description": description, "inputSchema": schema}
	if async_tool:
		tool["_async"] = true
	return tool


# ═══════════════════════════════════════════════════════════════════════════
# Deterministic Frame-Freeze
# ═══════════════════════════════════════════════════════════════════════════

func _rt_freeze() -> Dictionary:
	var scheduler := _get_input_scheduler()
	if scheduler == null or not scheduler.has_method("set_freeze"):
		return {"ok": false, "error": "input scheduler not available"}
	return scheduler.call("set_freeze", true)


func _rt_unfreeze() -> Dictionary:
	var scheduler := _get_input_scheduler()
	if scheduler == null or not scheduler.has_method("set_freeze"):
		return {"ok": false, "error": "input scheduler not available"}
	return scheduler.call("set_freeze", false)


func _rt_step_frame() -> Dictionary:
	var scheduler := _get_input_scheduler()
	if scheduler == null or not scheduler.has_method("step_one_frame"):
		return {"ok": false, "error": "input scheduler not available"}
	return scheduler.call("step_one_frame")


func _rt_step_frames(count: int) -> Dictionary:
	var scheduler := _get_input_scheduler()
	if scheduler == null or not scheduler.has_method("step_frames"):
		return {"ok": false, "error": "input scheduler not available"}
	return scheduler.call("step_frames", count)


func _rt_camera_move_to(args: Dictionary) -> Dictionary:
	var x: float = float(args.get("x", 0))
	var y: float = float(args.get("y", 0))
	var zoom: float = float(args.get("zoom", -1.0))
	var duration: float = float(args.get("duration", 0.5))
	var tree := Engine.get_main_loop()
	if not (tree is SceneTree):
		return {"error": "No scene tree"}
	var root := (tree as SceneTree).root
	if root == null:
		return {"error": "No root node"}
	var camera := root.find_child("MapCamera", true, false)
	if camera == null:
		return {"error": "MapCamera not found"}
	var target_pos := Vector2(x, y)
	if duration <= 0.0:
		camera.position = target_pos
		if zoom > 0.0:
			camera.zoom = Vector2(zoom, zoom)
		return {"ok": true, "instant": true, "position": {"x": camera.position.x, "y": camera.position.y}}
	var tween := (tree as SceneTree).create_tween()
	tween.tween_property(camera, "position", target_pos, duration)
	if zoom > 0.0:
		tween.parallel().tween_property(camera, "zoom", Vector2(zoom, zoom), duration)
	await tween.finished
	return {"ok": true, "position": {"x": camera.position.x, "y": camera.position.y}, "zoom": {"x": camera.zoom.x, "y": camera.zoom.y}}


func _rt_freeze_status() -> Dictionary:
	var scheduler := _get_input_scheduler()
	if scheduler == null or not scheduler.has_method("get_freeze_status"):
		return {"freeze_mode": false, "error": "input scheduler not available"}
	return scheduler.call("get_freeze_status")