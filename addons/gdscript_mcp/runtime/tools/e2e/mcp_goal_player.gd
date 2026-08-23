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


# ─── Tool Definitions ───────────────────────────────────────────

static func get_tool_defs() -> Array:
	return [
		_make("runtime_goal_play", "Autonomously play towards a GDScript-evaluable goal expression using freeze/step", {"goal": {"type": "string"}, "scene_path": {"type": "string", "default": ""}, "max_steps": {"type": "integer", "default": 500}}, ["goal"]),
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
		_:
			return {"error": "Unknown async goal player tool: " + tool_name}