extends RefCounted
class_name McpChainController

## McpChainController — Declarative Test and Feature Chain Orchestrator.
##
## Chains combine Headless Preflight / Contract assertions and Visible Runtime
## gameplay actions into a unified, reproducible verification trace:
##   Precondition → Action → Observation → Assertion → Evidence → Verdict

const PREFLIGHT_PATH := "res://scripts/preflight.gd"
const PREFLIGHT_TIMEOUT_MS := 120000
const PREFLIGHT_POLL_MS := 400
const PREFLIGHT_OUT_PATH := "user://mcp_preflight_result.json"

var _registry: RefCounted = null
var _lifecycle: RefCounted = null
var _last_trace: Dictionary = {}
var _running := false


func setup(registry: RefCounted, lifecycle: RefCounted = null) -> void:
	_registry = registry
	_lifecycle = lifecycle


static func get_tool_defs() -> Array:
	return [
		{
			"name": "runtime_chain_run",
			"description": "Execute a declarative multi-step test or feature verification chain",
			"inputSchema": {
				"type": "object",
				"properties": {
					"name": {"type": "string", "description": "Human-readable chain name"},
					"mode": {"type": "string", "enum": ["auto", "headless", "visible"], "default": "auto"},
					"stop_on_failure": {"type": "boolean", "default": true},
					"steps": {
						"type": "array",
						"description": "Ordered chain steps",
						"items": {"type": "object"}
					}
				},
				"required": ["steps"]
			},
			"_async": true
		},
		{
			"name": "runtime_chain_trace",
			"description": "Retrieve the last executed chain evidence trace and step verdicts",
			"inputSchema": {
				"type": "object",
				"properties": {}
			}
		},
		{
			"name": "runtime_chain_validate",
			"description": "Validate an atomic chain without executing it: tool availability, visible-mode safety, screenshot gates, and step contracts",
			"inputSchema": {
				"type": "object",
				"properties": {
					"mode": {"type": "string", "enum": ["auto", "headless", "visible"], "default": "auto"},
					"exploratory": {"type": "boolean", "default": false},
					"steps": {"type": "array", "items": {"type": "object"}}
				},
				"required": ["steps"]
			}
		}
	]


func dispatch_tool(tool_name: String, _args: Dictionary) -> Variant:
	match tool_name:
		"runtime_chain_trace":
			return _last_trace
		"runtime_chain_validate":
			return validate_chain(_args)
		_:
			return {"error": "Unknown chain controller tool: " + tool_name}


