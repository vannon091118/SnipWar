extends RefCounted
class_name McpGoalPlayer

## Goal-based autonomous playtester.
##
## Flow:
##   1. Analyze code → learn input methods
##   2. Freeze game
##   3. Screenshot + Eval goal
##   4. Decide next action (click interactable, press key)
##   5. Step N frames
##   6. Repeat until goal met or budget exhausted
##   7. Return Pass/Fail with evidence (steps, screenshots, anomalies)

const MAX_STEPS := 500
const STEP_TIMEOUT_MS := 60000
const DEFAULT_STEP_FRAMES := 3

var _registry: RefCounted = null
var _lifecycle: RefCounted = null


func setup(registry: RefCounted, lifecycle: RefCounted) -> void:
	_registry = registry
	_lifecycle = lifecycle


## Main entry: play a goal expression.
## goal: GDScript expression evaluated via runtime_eval, e.g. "GameState.run_id() != &''"
## scene_path: optional .tscn to load before playing
## max_steps: budget override
func play_goal(goal: String, scene_path: String = "", max_steps: int = MAX_STEPS) -> Dictionary:
	var steps: Array = []
	var start_ms := Time.get_ticks_msec()
	var anomalies: Array = []
	# No-progress circuit breaker (Playtest-Handoff MCP-07): nach 3 identischen
	# UI-Beobachtungen ohne Fortschritt stoppen statt Endlosschleife.
	var last_signature := ""
	var no_progress := 0

	# 1. Analyze project code for input hints
	var hints := McpCodeAnalyzer.analyze_input()
	var has_keyboard := bool(not hints.get("_input", []).is_empty() or not hints.get("is_action_pressed", []).is_empty())
	var has_mouse := bool(not hints.get("_unhandled_input", []).is_empty() or not hints.get("_gui_input", []).is_empty())

	# 2. Load scene if specified
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var loaded := load(scene_path)
		if loaded != null:
			var tree := Engine.get_main_loop()
			if tree is SceneTree:
				(tree as SceneTree).root.add_child(loaded.instantiate())
				await (tree as SceneTree).process_frame
				await (tree as SceneTree).process_frame

	# 3. Freeze
	_call("runtime_freeze", {})

	# 4. Main loop
	for i in max_steps:
		if Time.get_ticks_msec() - start_ms > STEP_TIMEOUT_MS:
			_call("runtime_unfreeze", {})
			return _verdict("timeout", goal, steps, anomalies, "Timeout after %d ms" % STEP_TIMEOUT_MS)

		# a. Screenshot + UX state
		var scan := _call_dict("runtime_ux_scan", {})
		var snapshot := {
			"step": i,
			"scene": str(scan.get("scene", "?")),
			"interactables": scan.get("interactables", []),
			"control_count": scan.get("control_count", 0),
			"timestamp_ms": Time.get_ticks_msec(),
		}
		steps.append(snapshot)

		# No-progress-Breaker: identische UI-Signatur (Scene + Interactables mit
		# Texte und disabled/pressed-Zustand) über 3 Beobachtungen → BLOCKED.
		var signature := _scan_signature(scan)
		if signature == last_signature:
			no_progress += 1
		else:
			no_progress = 0
		last_signature = signature
		if no_progress >= 3:
			_call("runtime_unfreeze", {})
			steps.append({"no_progress": true, "identical_observations": no_progress + 1})
			return _verdict("blocked", goal, steps, anomalies,
				"No-progress circuit breaker: %d identische UI-Beobachtungen ohne Fortschritt" % (no_progress + 1))

		# b. Check goal
		var eval_result := _eval_goal_expression(goal)
		var reached := bool(eval_result.get("reached", false))
		if reached:
			_call("runtime_unfreeze", {})
			steps.append({"goal_reached": true, "eval": eval_result})
			return _verdict("pass", goal, steps, anomalies, "Goal condition evaluated to true")

		# c. Get interactable actions
		var interactables: Array = scan.get("interactables", [])
		var action_taken := false

		# d. Try clicking the first interactable that is not already pressed
		for raw in interactables:
			var ctrl: Dictionary = raw
			if bool(ctrl.get("disabled", false)):
				continue
			if ctrl.has("pressed") and bool(ctrl.get("pressed", false)):
				continue  # skip toggle already on
			var desc := str(ctrl.get("text", ""))
			if desc == "":
				desc = str(ctrl.get("name", ""))
			if desc == "":
				continue
			var center: Dictionary = ctrl.get("center", {})
			var cx := int(center.get("x", 0))
			var cy := int(center.get("y", 0))
			if cx > 0 and cy > 0:
				_call("runtime_click", {"x": cx, "y": cy, "hold_frames": 2})
				steps.append({"action": "click", "target": desc, "x": cx, "y": cy})
				action_taken = true
				break

		# e. Fallback: press SPACE
		if not action_taken and has_keyboard:
			_call("runtime_key", {"keycode": KEY_SPACE, "pressed": true})
			_call("runtime_key", {"keycode": KEY_SPACE, "pressed": false})
			steps.append({"action": "key", "keycode": "KEY_SPACE"})
			action_taken = true

		# f. No action available
		if not action_taken:
			steps.append({"action": "none", "reason": "No interactable found and no keyboard input detected"})

		# g. Step frames (consecutive, so tweens/transitions can complete)
		var step_count := int(_call_dict("runtime_freeze_status", {}).get("frames_stepped", 0))
		_call("runtime_step_frames", {"count": DEFAULT_STEP_FRAMES})
		var step_count_after := int(_call_dict("runtime_freeze_status", {}).get("frames_stepped", 0))
		steps.append({"frames_advanced": step_count_after - step_count})

	# 5. Budget exhausted
	_call("runtime_unfreeze", {})
	return _verdict("budget_exceeded", goal, steps, anomalies, "Max steps (%d) reached without satisfying goal" % max_steps)


