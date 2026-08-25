extends RefCounted
class_name McpCapabilityPlanner

## Slice A planner: discovery and visible read-only probes only.
## It never writes project files, editor state, or GameState.

const CONTRACTS_PATH := "res://addons/gdscript_mcp/runtime/autonomy/mcp_autonomy_contracts.gd"
const PROJECT_ADAPTER_PATH := "res://addons/gdscript_mcp/runtime/core/mcp_project_adapter.gd"
const ARCHIVE_PATH := "res://addons/gdscript_mcp/runtime/context/mcp_playthrough_archive.gd"

var _contracts: RefCounted
var _registry: RefCounted
var _lifecycle: RefCounted
var _context_store: RefCounted
var _project_adapter: Node
var _archive: RefCounted
var _catalog: Array = []
var _statuses: Dictionary = {}
var _last_receipt: Dictionary = {}
var _run_sequence := 0


func setup(registry: RefCounted, lifecycle: RefCounted = null, context_store: RefCounted = null) -> void:
	_registry = registry
	_lifecycle = lifecycle
	_context_store = context_store
	_contracts = load(CONTRACTS_PATH).new()
	_archive = null
	_project_adapter = _resolve_project_adapter()
	_refresh_catalog()


func get_tool_defs() -> Array:
	return [
		_make_tool("runtime_autonomy_capabilities", "Read normalized MCP capability metadata and gate status", {
			"include_invalid": {"type": "boolean", "default": true},
			"limit": {"type": "integer", "default": 256},
		}),
		_make_tool("runtime_autonomy_plan", "Select read-only MCP tools by verified preconditions and postconditions", {
			"intent": {"type": "string"},
			"required_outputs": {"type": "array", "items": {"type": "string"}},
			"mode": {"type": "string", "enum": ["visible", "headless", "any"], "default": "any"},
			"allow_probe": {"type": "boolean", "default": false},
		}, ["intent"]),
		_make_tool("runtime_autonomy_probe", "Run the planner-selected read-only visible capability probe and return a receipt", {
			"intent": {"type": "string"},
			"required_outputs": {"type": "array", "items": {"type": "string"}},
		}, ["intent"], true),
		_make_tool("runtime_autonomy_receipt", "Read the last Slice-A capability receipt", {
			"run_id": {"type": "string", "default": ""},
		}),
	]


