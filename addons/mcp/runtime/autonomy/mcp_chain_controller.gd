extends RefCounted
class_name McpChainController

## McpChainController — Declarative Test and Feature Chain Orchestrator.
##
## Chains combine Headless Preflight / Contract assertions and Visible Runtime
## gameplay actions into a unified, reproducible verification trace:
##   Precondition → Action → Observation → Assertion → Evidence → Verdict

const PREFLIGHT_PATH := "res://scripts/preflight.gd"  # Default (SnipWar). Konfigurierbar über application/mcp/preflight_script.
const PREFLIGHT_TIMEOUT_MS := 120000
const PREFLIGHT_POLL_MS := 400
const PREFLIGHT_OUT_PATH := "user://mcp_preflight_result.json"

# Versionierte Chain-Manifeste (F5): wiederholbare, deklarative Testketten als
# JSON-Dateien unter addons/gdscript_mcp/mcp_chains/<id>.json (HARD SEPARATION:
# MCP-Assets leben ausschließlich im Addon, nie im Spiel-Root; überschreibbar
# über application/mcp/chain_dir).
const CHAIN_DIR := "res://addons/gdscript_mcp/mcp_chains"

# Host-Tools leben NICHT in der Registry — der Server dispatched sie über
# _dispatch_host_tool_for_chain als Fallback (set_host_dispatch). Die
# Validierung muss sie kennen, sonst failt jede Kette, die den Server-Zustand
# prüft (z.B. world_smoke mit runtime_mcp_status), beim Validate.
const HOST_TOOLS := [
	"runtime_mcp_status",
	"runtime_mcp_events",
	"runtime_agent_activity",
	"runtime_run_trace",
	"editor_logs_read",
]

var _registry: RefCounted = null
var _lifecycle: RefCounted = null
var _host_dispatch: Callable = Callable()
var _last_trace: Dictionary = {}
var _running := false


func setup(registry: RefCounted, lifecycle: RefCounted = null) -> void:
	_registry = registry
	_lifecycle = lifecycle


## Host-Tools (runtime_mcp_status, runtime_agent_activity, editor_logs_read, …)
## leben nicht in der Registry — der Server meldet sich hiermit als Fallback,
## damit Chain-Steps ALLE Server-Tools nutzen dürfen (kein "Unknown tool").
func set_host_dispatch(dispatch: Callable) -> void:
	_host_dispatch = dispatch


