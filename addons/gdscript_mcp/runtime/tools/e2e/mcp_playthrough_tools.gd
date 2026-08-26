extends RefCounted
class_name McpPlaythroughTools

## Agent-facing playthrough API: expose the archive (success store) as MCP
## tools so the agent can actively drive and resume a full game run over time.

const ARCHIVE_PATH := "res://addons/gdscript_mcp/runtime/context/mcp_playthrough_archive.gd"
const VISION_PATH := "res://addons/gdscript_mcp/runtime/tools/vision/mcp_vision.gd"

var _archive: RefCounted
var _registry: RefCounted


func set_registry(registry: RefCounted) -> void:
	_registry = registry


func _ensure_archive() -> bool:
	if _archive != null:
		return true
	var script: Resource = load(ARCHIVE_PATH)
	if script == null:
		return false
	_archive = script.new()
	return _archive != null


func _archive_result(method: String, args: Array) -> Variant:
	if not _ensure_archive():
		return {"error": "archive unavailable"}
	return _archive.callv(method, args)


func dispatch_tool(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"runtime_playthrough_search":
			return _archive_result("search", [str(args.get("query", "")), int(args.get("limit", 20))])
		"runtime_playthrough_latest":
			return _archive_result("latest", [int(args.get("limit", 10))])
		"runtime_playthrough_stats":
			return _archive_result("stats", [])
		"runtime_playthrough_frames":
			return _archive_result("frames", [int(args.get("limit", 8))])
		"runtime_playthrough_preset_load":
			return _archive_result("apply_snapshot", [str(args.get("entry_id", ""))])
		_:
			return {"error": "Unknown playthrough tool: " + tool_name}


func dispatch_async(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"runtime_playthrough_success":
			if not _ensure_archive():
				return {"error": "archive unavailable"}
			return await _archive.log_success(str(args.get("action", "")), args.get("meta", {}), null)
		"runtime_playthrough_record":
			return await _record_step(args)
		"runtime_playthrough_compare":
			return await _compare_presets(
				str(args.get("baseline_preset_id", "")),
				str(args.get("action_tool", "")),
				args.get("action_args", {}))
		_:
			return {"error": "Unknown async playthrough tool: " + tool_name}


static func get_tool_defs() -> Array:
	return [
		_make("runtime_playthrough_record", "Record a step verdict into the playthrough archive (TO_CHECK, SOLVED, MCP_ISSUE, GAME_ISSUE, BLOCKED, FAIL)",
			{"action": {"type": "string", "description": "Step identifier (e.g. 'mainmenu_neues_spiel')"}, "verdict": {"type": "string", "description": "TO_CHECK | SOLVED | MCP_ISSUE | GAME_ISSUE | BLOCKED | FAIL"}, "reason": {"type": "string", "default": ""}, "solved_count": {"type": "integer", "default": 0}, "fail_count": {"type": "integer", "default": 0}}, ["action", "verdict"], true),
		_make("runtime_playthrough_success", "Record a successful game action into the local playthrough archive (action, optional meta/snapshot)",
			{"action": {"type": "string"}, "meta": {"type": "object", "default": {}}}, ["action"], true),
		_make("runtime_playthrough_search", "Search successful actions in the archive (persistent across runs)",
			{"query": {"type": "string", "default": ""}, "limit": {"type": "integer", "default": 20}}),
		_make("runtime_playthrough_latest", "Latest successful actions (newest first) to continue a playthrough",
			{"limit": {"type": "integer", "default": 10}}),
		_make("runtime_playthrough_stats", "Archive stats: entry count, action histogram, root path"),
		_make("runtime_playthrough_frames", "Recent snapshot frames (PNG paths) for image-based play",
			{"limit": {"type": "integer", "default": 8}}),
		_make("runtime_playthrough_preset_load", "Restore a stored GameState snapshot (reproducible situation)",
			{"entry_id": {"type": "string"}}, ["entry_id"]),
		_make("runtime_playthrough_compare", "A/B compare: load baseline preset, execute action, compare screenshots + state",
			{"baseline_preset_id": {"type": "string"}, "action_tool": {"type": "string", "description": "Tool name to execute (e.g. runtime_ux_click)"}, "action_args": {"type": "object", "description": "Arguments for the action tool"}}, ["baseline_preset_id", "action_tool"], true),
	]


static func _make(tool_name: String, description: String, properties: Dictionary = {}, required: Array = [], async_tool: bool = false) -> Dictionary:
	var schema := {"type": "object", "properties": properties}
	if not required.is_empty():
		schema["required"] = required
	var tool := {"name": tool_name, "description": description, "inputSchema": schema}
	if async_tool:
		tool["_async"] = true
	return tool


## A/B compare: restore a baseline preset, capture pre-state, execute an
## action, capture post-state, then diff screenshots and state fingerprints.
func _compare_presets(baseline_preset_id: String, action_tool: String, action_args: Dictionary) -> Dictionary:
	if not _ensure_archive():
		return {"error": "archive unavailable"}
	if _registry == null:
		return {"error": "tool registry not available — set_registry() required"}

	# Load baseline preset
	var load_result: Dictionary = _archive.apply_snapshot(baseline_preset_id)
	if not bool(load_result.get("ok", false)):
		return {"error": "Failed to load baseline preset", "detail": load_result}

	# Allow world to reconnect before capturing
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		for _i in range(4):
			await (tree as SceneTree).process_frame

	# Capture pre-state screenshot
	var vision_script: Resource = load(VISION_PATH)
	if vision_script == null:
		return {"error": "Vision module not available"}
	var vision: RefCounted = vision_script.new()
	var pre_screenshot: Dictionary = await vision.capture_screenshot("png", false)
	var pre_state_fingerprint := _state_fingerprint()

	# Execute the action
	var action_result: Variant
	if action_tool != "":
		if _registry.has_method("dispatch_async"):
			action_result = await _registry.dispatch_async(action_tool, action_args)
		else:
			action_result = _registry.dispatch(action_tool, action_args)

	# Allow action to settle
	if tree is SceneTree:
		for _i in range(4):
			await (tree as SceneTree).process_frame

	# Capture post-state screenshot
	var post_screenshot: Dictionary = await vision.capture_screenshot("png", false)
	var post_state_fingerprint := _state_fingerprint()

	# Visual diff: McpVision keeps the previous in-memory frame when the post
	# capture commits, so no image bytes need to cross the MCP boundary.
	var visual_diff := {"stable": true, "changed_pixels": 0, "change_ratio": 0.0, "hotspots": []}
	if not pre_screenshot.has("error") and not post_screenshot.has("error") and vision.has_method("image_diff"):
		visual_diff = vision.image_diff("", 0)

	# State fingerprint diff
	var state_diff := {
		"pre": pre_state_fingerprint,
		"post": post_state_fingerprint,
		"changed": pre_state_fingerprint != post_state_fingerprint,
	}

	return {
		"baseline_preset": baseline_preset_id,
		"action": action_tool,
		"action_result": action_result,
		"visual_diff": visual_diff,
		"state_diff": state_diff,
		"pre": {"width": pre_screenshot.get("width", 0), "height": pre_screenshot.get("height", 0)},
		"post": {"width": post_screenshot.get("width", 0), "height": post_screenshot.get("height", 0)},
	}


func _state_fingerprint() -> String:
	var ml: Object = Engine.get_main_loop()
	if ml is SceneTree:
		var adapter: Node = _get_project_adapter()
		if adapter != null and adapter.has_method("state_fingerprint"):
			return str(adapter.state_fingerprint())
	return ""


func _get_project_adapter() -> Node:
	var root := (Engine.get_main_loop() as SceneTree).root if Engine.get_main_loop() is SceneTree else null
	if root == null:
		return null
	var configured_path := str(ProjectSettings.get_setting("application/mcp/project_adapter_node", "/root/McpProjectAdapter"))
	if configured_path.begins_with("/"):
		var configured := root.get_node_or_null(NodePath(configured_path))
		if configured != null:
			return configured
	return root.find_child("McpProjectAdapter", true, false)


## Record a step with verdict into the archive (no screenshot).
## Used by the agent after every click to build up the baseline ledger.
func _record_step(args: Dictionary) -> Dictionary:
	var action := str(args.get("action", ""))
	var verdict := str(args.get("verdict", "TO_CHECK"))
	var reason := str(args.get("reason", ""))
	var solved_count := int(args.get("solved_count", 0))
	var fail_count := int(args.get("fail_count", 0))

	var meta := {
		"verdict": verdict,
		"reason": reason,
		"solved_count": solved_count,
		"fail_count": fail_count,
		"step_ts": Time.get_unix_time_from_system(),
	}

	if not _ensure_archive():
		return {"error": "archive unavailable", "recorded": false}

	# Use log_success with the verdict in metadata (compact, no screenshot for TO_CHECK)
	var result: Dictionary = await _archive.log_success(action, meta, null)
	return {
		"recorded": true,
		"entry_id": result.get("id", 0),
		"action": action,
		"verdict": verdict,
		"solved_count": solved_count,
		"fail_count": fail_count,
	}