extends RefCounted
class_name McpAutonomyContracts

## Versioned contracts shared by capability discovery and future chain slices.
## Slice A is read-only: these helpers describe and verify work; they do not
## authorize project or editor mutations.

const CONTRACT_VERSION := "mcp.autonomy.v1"
const RECEIPT_VERSION := "mcp.receipt.v1"
const ERROR_CLASSES := [
	"VALIDATION_ERROR",
	"MCP_ISSUE",
	"GAME_ISSUE",
	"TIMEOUT",
	"BLOCKED",
	"ROLLBACK_FAILED",
]
const VERDICTS := ["PASS", "FAIL", "BLOCKED", "QUARANTINED"]
const ACCESS_MODES := ["read", "write"]
const VISIBILITY_MODES := ["visible", "headless"]
const SCOPES := ["runtime", "editor"]


static func normalize_tool(definition: Dictionary, source: String = "registry") -> Dictionary:
	var tool := definition.duplicate(true)
	var name := str(tool.get("name", ""))
	var inferred := _infer_metadata(name, tool)
	for key in inferred:
		if not tool.has(key):
			tool[key] = inferred[key]
	tool["autonomy_contract_version"] = CONTRACT_VERSION
	tool["metadata_valid"] = validate_tool_metadata(tool).is_empty()
	tool["metadata_source"] = source
	return tool


static func validate_tool_metadata(tool: Dictionary) -> Array:
	var errors: Array = []
	var name := str(tool.get("name", "")).strip_edges()
	if name == "":
		errors.append("missing name")
	var input_schema: Variant = tool.get("inputSchema", {})
	if not (input_schema is Dictionary) or str(input_schema.get("type", "")) != "object":
		errors.append("inputSchema must be an object schema")
	var access := str(tool.get("access", ""))
	if access not in ACCESS_MODES:
		errors.append("access must be read or write")
	var scope := str(tool.get("scope", ""))
	if scope not in SCOPES:
		errors.append("scope must be runtime or editor")
	var visibility := str(tool.get("visibility", ""))
	if visibility not in VISIBILITY_MODES:
		errors.append("visibility must be visible or headless")
	if str(tool.get("mode", "")) == "":
		errors.append("missing mode")
	if not (tool.get("requires", []) is Array):
		errors.append("requires must be an array")
	if not (tool.get("produces", []) is Array) or (tool.get("produces", []) as Array).is_empty():
		errors.append("produces must be a non-empty array")
	if not (tool.get("postconditions", []) is Array) or (tool.get("postconditions", []) as Array).is_empty():
		errors.append("postconditions must be a non-empty array")
	if not (tool.get("evidence", []) is Array) or (tool.get("evidence", []) as Array).is_empty():
		errors.append("evidence must be a non-empty array")
	if not (tool.get("mutates", false) is bool):
		errors.append("mutates must be boolean")
	if not (tool.get("async", false) is bool):
		errors.append("async must be boolean")
	if not (tool.get("cost", -1) is int) or int(tool.get("cost", -1)) < 0:
		errors.append("cost must be a non-negative integer")
	if str(tool.get("rollback", "")) == "":
		errors.append("missing rollback rule")
	if bool(tool.get("mutates", false)) and str(tool.get("rollback", "none")) == "none":
		errors.append("mutating tools require a rollback rule")
	return errors


static func make_step(step_id: String, tool: Dictionary, args: Dictionary = {}) -> Dictionary:
	return {
		"contract_version": CONTRACT_VERSION,
		"step_id": step_id,
		"tool": str(tool.get("name", "")),
		"args": args.duplicate(true),
		"access": str(tool.get("access", "")),
		"scope": str(tool.get("scope", "")),
		"mode": str(tool.get("mode", "")),
		"requires": (tool.get("requires", []) as Array).duplicate(true),
		"produces": (tool.get("produces", []) as Array).duplicate(true),
		"postconditions": (tool.get("postconditions", []) as Array).duplicate(true),
		"evidence": (tool.get("evidence", []) as Array).duplicate(true),
		"mutates": bool(tool.get("mutates", false)),
		"rollback": str(tool.get("rollback", "")),
		"async": bool(tool.get("async", false)),
		"cost": int(tool.get("cost", 0)),
	}


static func make_receipt(run_id: String, steps: Array, verdict: String, reason: String = "", observations: Array = [], missing: Array = []) -> Dictionary:
	var normalized_verdict := verdict if verdict in VERDICTS else "FAIL"
	return {
		"receipt_version": RECEIPT_VERSION,
		"receipt_id": "%s_receipt" % run_id,
		"run_id": run_id,
		"created_at": Time.get_unix_time_from_system(),
		"verdict": normalized_verdict,
		"reason": reason,
		"steps": steps.duplicate(true),
		"observations": observations.duplicate(true),
		"missing_capabilities": missing.duplicate(true),
		"evidence": {
			"types": ["tool_response", "capability_catalog", "planner_decision"],
			"complete": normalized_verdict == "PASS",
		},
		"rollback": {"status": "not_required", "mutations": false},
	}


static func error_receipt(run_id: String, error_class: String, reason: String, missing: Array = []) -> Dictionary:
	var safe_class := error_class if error_class in ERROR_CLASSES else "VALIDATION_ERROR"
	return make_receipt(run_id, [], "BLOCKED" if safe_class == "BLOCKED" else "FAIL", reason, [{
		"error_class": safe_class,
		"complete": false,
	}], missing)