# ─── Helpers ────────────────────────────────────────────────────

func _call(tool_name: String, args: Dictionary) -> Variant:
	if _registry == null:
		return {"error": "Registry not set"}
	return _registry.dispatch(tool_name, args)


func _call_dict(tool_name: String, args: Dictionary) -> Dictionary:
	var result := _call(tool_name, args)
	return result if result is Dictionary else {"_raw": str(result)}


## Evaluate a GDScript expression directly via Godot's Expression class.
## No dependency on runtime_eval or --mcp-developer flag.
func _eval_goal_expression(goal: String) -> Dictionary:
	var expr := Expression.new()
	var err := expr.parse(goal, [])
	if err != OK:
		return {"reached": false, "error": "parse error: " + expr.get_error_text(), "line": expr.get_error_line()}
	var result: Variant = expr.execute([], null)
	if expr.has_execute_failed():
		return {"reached": false, "error": "execute error: " + expr.get_error_text()}
	return {"reached": _is_truthy(result), "result": str(result), "type": typeof(result)}


## Kompakte, deterministisch sortierte UI-Signatur für den No-progress-Breaker.
func _scan_signature(scan: Dictionary) -> String:
	var parts: Array = []
	parts.append(str(scan.get("scene", "")))
	parts.append(str(scan.get("screen_size", "")))
	for raw in scan.get("interactables", []):
		if not (raw is Dictionary):
			continue
		var ctrl: Dictionary = raw
		parts.append("%s|%s|d:%s|p:%s|%s,%s" % [
			str(ctrl.get("text", "")),
			str(ctrl.get("name", "")),
			str(ctrl.get("disabled", false)),
			str(ctrl.get("pressed", false)),
			str(ctrl.get("center", {}).get("x", 0)),
			str(ctrl.get("center", {}).get("y", 0)),
		])
	parts.sort()
	return "|".join(parts)


func _is_truthy(value: Variant) -> bool:
	if value is bool:
		return value
	if value is int:
		return value != 0
	if value is float:
		return value != 0.0
	if value is String:
		return value != "" and value != "false" and value != "null"
	if value is StringName:
		return value != &"" and value != &"false"
	if value is Array:
		return not value.is_empty()
	if value is Dictionary:
		return not value.is_empty()
	return value != null


func _verdict(outcome: String, goal: String, steps: Array, anomalies: Array, reason: String) -> Dictionary:
	return {
		"ok": outcome == "pass",
		"verdict": outcome.to_upper(),
		"goal": goal,
		"steps_count": steps.size(),
		"anomaly_count": anomalies.size(),
		"anomalies": anomalies,
		"reason": reason,
		"steps": steps.slice(maxi(0, steps.size() - 30), steps.size()),  # last 30 steps
	}


# ─── Sequence Player ─────────────────────────────────────────────

