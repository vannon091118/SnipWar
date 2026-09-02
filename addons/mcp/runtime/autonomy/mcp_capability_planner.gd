extends RefCounted
class_name McpCapabilityPlanner

## Slice A planner: discovery and visible read-only probes.
## Slice D: journaled edit-workspace tools (read/write/patch/rollback), gated
## behind set_mutations_allowed — writes stay inside user://mcp_workspaces and
## are preimaged + rollbackable. Probes always stay read-only.

const CONTRACTS_PATH := "res://addons/gdscript_mcp/runtime/autonomy/mcp_autonomy_contracts.gd"
const PROJECT_ADAPTER_PATH := "res://addons/gdscript_mcp/runtime/core/mcp_project_adapter.gd"
const ARCHIVE_PATH := "res://addons/gdscript_mcp/runtime/context/mcp_playthrough_archive.gd"
const WORKSPACE_JOURNAL_PATH := "res://addons/gdscript_mcp/runtime/autonomy/mcp_workspace_journal.gd"
const PROJECT_TOOLS_PATH := "res://addons/gdscript_mcp/runtime/autonomy/mcp_project_tools.gd"

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
var _workspace_journal: RefCounted = null
var _workspace_tools: RefCounted = null
var _mutations_allowed := false
var _session_id := ""
var _project_id := ""


func setup(registry: RefCounted, lifecycle: RefCounted = null, context_store: RefCounted = null) -> void:
	_registry = registry
	_lifecycle = lifecycle
	_context_store = context_store
	_contracts = load(CONTRACTS_PATH).new()
	_archive = null
	_project_adapter = _resolve_project_adapter()
	_session_id = _resolve_session_id()
	_project_id = _resolve_project_id()
	_refresh_catalog()


## Slice D write gate: mutating tools stay disabled unless the host enables
## them explicitly (runtime_autonomy_* writes are journaled + rollbackable).
func set_mutations_allowed(allowed: bool) -> void:
	_mutations_allowed = allowed


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
		_make_workspace_tool("runtime_autonomy_workspace_begin", "Begin an isolated journaled run workspace under user://mcp_workspaces", {
			"project_id": {"type": "string", "default": ""},
			"session_id": {"type": "string", "default": ""},
			"renderer": {"type": "string", "enum": ["visible", "headless", "auto"], "default": "auto"},
		}, "write"),
		_make_workspace_tool("runtime_autonomy_workspace_status", "Read the bound workspace state, baseline and transaction counts", {}, "read"),
		_make_workspace_tool("runtime_autonomy_workspace_files", "List files in the bound workspace", {}, "read"),
		_make_workspace_tool("runtime_autonomy_workspace_baseline", "Verify the workspace against its run-start baseline fingerprint", {}, "read"),
		_make_workspace_tool("runtime_autonomy_workspace_end", "Finish the run (refuses uncommitted transactions)", {}, "read"),
		_make_workspace_tool("runtime_autonomy_read", "Read a res:// or user:// file with hash and byte count", {
			"path": {"type": "string"},
		}, "read", ["path"]),
		_make_workspace_tool("runtime_autonomy_write", "Journaled write inside the workspace root only", {
			"path": {"type": "string"},
			"content": {"type": "string"},
			"expected_hash": {"type": "string", "default": ""},
		}, "write", ["path", "content"]),
		_make_workspace_tool("runtime_autonomy_patch", "Fail-closed single-occurrence patch inside the workspace root", {
			"path": {"type": "string"},
			"old_text": {"type": "string"},
			"new_text": {"type": "string"},
			"expected_hash": {"type": "string", "default": ""},
		}, "write", ["path", "old_text", "new_text"]),
		_make_workspace_tool("runtime_autonomy_search", "Text search across workspace files", {
			"needle": {"type": "string"},
			"limit": {"type": "integer", "default": 50},
		}, "read", ["needle"]),
		_make_workspace_tool("runtime_autonomy_symbols", "Detect GDScript classes, funcs, vars and consts in a file", {
			"path": {"type": "string"},
		}, "read", ["path"]),
		_make_workspace_tool("runtime_autonomy_rollback", "Roll back a single journaled transaction", {
			"transaction_id": {"type": "string"},
		}, "write", ["transaction_id"]),
		_make_workspace_tool("runtime_autonomy_rollback_all", "Roll back all journaled transactions to the baseline", {}, "write"),
		_make_workspace_tool("runtime_autonomy_workspace_import", "Copy a res:// project file into the workspace for safe editing", {
			"path": {"type": "string"},
		}, "write", ["path"]),
		_make_workspace_tool("runtime_autonomy_export", "Validate and apply an imported change back to the project (apply=true required)", {
			"path": {"type": "string"},
			"apply": {"type": "boolean", "default": false},
			"force": {"type": "boolean", "default": false},
		}, "write", ["path"], true),
		_make_workspace_tool("runtime_autonomy_imports", "List files imported into the workspace", {}, "read"),
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
		"runtime_autonomy_workspace_begin":
			return workspace_begin(args)
		"runtime_autonomy_workspace_status":
			return workspace_status()
		"runtime_autonomy_workspace_files":
			return workspace_files()
		"runtime_autonomy_workspace_baseline":
			return workspace_baseline()
		"runtime_autonomy_workspace_end":
			return workspace_end()
		"runtime_autonomy_read":
			return workspace_read(str(args.get("path", "")))
		"runtime_autonomy_write":
			return workspace_write(str(args.get("path", "")), str(args.get("content", "")), str(args.get("expected_hash", "")))
		"runtime_autonomy_patch":
			return workspace_patch(str(args.get("path", "")), str(args.get("old_text", "")), str(args.get("new_text", "")), str(args.get("expected_hash", "")))
		"runtime_autonomy_search":
			return workspace_search(str(args.get("needle", "")), int(args.get("limit", 50)))
		"runtime_autonomy_symbols":
			return workspace_symbols(str(args.get("path", "")))
		"runtime_autonomy_rollback":
			return workspace_rollback(str(args.get("transaction_id", "")))
		"runtime_autonomy_rollback_all":
			return workspace_rollback_all()
		"runtime_autonomy_workspace_import":
			return workspace_import(str(args.get("path", "")))
		"runtime_autonomy_export":
			return workspace_export(str(args.get("path", "")), bool(args.get("apply", false)), bool(args.get("force", false)))
		"runtime_autonomy_imports":
			return workspace_imports()
		_:
			return {"error": "Unknown autonomy tool: " + tool_name}