static func _infer_metadata(name: String, tool: Dictionary) -> Dictionary:
	var scope := "editor" if name.begins_with("editor_") else "runtime"
	var access := "write" if _looks_mutating(name, tool) else "read"
	var visibility := "headless" if name in ["runtime_mcp_status", "runtime_mcp_events", "runtime_analyze_project", "runtime_analyze_input", "runtime_analyze_signals", "runtime_analyze_game_state"] else "visible"
	var async_tool := bool(tool.get("_async", false))
	var produces := _default_produces(name)
	var postconditions := _default_postconditions(name)
	var requires := _default_requires(name)
	var evidence := _default_evidence(name)
	var rollback := "none" if access == "read" else "contract_required"
	return {
		"access": access,
		"scope": scope,
		"visibility": visibility,
		"mode": "%s_%s" % [scope, visibility],
		"requires": requires,
		"produces": produces,
		"postconditions": postconditions,
		"evidence": evidence,
		"mutates": access == "write",
		"rollback": rollback,
		"async": async_tool,
		"cost": _default_cost(name),
	}


static func _looks_mutating(name: String, tool: Dictionary) -> bool:
	if bool(tool.get("mutates", false)):
		return true
	for verb in ["click", "key", "drag", "move", "play", "stop", "set_", "create", "delete", "save", "apply", "undo", "redo", "run"]:
		if name.contains(verb) and not name in ["runtime_goal_check", "runtime_e2e_list", "runtime_playthrough_search", "runtime_playthrough_latest", "runtime_playthrough_stats", "runtime_playthrough_frames", "runtime_playthrough_compare"]:
			return true
	return false


static func _default_requires(name: String) -> Array:
	if name == "runtime_mcp_status":
		return ["mcp_session"]
	if name == "runtime_mcp_events":
		return ["mcp_session", "lifecycle"]
	if name.begins_with("runtime_ux_") or name.begins_with("runtime_goal_") or name.begins_with("runtime_e2e_"):
		return ["game_running", "visible_renderer"]
	if name in ["runtime_screenshot", "runtime_get_pixel", "runtime_detect_text_regions"]:
		return ["game_running", "visible_renderer", "vision"]
	if name == "runtime_virtual_mouse_status" or name == "runtime_mouse_move":
		return ["input_scheduler"]
	if name.begins_with("runtime_freeze") or name.begins_with("runtime_step"):
		return ["game_running", "freeze_step"]
	if name.begins_with("runtime_context_"):
		return ["context_store"]
	if name.begins_with("runtime_analyze_"):
		return ["project_files", "code_analysis"]
	if name.begins_with("game_"):
		return ["game_running", "project_adapter"]
	return []


static func _default_produces(name: String) -> Array:
	if name == "runtime_ux_scan":
		return ["scene_observation", "control_rects", "interactables"]
	if name == "runtime_freeze_status":
		return ["freeze_observation"]
	if name == "runtime_virtual_mouse_status":
		return ["input_observation"]
	if name == "runtime_context_list":
		return ["artifact_catalog"]
	if name == "runtime_e2e_list":
		return ["scenario_catalog"]
	if name.begins_with("runtime_analyze_"):
		return ["code_observation"]
	if name == "runtime_mcp_status":
		return ["lifecycle_observation", "capability_observation"]
	if name == "runtime_mcp_events":
		return ["lifecycle_events"]
	if name.begins_with("runtime_goal_"):
		return ["goal_observation"]
	if name.begins_with("runtime_ux_"):
		return ["ux_observation"]
	return ["tool_observation"]


static func _default_postconditions(name: String) -> Array:
	if name == "runtime_ux_scan":
		return ["result.scene is present", "result.control_count is non-negative"]
	if name == "runtime_freeze_status":
		return ["result contains tree_paused and frames_stepped"]
	if name == "runtime_virtual_mouse_status":
		return ["result contains active and bounds"]
	if name == "runtime_context_list":
		return ["result contains contexts and count"]
	if name == "runtime_e2e_list":
		return ["result.scenarios is an array"]
	if name.begins_with("runtime_analyze_"):
		return ["result is a dictionary with analysis fields"]
	if name == "runtime_mcp_status":
		return ["result.state is present", "result.session_id is present"]
	if name == "runtime_mcp_events":
		return ["result.entries is an array", "result.next_cursor is present"]
	return ["result is a dictionary", "result.error is absent"]


static func _default_evidence(name: String) -> Array:
	var evidence := ["tool_response"]
	if name.begins_with("runtime_ux_") or name.begins_with("runtime_goal_"):
		evidence.append("scene_tree")
	if name == "runtime_screenshot":
		evidence.append("screenshot_artifact")
	if name.begins_with("runtime_analyze_"):
		evidence.append("code_analysis")
	return evidence


static func _default_cost(name: String) -> int:
	if name == "runtime_screenshot" or name == "runtime_ux_analyze":
		return 4
	if name.begins_with("runtime_analyze_"):
		return 2
	if name.begins_with("runtime_wait_") or name.begins_with("runtime_e2e_"):
		return 3
	return 1