func dispatch_async(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"runtime_chain_run":
			return await run_chain(args)
		_:
			return {"error": "Unknown async chain controller tool: " + tool_name}


## Execute a declarative chain.
func validate_chain(chain_def: Dictionary) -> Dictionary:
	var mode := str(chain_def.get("mode", "auto"))
	var exploratory := bool(chain_def.get("exploratory", false))
	var steps: Array = chain_def.get("steps", []) as Array
	var errors: Array = []
	var warnings: Array = []
	if mode not in ["auto", "headless", "visible"]:
		errors.append("mode must be auto, headless, or visible")
	if steps.is_empty():
		errors.append("steps must not be empty")
	if steps.size() > 100:
		errors.append("chain exceeds 100 steps; split the run into validated segments")
	var available: Dictionary = {}
	if _registry != null:
		for definition in _registry.get_all_tools():
			if definition is Dictionary:
				available[str(definition.get("name", ""))] = definition
	var composite_tools := ["runtime_ux_click", "runtime_goal_play", "runtime_goal_sequence", "runtime_chain_run"]
	for index in range(steps.size()):
		var raw: Variant = steps[index]
		if not raw is Dictionary:
			errors.append("step %d is not an object" % index)
			continue
		var step: Dictionary = raw
		var tool_name := str(step.get("tool", ""))
		if tool_name == "":
			errors.append("step %d has no tool" % index)
			continue
		if not available.has(tool_name) and tool_name != "preflight_constraint":
			errors.append("step %d references unavailable tool %s" % [index, tool_name])
		if tool_name in composite_tools:
			errors.append("step %d uses composite tool %s; use one atomic tool per step" % [index, tool_name])
		if mode == "visible" and (tool_name.begins_with("game_") or tool_name in ["runtime_goal_check", "runtime_goal_history"]):
			errors.append("step %d uses non-player/game-state tool %s in visible mode" % [index, tool_name])
		if tool_name == "runtime_screenshot" and str(step.get("reason", "")).strip_edges() == "":
			errors.append("step %d screenshot requires a reason; capture only on ambiguity" % index)
		if tool_name.begins_with("runtime_") and step.get("args", {}) is not Dictionary:
			errors.append("step %d args must be an object" % index)
		if tool_name not in ["runtime_wait_ms", "runtime_wait_frames"] and not step.has("assertion") and not step.has("expect"):
			warnings.append("step %d has no postcondition/assertion" % index)
		if tool_name == "runtime_ux_find" and str(step.get("args", {}).get("root_path", "/root")) == "/root":
			warnings.append("step %d uses broad UI scope; prefer the current panel root_path" % index)
	if mode == "visible" and exploratory:
		errors.append("exploratory visible play must remain interactive; validate segments only after discovery")
	if mode == "visible" and steps.size() > 20:
		warnings.append("long visible chain; split at panel transitions to preserve player-like decisions")
	return {
		"ok": errors.is_empty(),
		"verdict": "PASS" if errors.is_empty() else "BLOCKED",
		"mode": mode,
		"exploratory": exploratory,
		"step_count": steps.size(),
		"errors": errors,
		"warnings": warnings,
		"rules": {
			"one_tool_call_per_step": true,
			"screenshots_only_with_reason": true,
			"visible_mode_disallows_game_state": true,
			"bounded_context_required": true,
		},
	}


## Execute a declarative chain.
func run_chain(chain_def: Dictionary) -> Dictionary:
	var validation := validate_chain(chain_def)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "verdict": "BLOCKED", "validation": validation}
	if _running:
		return {"ok": false, "error": "Chain execution already in progress"}
	_running = true

	var chain_name: String = str(chain_def.get("name", "unnamed_chain"))
	var stop_on_failure: bool = bool(chain_def.get("stop_on_failure", true))
	var steps: Array = chain_def.get("steps", []) as Array

	var trace_id := "trace_%d" % int(Time.get_unix_time_from_system())
	var step_results: Array = []
	var passed := true
	var failed_step := -1
	var failure_reason := ""
	var start_time := Time.get_ticks_msec()

	for i in range(steps.size()):
		var raw_step = steps[i]
		if not (raw_step is Dictionary):
			continue
		var step: Dictionary = raw_step
		var step_name := str(step.get("name", "step_%d" % i))
		var step_mode := str(step.get("mode", "auto"))

		var result: Dictionary = {
			"step_index": i,
			"name": step_name,
			"mode": step_mode,
			"status": "pending",
			"timestamp_ms": Time.get_ticks_msec(),
		}

		# 1. Precondition check (if provided)
		var precondition: String = str(step.get("precondition", ""))
		if precondition != "":
			var pre_eval := _eval_expression(precondition)
			if not bool(pre_eval.get("result", false)):
				result["status"] = "PRECONDITION_FAILED"
				result["precondition_eval"] = pre_eval
				passed = false
				step_results.append(result)
				if stop_on_failure:
					failed_step = i
					failure_reason = "Precondition failed on step: " + step_name
					break
				continue

		# 2. Execute Step Action
		var tool_name := str(step.get("tool", ""))
		var tool_args: Dictionary = step.get("args", {}) if step.get("args") is Dictionary else {}
		var action_result: Variant = null

		if tool_name != "":
			if tool_name == "preflight_constraint":
				action_result = await _run_preflight_constraint(str(tool_args.get("constraint", "")))
			elif _registry != null:
				if _is_async_tool(tool_name):
					action_result = await _registry.dispatch_async(tool_name, tool_args)
				else:
					action_result = _registry.dispatch(tool_name, tool_args)
			else:
				action_result = {"error": "registry unavailable"}
			result["action_result"] = action_result

		# 3. Assertion check (if provided)
		var assertion: String = str(step.get("assertion", ""))
		if assertion != "":
			var assert_eval := _eval_expression(assertion)
			var ok := bool(assert_eval.get("result", false))
			result["assertion_eval"] = assert_eval
			if not ok:
				result["status"] = "ASSERTION_FAILED"
				passed = false
				step_results.append(result)
				if stop_on_failure:
					failed_step = i
					failure_reason = "Assertion failed on step: " + step_name
					break
				continue

		result["status"] = "PASSED"
		step_results.append(result)

	var total_duration_ms := Time.get_ticks_msec() - start_time
	_last_trace = {
		"trace_id": trace_id,
		"chain_name": chain_name,
		"verdict": "PASS" if passed else "FAIL",
		"duration_ms": total_duration_ms,
		"total_steps": steps.size(),
		"completed_steps": step_results.size(),
		"failed_step": failed_step,
		"failure_reason": failure_reason,
		"steps": step_results,
	}

	_running = false
	return _last_trace