func dispatch_tool(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"runtime_autonomy_capabilities":
			return capabilities(bool(args.get("include_invalid", true)), int(args.get("limit", 256)))
		"runtime_autonomy_plan":
			return plan(str(args.get("intent", "")), args.get("required_outputs", []) as Array, str(args.get("mode", "any")), bool(args.get("allow_probe", false)))
		"runtime_autonomy_receipt":
			return receipt(str(args.get("run_id", "")))
		"runtime_autonomy_probe":
			return {"error": "runtime_autonomy_probe is async; use the async dispatch path"}
		_:
			return {"error": "Unknown autonomy tool: " + tool_name}


func dispatch_async(tool_name: String, args: Dictionary) -> Variant:
	if tool_name != "runtime_autonomy_probe":
		return {"error": "Unknown async autonomy tool: " + tool_name}
	return await probe(str(args.get("intent", "")), args.get("required_outputs", []) as Array)


func capabilities(include_invalid: bool = true, limit: int = 256) -> Dictionary:
	_refresh_catalog()
	var entries: Array = []
	for item in _catalog:
		if include_invalid or bool(item.get("metadata_valid", false)):
			entries.append(item.duplicate(true))
	if entries.size() > maxi(0, limit):
		entries = entries.slice(0, maxi(0, limit))
	return {
		"contract_version": McpAutonomyContracts.CONTRACT_VERSION,
		"count": entries.size(),
		"capabilities": entries,
		"planner": "metadata_and_postcondition_based",
		"mutations_allowed": false,
	}


func plan(intent: String, required_outputs: Array = [], mode: String = "any", allow_probe: bool = false) -> Dictionary:
	_refresh_catalog()
	var run_id := _new_run_id()
	var normalized_intent := intent.strip_edges()
	if normalized_intent == "" and required_outputs.is_empty():
		var blocked: Dictionary = _contracts.error_receipt(run_id, "VALIDATION_ERROR", "intent or required_outputs is required")
		_last_receipt = blocked.duplicate(true)
		return blocked
	var requested := _normalize_strings(required_outputs)
	if normalized_intent == "":
		normalized_intent = "output selection"
	var candidates: Array = []
	var rejected: Array = []
	var selected: Array = []
	var available := _available_capabilities()
	for tool in _catalog:
		var name := str(tool.get("name", ""))
		var reasons: Array = []
		var metadata_errors: Array = _contracts.validate_tool_metadata(tool)
		if not metadata_errors.is_empty():
			reasons.append_array(metadata_errors)
		if bool(tool.get("mutates", false)):
			reasons.append("Slice A is read-only; mutating tool")
		if mode != "any" and str(tool.get("visibility", "")) != mode:
			reasons.append("visibility mismatch")
		var missing := _missing_requirements(tool, available)
		if not missing.is_empty():
			reasons.append("missing: " + ", ".join(missing))
		if not requested.is_empty() and not _produces_requested(tool, requested):
			reasons.append("does not produce requested output")
		var candidate := {
			"tool": name,
			"selected": reasons.is_empty(),
			"reasons": reasons,
			"requires": tool.get("requires", []),
			"produces": tool.get("produces", []),
			"postconditions": tool.get("postconditions", []),
			"evidence": tool.get("evidence", []),
			"cost": tool.get("cost", 0),
		}
		if reasons.is_empty():
			candidates.append(candidate)
		else:
			rejected.append(candidate)
	for candidate in candidates:
		if _candidate_matches_intent(candidate, intent, requested):
			selected.append(candidate)
	var verdict := "PASS" if not selected.is_empty() else "BLOCKED"
	var reason := "Selected by verified requirements, outputs, postconditions, and evidence" if verdict == "PASS" else "No tool satisfies the declared requirements and live prerequisites"
	var missing_capabilities := _collect_missing(rejected)
	var steps: Array = []
	for selected_candidate in selected:
		var tool := _tool_by_name(str(selected_candidate.get("tool", "")))
		steps.append(_contracts.make_step("%s_%02d" % [run_id, steps.size() + 1], tool))
	var receipt: Dictionary = _contracts.make_receipt(run_id, steps, verdict, reason, [{
		"kind": "planner_decision",
		"intent": intent,
		"available_capabilities": available,
		"candidate_count": candidates.size(),
		"rejected_count": rejected.size(),
		"allow_probe": allow_probe,
	}], missing_capabilities)
	receipt["selection"] = {
		"selected": selected,
		"rejected": rejected,
		"intent": intent,
		"required_outputs": requested,
		"mode": mode,
	}
	_last_receipt = receipt.duplicate(true)
	_status_for_receipt(receipt)
	return receipt


func probe(intent: String, required_outputs: Array = []) -> Dictionary:
	var planned := plan(intent, required_outputs, "visible", true)
	if str(planned.get("verdict", "")) != "PASS":
		return planned
	var run_id := str(planned.get("run_id", ""))
	var step_receipts: Array = []
	var observations: Array = []
	var failed := false
	var failure_reason := ""
	for raw_step in planned.get("steps", []):
		var step: Dictionary = raw_step
		var tool_name := str(step.get("tool", ""))
		var tool := _tool_by_name(tool_name)
		var before := _observe_environment()
		var result: Variant = await _probe_tool(tool_name, tool)
		var post := _check_postconditions(tool, result)
		var step_status := "PASS" if bool(post.get("ok", false)) else "QUARANTINED"
		var step_receipt := {
			"step_id": str(step.get("step_id", "")),
			"tool": tool_name,
			"preconditions": {"ok": true, "environment": before},
			"action": {"args": {}, "mutates": false},
			"observation": _bounded_value(result),
			"postconditions": post,
			"evidence": {"types": tool.get("evidence", []), "complete": bool(post.get("ok", false))},
			"verdict": step_status,
			"rollback": {"status": "not_required", "mutated": false},
		}
		step_receipts.append(step_receipt)
		observations.append({"tool": tool_name, "postconditions": post})
		if step_status != "PASS":
			failed = true
			failure_reason = "Postcondition failed for %s" % tool_name
			break
	var final_verdict := "QUARANTINED" if failed else "PASS"
	var final_receipt: Dictionary = _contracts.make_receipt(run_id, step_receipts, final_verdict, failure_reason if failed else "All selected read-only probes passed", observations, [])
	final_receipt["selection"] = planned.get("selection", {})
	final_receipt["probe"] = true
	_last_receipt = final_receipt.duplicate(true)
	_status_for_receipt(final_receipt)
	if _archive == null and ResourceLoader.exists(ARCHIVE_PATH):
		var archive_script: Resource = load(ARCHIVE_PATH)
		if archive_script != null:
			_archive = archive_script.new()
	if _archive != null:
		await _archive.log_success("autonomy_probe:" + intent, {"verdict": final_verdict, "steps": step_receipts.size(), "receipt": final_receipt}, null)
	return final_receipt


func receipt(run_id: String = "") -> Dictionary:
	if run_id == "" or str(_last_receipt.get("run_id", "")) == run_id:
		return _last_receipt.duplicate(true)
	return {"error": "Receipt not found", "run_id": run_id}


func _refresh_catalog() -> void:
	_catalog.clear()
	if _registry == null:
		return
	for raw in _registry.get_all_tools():
		if raw is Dictionary and not str(raw.get("name", "")).begins_with("runtime_autonomy_"):
			var normalized := McpAutonomyContracts.normalize_tool(raw, "registry")
			_catalog.append(normalized)
	for host_def in _host_tool_defs():
		_catalog.append(McpAutonomyContracts.normalize_tool(host_def, "host"))
	for def in get_tool_defs():
		var normalized := McpAutonomyContracts.normalize_tool(def, "autonomy")
		_catalog.append(normalized)


func _available_capabilities() -> Array:
	var available: Array = ["mcp_session", "lifecycle", "project_files", "code_analysis"]
	if _registry != null:
		available.append("input_scheduler")
		available.append("freeze_step")
		available.append("vision")
	if _lifecycle != null:
		available.append("lifecycle")
	if _context_store != null:
		available.append("context_store")
	if _project_adapter != null:
		available.append_array(["project_adapter", "scene_detection"])
	if _is_visible_renderer():
		available.append("visible_renderer")
		if _is_game_running():
			available.append("game_running")
	return _unique(available)


func _missing_requirements(tool: Dictionary, available: Array) -> Array:
	var missing: Array = []
	for requirement in tool.get("requires", []):
		if str(requirement) not in available:
			missing.append(str(requirement))
	return missing


func _produces_requested(tool: Dictionary, requested: Array) -> bool:
	for item in requested:
		if item in tool.get("produces", []):
			return true
	return false


func _candidate_matches_intent(candidate: Dictionary, intent: String, requested: Array) -> bool:
	if not requested.is_empty():
		return _produces_requested(candidate, requested)
	var needle := intent.to_lower()
	var name := str(candidate.get("tool", "")).to_lower()
	return needle == "" or needle in name or needle in JSON.stringify(candidate.get("produces", [])).to_lower() or needle in JSON.stringify(candidate.get("postconditions", [])).to_lower()


func _collect_missing(rejected: Array) -> Array:
	var missing: Array = []
	for item in rejected:
		for reason in item.get("reasons", []):
			var text := str(reason)
			if text.begins_with("missing: "):
				for capability in text.trim_prefix("missing: ").split(", "):
					if capability != "" and capability not in missing:
						missing.append(capability)
	return missing


func _probe_tool(tool_name: String, tool: Dictionary) -> Variant:
	if tool_name == "runtime_mcp_status":
		return _lifecycle.status({"planner": "slice_a", "mutations_allowed": false}) if _lifecycle != null else {"error": "lifecycle unavailable"}
	if tool_name == "runtime_mcp_events":
		return _lifecycle.events_since(0, 32) if _lifecycle != null else {"error": "lifecycle unavailable"}
	if bool(tool.get("async", false)):
		return await _registry.dispatch_async(tool_name, {})
	return _registry.dispatch(tool_name, {})


func _check_postconditions(tool: Dictionary, result: Variant) -> Dictionary:
	var checks: Array = []
	var is_dict := result is Dictionary
	for condition in tool.get("postconditions", []):
		var text := str(condition)
		var ok := is_dict and not (result as Dictionary).has("error")
		if text.contains("scene is present"):
			ok = ok and str((result as Dictionary).get("scene", "")) != ""
		elif text.contains("count is non-negative"):
			ok = ok and int((result as Dictionary).get("count", -1)) >= 0
		elif text.contains("tree_paused"):
			ok = ok and (result as Dictionary).has("tree_paused") and (result as Dictionary).has("frames_stepped")
		elif text.contains("active and bounds"):
			ok = ok and (result as Dictionary).has("active") and (result as Dictionary).has("bounds")
		elif text.contains("contexts and count"):
			ok = ok and (result as Dictionary).has("contexts") and (result as Dictionary).has("count")
		elif text.contains("scenarios is an array"):
			ok = ok and (result as Dictionary).get("scenarios", null) is Array
		elif text.contains("analysis fields"):
			ok = ok and (result as Dictionary).size() > 0
		elif text.contains("state is present"):
			ok = ok and (result as Dictionary).has("state") and (result as Dictionary).has("session_id")
		elif text.contains("entries is an array"):
			ok = ok and (result as Dictionary).get("entries", null) is Array
		elif text.contains("next_cursor"):
			ok = ok and (result as Dictionary).has("next_cursor")
		checks.append({"condition": text, "ok": ok})
	var all_ok := true
	for check in checks:
		if not bool(check.get("ok", false)):
			all_ok = false
	return {"ok": all_ok, "checks": checks}


func _host_tool_defs() -> Array:
	return [
		_make_tool("runtime_mcp_status", "Read MCP lifecycle and planner status", {}),
		_make_tool("runtime_mcp_events", "Read MCP lifecycle events", {"cursor": {"type": "integer", "default": 0}, "limit": {"type": "integer", "default": 32}}),
	]


func _status_for_receipt(receipt_data: Dictionary) -> void:
	for step in receipt_data.get("steps", []):
		var name := str(step.get("tool", ""))
		_statuses[name] = "PROBE_PASS" if str(receipt_data.get("verdict", "")) == "PASS" else "QUARANTINED"


func get_statuses() -> Dictionary:
	return _statuses.duplicate(true)


func _tool_by_name(name: String) -> Dictionary:
	for tool in _catalog:
		if str(tool.get("name", "")) == name:
			return tool
	return {}


func _resolve_project_adapter() -> Node:
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		return (tree as SceneTree).root.get_node_or_null("/root/McpProjectAdapter")
	return null


func _is_game_running() -> bool:
	var tree := Engine.get_main_loop()
	return tree is SceneTree and (tree as SceneTree).current_scene != null


func _is_visible_renderer() -> bool:
	if OS.has_feature("headless") or "--headless" in OS.get_cmdline_args():
		return false
	var tree := Engine.get_main_loop()
	if not tree is SceneTree or (tree as SceneTree).root == null:
		return false
	var texture := (tree as SceneTree).root.get_texture()
	return texture != null and texture.get_rid().is_valid()


func _has_capability(requirement: String) -> bool:
	if _registry == null:
		return false
	for tool in _registry.get_all_tools():
		if tool is Dictionary and requirement in McpAutonomyContracts.normalize_tool(tool).get("produces", []):
			return true
	return false


func _observe_environment() -> Dictionary:
	return {
		"renderer": "visible" if _is_visible_renderer() else "unavailable",
		"game_running": _is_game_running(),
		"session_id": _lifecycle.status().get("session_id", "") if _lifecycle != null else "",
		"project_id": _project_adapter.project_id if _project_adapter != null else "",
	}


func _bounded_value(value: Variant) -> Variant:
	var encoded := JSON.stringify(value)
	if encoded.length() <= 16000:
		return value
	return {"truncated": true, "size": encoded.length(), "preview": encoded.substr(0, 15000)}


func _new_run_id() -> String:
	_run_sequence += 1
	return "autonomy_%d_%d" % [Time.get_ticks_msec(), _run_sequence]


func _normalize_strings(values: Array) -> Array:
	var result: Array = []
	for value in values:
		var text := str(value).strip_edges()
		if text != "" and text not in result:
			result.append(text)
	return result


func _unique(values: Array) -> Array:
	var result: Array = []
	for value in values:
		if value not in result:
			result.append(value)
	return result


static func _make_tool(name: String, description: String, properties: Dictionary = {}, required: Array = [], async_tool: bool = false) -> Dictionary:
	var schema := {"type": "object", "properties": properties}
	if not required.is_empty():
		schema["required"] = required
	var tool := {"name": name, "description": description, "inputSchema": schema}
	if async_tool:
		tool["_async"] = true
	return tool