static func get_tool_defs() -> Array:
	return [
		{
			"name": "runtime_chain_run",
			"description": "Execute a declarative multi-step test or feature verification chain. Pass chain_id to run a versioned manifest from the chain catalog (res://addons/gdscript_mcp/mcp_chains), or inline steps for ad-hoc chains",
			"inputSchema": {
				"type": "object",
				"properties": {
					"chain_id": {"type": "string", "description": "Versioned chain manifest id (res://addons/gdscript_mcp/mcp_chains/<id>.json). Overrides inline steps"},
					"name": {"type": "string", "description": "Human-readable chain name"},
					"mode": {"type": "string", "enum": ["auto", "headless", "visible"], "default": "auto"},
					"stop_on_failure": {"type": "boolean", "default": true},
					"steps": {
						"type": "array",
						"description": "Ordered chain steps (required unless chain_id is given)",
						"items": {"type": "object"}
					}
				}
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
			"description": "Validate an atomic chain without executing it: tool availability, mode safety, screenshot gates, and step contracts. Accepts chain_id to validate a manifest",
			"inputSchema": {
				"type": "object",
				"properties": {
					"chain_id": {"type": "string", "description": "Versioned chain manifest id"},
					"mode": {"type": "string", "enum": ["auto", "headless", "visible"], "default": "auto"},
					"exploratory": {"type": "boolean", "default": false},
					"steps": {"type": "array", "items": {"type": "object"}}
				}
			},
		},
		{
			"name": "runtime_chain_list",
			"description": "List versioned chain manifests from the chain catalog (res://addons/gdscript_mcp/mcp_chains/*.json): id, name, description, mode, step count",
			"inputSchema": {"type": "object", "properties": {}},
		},
		{
			"name": "runtime_chain_load",
			"description": "Load and validate a chain manifest by id; returns the validated chain definition ready for runtime_chain_run",
			"inputSchema": {"type": "object", "properties": {"chain_id": {"type": "string"}}, "required": ["chain_id"]},
		},
	]


func dispatch_tool(tool_name: String, _args: Dictionary) -> Variant:
	match tool_name:
		"runtime_chain_trace":
			return _last_trace
		"runtime_chain_validate":
			return _validate_with_manifest(_args)
		"runtime_chain_list":
			return list_manifests()
		"runtime_chain_load":
			return load_manifest(str(_args.get("chain_id", "")))
		_:
			return {"error": "Unknown chain controller tool: " + tool_name}


func dispatch_async(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"runtime_chain_run":
			return await run_chain(args)
		_:
			return {"error": "Unknown async chain controller tool: " + tool_name}


## Validates inline steps, or loads a manifest first when chain_id is given.
func _validate_with_manifest(chain_def: Dictionary) -> Dictionary:
	var chain_id := str(chain_def.get("chain_id", ""))
	if chain_id == "":
		return validate_chain(chain_def)
	var manifest := load_manifest(chain_id)
	if not bool(manifest.get("ok", false)):
		return {"ok": false, "verdict": "BLOCKED", "error": str(manifest.get("error", "manifest not found"))}
	var merged: Dictionary = chain_def.duplicate(true)
	var manifest_def: Dictionary = manifest.get("def", {})
	for key in ["name", "description", "mode", "stop_on_failure", "steps"]:
		if not merged.has(key):
			merged[key] = manifest_def.get(key)
	merged["id"] = chain_id
	return validate_chain(merged)


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
	# Host-Tools (Server-Dispatch-Fallback) sind valid — sonst failt jede
	# Kette, die den Server-Zustand prüft (z.B. runtime_mcp_status), beim
	# Validate, obwohl zur Laufzeit der Server sie dispatched.
	for host_tool in HOST_TOOLS:
		available[host_tool] = {}
	# Host-Tools (Server-Dispatch-Fallback) sind valid — sonst failt jede
	# Kette, die den Server-Zustand prüft (z.B. runtime_mcp_status), beim
	# Validate, obwohl zur Laufzeit der Server sie dispatched.
	for host_tool in HOST_TOOLS:
		available[host_tool] = {}
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
			errors.append("step %d has no postcondition/assertion (HART: kein blindes Tool-Feuer, kein Fake-Testing)" % index)
		if tool_name == "runtime_ux_find" and str(step.get("args", {}).get("root_path", "/root")) == "/root":
			errors.append("step %d uses broad UI scope; prefer the current panel root_path (HART: bounded context required)" % index)
	if mode == "visible" and exploratory:
		errors.append("exploratory visible play must remain interactive; validate segments only after discovery")
	if mode == "visible" and steps.size() > 20:
		errors.append("long visible chain (>20 steps); split at panel transitions to preserve player-like decisions (HART)")
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


## Execute a declarative chain. When chain_id is given, the manifest is loaded
## and merged BEFORE validation (its steps become the chain definition).
func run_chain(chain_def: Dictionary) -> Dictionary:
	var chain := chain_def.duplicate(true)
	var chain_id := str(chain_def.get("chain_id", ""))
	var manifest_path := ""
	if chain_id != "":
		var manifest := load_manifest(chain_id)
		if not bool(manifest.get("ok", false)):
			return {"ok": false, "verdict": "BLOCKED", "error": str(manifest.get("error", "manifest not found"))}
		var manifest_def: Dictionary = manifest.get("def", {})
		for key in ["name", "description", "mode", "stop_on_failure", "steps"]:
			if not chain.has(key):
				chain[key] = manifest_def.get(key)
		chain["id"] = chain_id
		manifest_path = str(manifest.get("path", ""))
	var validation := validate_chain(chain)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "verdict": "BLOCKED", "validation": validation}
	if _running:
		return {"ok": false, "error": "Chain execution already in progress"}
	_running = true

	var chain_name: String = str(chain.get("name", "unnamed_chain"))
	var stop_on_failure: bool = bool(chain.get("stop_on_failure", true))
	var steps: Array = chain.get("steps", []) as Array

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
				# Host-Tool-Fallback: "Unknown tool" aus der Registry heißt
				# nicht tot — der Server dispatched Host-Tools direkt.
				if action_result is Dictionary and str(action_result.get("error", "")).begins_with("Unknown tool") and _host_dispatch.is_valid():
					action_result = _host_dispatch.call(tool_name, tool_args)
				elif (action_result == null or (action_result is Dictionary and action_result.is_empty())) and _host_dispatch.is_valid():
					action_result = _host_dispatch.call(tool_name, tool_args)
			else:
				action_result = {"error": "registry unavailable"}
			result["action_result"] = action_result

		# 3. Assertion check (assertion expression with result binding, or the
		#    declarative expect form: {key, op, value} against the tool result)
		var assertion: String = str(step.get("assertion", ""))
		var expect: Variant = step.get("expect", null)
		if assertion != "" or expect != null:
			var ok := false
			var assert_eval: Dictionary = {}
			if assertion != "":
				assert_eval = _eval_expression(assertion, {"result": action_result})
				ok = bool(assert_eval.get("result", false))
			else:
				assert_eval = _expect_check(action_result, expect)
				ok = bool(assert_eval.get("result", false))
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
		"chain_id": chain_id,
		"manifest_path": manifest_path,
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
		"runtime_autonomy_export",
		"runtime_chain_run"
	]