func _is_async_tool(name: String) -> bool:
	return name in [
		"runtime_wait_frames",
		"runtime_wait_ms",
		"runtime_camera_move_to",
		"runtime_screenshot",
		"runtime_goal_play",
		"runtime_e2e_run",
		"runtime_autonomy_probe",
		"runtime_chain_run"
	]


func _eval_expression(code: String) -> Dictionary:
	var expr := Expression.new()
	var err := expr.parse(code, [])
	if err != OK:
		return {"ok": false, "error": "parse error: " + error_string(err), "result": false}
	var tree := Engine.get_main_loop()
	var base_context: Object = null
	if tree is SceneTree and (tree as SceneTree).root != null:
		base_context = (tree as SceneTree).root.get_node_or_null("/root/GameState")
	var res = expr.execute([], base_context, false)
	if expr.has_execute_failed():
		return {"ok": false, "error": expr.get_error_text(), "result": false}
	return {"ok": true, "result": res}


## Führt Preflight real als Subprozess aus (headless) und pollt das
## --mcp-json-Ergebnis. Kein Platzhalter mehr: Ein Constraint gilt nur als
## PASS, wenn die Preflight-Suite es wirklich bestätigt hat.
func _run_preflight_constraint(constraint_name: String) -> Dictionary:
	var name := constraint_name.strip_edges()
	if name == "":
		return {"ok": false, "error": "no constraint specified"}
	var project_dir := ProjectSettings.globalize_path("res://")
	var out_path := ProjectSettings.globalize_path(PREFLIGHT_OUT_PATH)
	if FileAccess.file_exists(out_path):
		DirAccess.remove_absolute(out_path)
	var args := PackedStringArray([
		"--path", project_dir, "--headless",
		"--script", PREFLIGHT_PATH,
		"--filter=" + name, "--mcp-json=" + out_path,
	])
	var pid := OS.create_process(OS.get_executable_path(), args, false)
	if pid <= 0:
		return {"ok": false, "verdict": "FAIL", "error": "preflight subprocess failed to start", "constraint": name}
	var deadline := Time.get_ticks_msec() + PREFLIGHT_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(out_path):
			var file := FileAccess.open(out_path, FileAccess.READ)
			if file != null:
				var parsed: Variant = JSON.parse_string(file.get_as_text())
				file.close()
				DirAccess.remove_absolute(out_path)
				if parsed is Dictionary:
					(parsed as Dictionary)["constraint"] = name
					(parsed as Dictionary)["pid"] = pid
					return parsed
		await _wait_ms(PREFLIGHT_POLL_MS)
	return {"ok": false, "verdict": "FAIL", "error": "preflight timeout after %d ms" % PREFLIGHT_TIMEOUT_MS, "constraint": name}


func _wait_ms(ms: int) -> void:
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		await (tree as SceneTree).create_timer(float(ms) / 1000.0, true).timeout