## Execute a deterministic sequence of targeted actions (clicks, camera, keys, waits, assertions).
func play_sequence(actions: Array, goal: String = "") -> Dictionary:
	var steps: Array = []
	var anomalies: Array = []

	for i in range(actions.size()):
		var raw_act = actions[i]
		if not (raw_act is Dictionary):
			continue
		var act: Dictionary = raw_act
		var type: String = str(act.get("type", ""))
		var step_rec: Dictionary = {"step": i, "type": type}

		match type:
			"click_text", "click":
				var text := str(act.get("text", ""))
				if text != "":
					var click_res = _call("runtime_ux_click", {"text": text})
					step_rec["result"] = click_res
				else:
					var x: int = int(act.get("x", -1))
					var y: int = int(act.get("y", -1))
					var click_res = _call("runtime_click", {"x": x, "y": y})
					step_rec["result"] = click_res
			"camera_to":
				var x: float = float(act.get("x", 0))
				var y: float = float(act.get("y", 0))
				var zoom: float = float(act.get("zoom", -1.0))
				var duration: float = float(act.get("duration", 0.0))
				if _registry != null:
					var cam_res = await _registry.dispatch_async("runtime_camera_move_to", {"x": x, "y": y, "zoom": zoom, "duration": duration})
					step_rec["result"] = cam_res
			"key":
				var keycode = act.get("keycode", act.get("key", KEY_SPACE))
				var code: int = int(keycode) if keycode is int else _resolve_key_name(str(keycode))
				_call("runtime_key", {"keycode": code, "pressed": true})
				_call("runtime_key", {"keycode": code, "pressed": false})
				step_rec["result"] = {"key": code}
			"wait_frames":
				var frames: int = int(act.get("count", 1))
				var tree := Engine.get_main_loop()
				if tree is SceneTree:
					for _f in range(frames):
						await (tree as SceneTree).process_frame
				step_rec["result"] = {"frames": frames}
			"assert":
				var expr_str: String = str(act.get("code", act.get("expression", "")))
				var eval_res := _eval_goal_expression(expr_str)
				step_rec["assert_eval"] = eval_res
				if not bool(eval_res.get("reached", false)):
					steps.append(step_rec)
					return _verdict("fail", goal if goal != "" else expr_str, steps, anomalies, "Assertion failed on step %d: %s" % [i, expr_str])

		steps.append(step_rec)

	if goal != "":
		var final_eval := _eval_goal_expression(goal)
		if not bool(final_eval.get("reached", false)):
			return _verdict("fail", goal, steps, anomalies, "Final goal condition not reached: " + goal)

	return _verdict("pass", goal, steps, anomalies, "All sequence actions completed successfully")


func _resolve_key_name(s: String) -> int:
	match s.to_upper():
		"KEY_ESCAPE", "ESCAPE", "ESC": return KEY_ESCAPE
		"KEY_ENTER", "ENTER": return KEY_ENTER
		"KEY_SPACE", "SPACE": return KEY_SPACE
		"KEY_TAB", "TAB": return KEY_TAB
		"KEY_BACKSPACE", "BACKSPACE": return KEY_BACKSPACE
		"KEY_W", "W": return KEY_W
		"KEY_A", "A": return KEY_A
		"KEY_S", "S": return KEY_S
		"KEY_D", "D": return KEY_D
		_: return KEY_SPACE


# ─── Tool Definitions ───────────────────────────────────────────

static func get_tool_defs() -> Array:
	return [
		_make("runtime_goal_play", "Autonomously play towards a GDScript-evaluable goal expression using freeze/step", {"goal": {"type": "string"}, "scene_path": {"type": "string", "default": ""}, "max_steps": {"type": "integer", "default": 500}}, ["goal"]),
		_make("runtime_goal_sequence", "Execute a deterministic sequence of targeted actions and assertions", {"actions": {"type": "array", "items": {"type": "object"}}, "goal": {"type": "string", "default": ""}}, ["actions"], true),
		_make("runtime_goal_check", "Evaluate a goal expression once without stepping", {"goal": {"type": "string"}}, ["goal"]),
		_make("runtime_goal_history", "Return the last goal-play steps for inspection", {"limit": {"type": "integer", "default": 50}}),
	]


static func _make(name: String, description: String, properties: Dictionary = {}, required: Array = [], async_tool: bool = false) -> Dictionary:
	var schema := {"type": "object", "properties": properties}
	if not required.is_empty():
		schema["required"] = required
	var tool := {"name": name, "description": description, "inputSchema": schema}
	if async_tool:
		tool["_async"] = true
	return tool

var _last_steps: Array = []


func dispatch_tool(tool_name: String, args: Dictionary) -> Variant:
	if _registry == null:
		return {"error": "Goal player not initialized — call setup() with registry and lifecycle"}
	match tool_name:
		"runtime_goal_check":
			return _eval_goal_expression(str(args.get("goal", "")))
		"runtime_goal_history":
			var limit := maxi(1, int(args.get("limit", 50)))
			var out := _last_steps.duplicate()
			if out.size() > limit:
				out.resize(limit)
			return {"steps": out, "count": out.size()}
		_:
			return {"error": "Unknown goal player tool: " + tool_name}


func dispatch_async(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"runtime_goal_play":
			var result := await play_goal(
				str(args.get("goal", "")),
				str(args.get("scene_path", "")),
				int(args.get("max_steps", MAX_STEPS)),
			)
			_last_steps = result.get("steps", [])
			return result
		"runtime_goal_sequence":
			var actions: Array = args.get("actions", []) as Array
			var goal: String = str(args.get("goal", ""))
			var result := await play_sequence(actions, goal)
			_last_steps = result.get("steps", [])
			return result
		_:
			return {"error": "Unknown async goal player tool: " + tool_name}