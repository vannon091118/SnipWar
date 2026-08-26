extends RefCounted
class_name McpDebugRuntime

## McpDebugRuntime — Runtime-level debugging (extracted from McpDebug).
## EventLog reading, object counts, memory info, expression profiling, node inspection.


static func get_event_log(limit: int = 100, filter_str: String = "") -> Dictionary:
	# Use the project adapter if available; fall back to raw EventLog.
	var adapter = _get_project_adapter()
	if adapter != null and adapter.has_method("log_sources"):
		var sources: Array = adapter.log_sources()
		if "event_log" in sources and adapter.has_method("log_normalize_entry"):
			# Delegate to adapter for normalized entries
			return _get_event_log_via_adapter(adapter, limit, filter_str)

	# Fallback: discover a conventional EventLog node, or configure its path.
	var rt: Window = _get_root()
	if not rt:
		return {"error": "No scene tree"}
	var event_log: Object = _find_named_node(rt, "EventLog")
	if not event_log:
		return {"error": "EventLog autoload not found — register a McpProjectAdapter for cross-project support"}

	var entries: Array = []
	if event_log.has_method("get_entries"):
		var raw: Variant = event_log.get_entries()
		if raw is Array:
			for e in (raw as Array):
				if entries.size() >= limit:
					break
				if filter_str == "":
					entries.append(e)
				else:
					var txt: String = ""
					if e is String:          txt = e as String
					elif e is Dictionary:
						var ed: Dictionary = e as Dictionary
						txt = str(ed.get("text", ed.get("message", str(e))))
					else:                    txt = str(e)
					if filter_str in txt:
						entries.append(e)
	return {"entries": entries, "count": entries.size(), "truncated": entries.size() >= limit}


static func _get_event_log_via_adapter(adapter, limit: int, filter_str: String) -> Dictionary:
	var rt: Window = _get_root()
	if not rt:
		return {"error": "No scene tree"}
	var event_log: Object = _find_named_node(rt, "EventLog")
	if event_log == null or not event_log.has_method("get_entries"):
		return {"error": "EventLog not accessible"}
	var raw: Array = event_log.get_entries()
	var entries: Array = []
	for i in range(raw.size() - 1, -1, -1):
		if entries.size() >= limit:
			break
		var normalized: Dictionary = adapter.log_normalize_entry("event_log", raw[i])
		if normalized.is_empty():
			continue
		if filter_str != "" and not str(normalized.get("text", "")).to_lower().contains(filter_str.to_lower()):
			continue
		entries.append(normalized)
	entries.reverse()
	return {"entries": entries, "count": entries.size(), "truncated": entries.size() >= limit}


static func _find_named_node(root: Node, node_name: String) -> Node:
	var configured_path := str(ProjectSettings.get_setting("application/mcp/%s_node" % node_name.to_lower(), ""))
	if configured_path.begins_with("/"):
		var configured := root.get_node_or_null(NodePath(configured_path))
		if configured != null:
			return configured
	return root.find_child(node_name, true, false)


static func _get_project_adapter():
	var rt: Window = _get_root()
	if not rt:
		return null
	var configured_path := str(ProjectSettings.get_setting("application/mcp/project_adapter_node", "/root/McpProjectAdapter"))
	return rt.get_node_or_null(NodePath(configured_path)) if configured_path.begins_with("/") else null


static func get_object_counts() -> Dictionary:
	return {
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_nodes": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
	}


static func get_memory_info() -> Dictionary:
	return {
		"static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"static_max_mb": Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0,
		"video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
	}


static func profile_callable(code: String, iterations: int = 1000) -> Dictionary:
	var safe_iterations := clampi(iterations, 1, 1000000)
	var expr: Expression = Expression.new()
	var err: int = expr.parse(code, ["_i"])
	if err != OK:
		return {"error": "Parse error: " + error_string(err)}

	var start: int = Time.get_ticks_usec()
	for i in safe_iterations:
		expr.execute([i], null, true)
	var elapsed: int = Time.get_ticks_usec() - start
	return {"code": code, "iterations": safe_iterations, "total_usec": elapsed, "avg_usec": float(elapsed) / float(safe_iterations)}


static func _get_root() -> Window:
	var ml: Object = Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root
	return null