func dispatch_async(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"runtime_autonomy_probe":
			return await probe(str(args.get("intent", "")), args.get("required_outputs", []) as Array)
		"runtime_autonomy_export":
			return await workspace_export(str(args.get("path", "")), bool(args.get("apply", false)), bool(args.get("force", false)))
		_:
			return dispatch_tool(tool_name, args)


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
		"mutations_allowed": _mutations_allowed,
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
			if allow_probe:
				reasons.append("probe is read-only")
			elif not _mutations_allowed:
				reasons.append("mutations not authorized")
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


## ────────────────────────────────────────────────────────────────────
## Slice D: journaled edit workspace (gated behind mutations_allowed)
## ────────────────────────────────────────────────────────────────────

func workspace_begin(args: Dictionary) -> Dictionary:
	if not _mutations_allowed:
		return _blocked("writes are disabled for this session", "BLOCKED")
	if _workspace_journal != null and _workspace_journal.is_bound():
		return _blocked("workspace already bound; end or roll back first", "BLOCKED")
	var journal_script: Resource = load(WORKSPACE_JOURNAL_PATH)
	var tools_script: Resource = load(PROJECT_TOOLS_PATH)
	if journal_script == null or tools_script == null:
		return _blocked("workspace modules unavailable", "MCP_ISSUE")
	_workspace_journal = journal_script.new()
	_workspace_tools = tools_script.new()
	var session_id := str(args.get("session_id", ""))
	if session_id == "":
		session_id = _session_id
	var project_id := str(args.get("project_id", ""))
	if project_id == "":
		project_id = _project_id
	var renderer := str(args.get("renderer", "auto"))
	if renderer == "auto":
		renderer = "visible" if _is_visible_renderer() else "headless"
	_workspace_journal.begin_run(project_id, session_id, renderer, OS.get_process_id())
	if not _workspace_journal.is_bound():
		_workspace_journal = null
		_workspace_tools = null
		return _blocked("workspace begin failed", "MCP_ISSUE")
	_workspace_tools.setup(str(_workspace_journal.root_path), session_id, _workspace_journal)
	return {"ok": true, "workspace": _workspace_journal.status(), "session_id": session_id}


func workspace_status() -> Dictionary:
	if _workspace_journal == null or not _workspace_journal.is_bound():
		return _blocked("no workspace bound", "BLOCKED")
	return {"ok": true, "workspace": _workspace_journal.status()}


func workspace_files() -> Dictionary:
	if _workspace_journal == null or not _workspace_journal.is_bound():
		return _blocked("no workspace bound", "BLOCKED")
	var files: Array = _workspace_journal.list_workspace_files()
	return {"ok": true, "files": files, "count": files.size()}


func workspace_baseline() -> Dictionary:
	if _workspace_journal == null or not _workspace_journal.is_bound():
		return _blocked("no workspace bound", "BLOCKED")
	var result: Dictionary = _workspace_journal.verify_baseline(_session_id)
	result["ok"] = bool(result.get("clean", false))
	return result


func workspace_end() -> Dictionary:
	if _workspace_journal == null or not _workspace_journal.is_bound():
		return _blocked("no workspace bound", "BLOCKED")
	var finish_result: Dictionary = _workspace_journal.finish(_session_id)
	if not bool(finish_result.get("ok", false)):
		return finish_result
	var status_data: Dictionary = _workspace_journal.status()
	_workspace_journal = null
	_workspace_tools = null
	return {"ok": true, "workspace": status_data, "ended": true}


func workspace_read(path_string: String) -> Dictionary:
	var tools := _ensure_tools()
	if tools == null:
		return _blocked("workspace tools unavailable", "MCP_ISSUE")
	return tools.read(path_string)


func workspace_write(path_string: String, content: String, expected_hash: String = "") -> Dictionary:
	var gate := _write_gate()
	if not bool(gate.get("ok", false)):
		return gate
	return _workspace_tools.write(path_string, content, expected_hash, _session_id)


func workspace_patch(path_string: String, old_text: String, new_text: String, expected_hash: String = "") -> Dictionary:
	var gate := _write_gate()
	if not bool(gate.get("ok", false)):
		return gate
	return _workspace_tools.patch_content(path_string, old_text, new_text, expected_hash, _session_id)


func workspace_search(needle: String, limit: int = 50) -> Dictionary:
	if _workspace_tools == null or not _workspace_tools.is_workspace_bound():
		return _blocked("no workspace bound; search is scoped to the workspace", "BLOCKED")
	return _workspace_tools.search(needle, limit)


func workspace_symbols(path_string: String) -> Dictionary:
	var tools := _ensure_tools()
	if tools == null:
		return _blocked("workspace tools unavailable", "MCP_ISSUE")
	return tools.find_symbols(path_string)


func workspace_rollback(transaction_id: String) -> Dictionary:
	var gate := _write_gate()
	if not bool(gate.get("ok", false)):
		return gate
	return _workspace_tools.rollback_transaction(transaction_id, _session_id)


func workspace_rollback_all() -> Dictionary:
	var gate := _write_gate()
	if not bool(gate.get("ok", false)):
		return gate
	return _workspace_journal.rollback_all(_session_id)


func workspace_import(path_string: String) -> Dictionary:
	var gate := _write_gate()
	if not bool(gate.get("ok", false)):
		return gate
	return _workspace_tools.import_file(path_string)


func workspace_export(path_string: String, apply: bool = false, force: bool = false) -> Dictionary:
	var gate := _write_gate()
	if not bool(gate.get("ok", false)):
		return gate
	return _workspace_tools.export_file(path_string, apply, force)


func workspace_imports() -> Dictionary:
	if _workspace_tools == null or not _workspace_tools.is_workspace_bound():
		return _blocked("no workspace bound", "BLOCKED")
	return _workspace_tools.list_imports()


func _write_gate() -> Dictionary:
	if not _mutations_allowed:
		return _blocked("writes are disabled for this session", "BLOCKED")
	if _workspace_tools == null or not _workspace_tools.is_workspace_bound():
		return _blocked("no workspace bound; begin a workspace first", "BLOCKED")
	return {"ok": true}


func _ensure_tools() -> RefCounted:
	if _workspace_tools == null:
		var tools_script: Resource = load(PROJECT_TOOLS_PATH)
		if tools_script != null:
			_workspace_tools = tools_script.new()
	return _workspace_tools


func _blocked(reason: String, error_class: String) -> Dictionary:
	return {"ok": false, "error": reason, "error_class": error_class}


func _resolve_session_id() -> String:
	if _lifecycle != null and _lifecycle.has_method("status"):
		var lifecycle_status: Dictionary = _lifecycle.status()
		var sid := str(lifecycle_status.get("session_id", ""))
		if sid != "":
			return sid
	return "autonomy_%d" % Time.get_ticks_msec()


func _resolve_project_id() -> String:
	if _project_adapter != null:
		return str(_project_adapter.project_id)
	var configured_name := str(ProjectSettings.get_setting("application/config/name", "godot_project"))
	return configured_name.strip_edges().to_lower().replace(" ", "_") if configured_name != "" else "godot_project"


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
	if _workspace_tools != null and _workspace_tools.is_workspace_bound():
		available.append("workspace_bound")
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
	if not (tree is SceneTree):
		return null
	var root := (tree as SceneTree).root
	var configured_path := str(ProjectSettings.get_setting("application/mcp/project_adapter_node", "/root/McpProjectAdapter"))
	if configured_path.begins_with("/"):
		var configured := root.get_node_or_null(NodePath(configured_path))
		if configured != null:
			return configured
	return root.find_child("McpProjectAdapter", true, false)


## Siehe mcp_server.gd::_is_game_running — gleiche Logik. Der Runtime-Server
## läuft seit OFFEN-1 immer IM Spielprozess (current_scene entscheidet); der
## EditorInterface-Fallback ist nur defensives Netz.
func _is_game_running() -> bool:
	var main_loop := Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return false
	var tree: SceneTree = main_loop as SceneTree
	if tree.current_scene != null:
		return true
	# Editor-Prozess-Fallback (defensiv, analog zu mcp_server.gd).
	if not Engine.is_editor_hint():
		return false
	if not ClassDB.class_exists("EditorInterface"):
		return false
	var ei: Object = Engine.get_singleton("EditorInterface") if Engine.has_singleton("EditorInterface") else null
	if ei == null:
		return false
	if ei.has_method("is_playing_scene") and bool(ei.call("is_playing_scene")):
		return true
	return false


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
		"project_id": str(_project_adapter.get("project_id")) if _project_adapter != null and _project_adapter.get("project_id") != null else _project_id,
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


static func _make_workspace_tool(name: String, description: String, properties: Dictionary = {}, access: String = "read", required: Array = [], async_tool: bool = false) -> Dictionary:
	var schema := {"type": "object", "properties": properties}
	if not required.is_empty():
		schema["required"] = required
	var is_write := access == "write"
	var tool := {"name": name, "description": description, "inputSchema": schema}
	tool["access"] = access
	tool["scope"] = "runtime"
	tool["visibility"] = "visible"
	tool["mode"] = "runtime_visible"
	tool["mutates"] = is_write
	tool["rollback"] = "journal_rollback" if is_write else "none"
	# Starting a workspace creates the journal that later write tools require;
	# requiring workspace_bound here would make the first step unplannable.
	if name == "runtime_autonomy_workspace_begin":
		tool["requires"] = ["mcp_session"]
		tool["produces"] = ["workspace_bound"]
		tool["postconditions"] = ["result.ok is present", "workspace is bound"]
	else:
		tool["requires"] = ["mcp_session"] if not is_write else ["mcp_session", "workspace_bound"]
		tool["produces"] = ["file_content"] if not is_write else ["file_change"]
		tool["postconditions"] = ["result is a dictionary", "result.error is absent"] if not is_write else ["result.ok is present", "transaction journaled"]
	tool["evidence"] = ["tool_response"]
	tool["cost"] = 2
	if async_tool:
		tool["_async"] = true
	return tool