## Wertet einen GDScript-Ausdruck aus. inputs (z.B. {"result": action_result})
## werden als benannte Variablen gebunden; base_instance ist der GameState-
## Node (falls verfügbar), damit Assertions auch Spielzustand lesen können.
func _eval_expression(code: String, inputs: Dictionary = {}) -> Dictionary:
	var expr := Expression.new()
	var input_names: Array = inputs.keys()
	var err := expr.parse(code, input_names)
	if err != OK:
		return {"ok": false, "error": "parse error: " + error_string(err), "result": false}
	var tree := Engine.get_main_loop()
	var base_context: Object = null
	if tree is SceneTree and (tree as SceneTree).root != null:
		var root := (tree as SceneTree).root
		var configured_path := str(ProjectSettings.get_setting("application/mcp/game_state_node", ""))
		if configured_path.begins_with("/"):
			base_context = root.get_node_or_null(NodePath(configured_path))
		if base_context == null:
			base_context = root.get_node_or_null("/root/GameState")
		if base_context == null:
			base_context = root.find_child("GameState", true, false)
	var input_values: Array = []
	for name in input_names:
		input_values.append(inputs[name])
	var res = expr.execute(input_values, base_context, false)
	if expr.has_execute_failed():
		return {"ok": false, "error": expr.get_error_text(), "result": false}
	return {"ok": true, "result": res}


## Deklarative Expect-Prüfung gegen ein Tool-Result: {key, op, value}.
## op: ==, !=, >=, <=, >, <, contains, has_key. key ist dot-notiert
## (z.B. "count" oder "result.steps" — wird relativ zum Result aufgelöst).
func _expect_check(result: Variant, expect: Variant) -> Dictionary:
	if not (expect is Dictionary):
		return {"ok": false, "result": false, "error": "expect must be an object {key, op, value}"}
	var expect_data: Dictionary = expect
	var key := str(expect_data.get("key", ""))
	var op := str(expect_data.get("op", "=="))
	var expected: Variant = expect_data.get("value")
	var actual: Variant = _get_nested(result, key)
	var ok := false
	match op:
		"==": ok = actual == expected
		"!=": ok = actual != expected
		">=": ok = actual >= expected
		"<=": ok = actual <= expected
		">": ok = actual > expected
		"<": ok = actual < expected
		"contains":
			if actual is String and expected is String:
				ok = expected in actual
			elif actual is Array:
				ok = expected in actual
		"has_key":
			ok = actual is Dictionary and expected in actual
		_:
			ok = actual == expected
	return {"ok": true, "result": ok, "key": key, "op": op, "expected": expected, "actual": actual}


## Navigiert dot-notierte Pfade durch Dictionary/Array (wie der Test-Runner).
func _get_nested(data: Variant, key_path: String) -> Variant:
	if data == null or key_path == "":
		return data
	if not (data is Dictionary):
		return null
	var parts: PackedStringArray = key_path.split(".")
	var current: Variant = data
	for part in parts:
		if current is Dictionary:
			if not (current as Dictionary).has(part):
				return null
			current = (current as Dictionary)[part]
		elif current is Array:
			var idx: int = part.to_int()
			if idx < 0 or idx >= (current as Array).size():
				return null
			current = (current as Array)[idx]
		else:
			return null
	return current


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
		"--script", _resolve_preflight_path(),
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


## Löst den Preflight-Script-Pfad projektagnostisch auf.
## Default: SnipWar (scripts/preflight.gd). Andere Projekte setzen
## application/mcp/preflight_script in project.godot.
static func _resolve_preflight_path() -> String:
	var configured := str(ProjectSettings.get_setting("application/mcp/preflight_script", PREFLIGHT_PATH))
	if configured.begins_with("res://") or configured.begins_with("user://"):
		return configured
	return PREFLIGHT_PATH


# ═══════════════════════════════════════════════════════════════════════════
# Versionierte Chain-Manifeste (F5)
# ═══════════════════════════════════════════════════════════════════════════

## Löst das Manifest-Verzeichnis auf (application/mcp/chain_dir, Default
## res://addons/gdscript_mcp/mcp_chains).
static func _resolve_chain_dir() -> String:
	var configured := str(ProjectSettings.get_setting("application/mcp/chain_dir", CHAIN_DIR))
	if configured.begins_with("res://") or configured.begins_with("user://"):
		return configured
	return CHAIN_DIR


## Lädt und validiert ein Manifest (res://addons/gdscript_mcp/mcp_chains/<id>.json).
func load_manifest(chain_id: String) -> Dictionary:
	var id := chain_id.strip_edges()
	if id == "":
		return {"ok": false, "error": "chain_id must not be empty"}
	var dir := _resolve_chain_dir()
	var path := "%s/%s.json" % [dir, id]
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "chain manifest not found: " + id, "dir": dir}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "chain manifest unreadable: " + id}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {"ok": false, "error": "chain manifest is not valid JSON: " + id}
	var manifest_def: Dictionary = parsed
	if str(manifest_def.get("id", "")) == "":
		manifest_def["id"] = id
	var validation := validate_chain(manifest_def)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "error": "chain manifest failed validation: " + str(validation.get("errors", [])), "validation": validation}
	return {"ok": true, "def": manifest_def, "path": path}


## Listet alle Manifeste im Katalog auf (id, name, description, mode, steps).
func list_manifests() -> Dictionary:
	var dir := _resolve_chain_dir()
	var manifests: Array = []
	var da := DirAccess.open(dir)
	if da != null:
		da.list_dir_begin()
		var entry := da.get_next()
		while entry != "":
			if entry.ends_with(".json"):
				var path := "%s/%s" % [dir, entry]
				var file := FileAccess.open(path, FileAccess.READ)
				if file != null:
					var parsed: Variant = JSON.parse_string(file.get_as_text())
					file.close()
					if parsed is Dictionary:
						var def: Dictionary = parsed
						manifests.append({
							"id": str(def.get("id", entry.trim_suffix(".json"))),
							"name": str(def.get("name", "")),
							"description": str(def.get("description", "")),
							"mode": str(def.get("mode", "auto")),
							"step_count": int((def.get("steps", []) as Array).size()),
						})
			entry = da.get_next()
		da.list_dir_end()
	manifests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return {"ok": true, "count": manifests.size(), "manifests": manifests, "dir": dir}
