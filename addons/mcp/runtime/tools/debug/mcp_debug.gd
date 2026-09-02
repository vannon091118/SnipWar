extends RefCounted
class_name McpDebug

## McpDebug — Facade. Delegates to McpDebugPerf, McpDebugProject, McpDebugRuntime.
## This file: ~110 lines (was 508).

var _perf: McpDebugPerf = null


func _get_perf() -> McpDebugPerf:
	if not _perf:
		_perf = McpDebugPerf.new()
	return _perf


# ═══════════════════════════════════════════════════════════════
# Delegates → sub-modules
# ═══════════════════════════════════════════════════════════════

func get_perf_metrics() -> Dictionary:
	return _get_perf().get_perf_metrics()

func get_rendering_stats() -> Dictionary:
	return _get_perf().get_rendering_stats()

func get_engine_info() -> Dictionary:
	return _get_perf().get_engine_info()

func get_frame_timing() -> Dictionary:
	return _get_perf().get_frame_timing()

func get_project_config() -> Dictionary:
	return McpDebugProject.get_project_config()

func list_project_files(filter_str: String = "", max_depth: int = 5) -> Dictionary:
	return McpDebugProject.list_project_files(filter_str, max_depth)

func get_class_info(cls_name: String) -> Dictionary:
	return McpDebugProject.get_class_info(cls_name)

func get_resource_uid(path: String) -> Dictionary:
	return McpDebugProject.get_resource_uid(path)

func get_event_log(limit: int = 100, filter_str: String = "") -> Dictionary:
	return McpDebugRuntime.get_event_log(limit, filter_str)

func get_object_counts() -> Dictionary:
	return McpDebugRuntime.get_object_counts()

func get_memory_info() -> Dictionary:
	return McpDebugRuntime.get_memory_info()

func profile_callable(code: String, iterations: int = 1000) -> Dictionary:
	return McpDebugRuntime.profile_callable(code, iterations)


# ═══════════════════════════════════════════════════════════════
# MCP Module Interface: get_tool_defs() + dispatch_tool()
# ═══════════════════════════════════════════════════════════════

static func get_tool_defs() -> Array:
	return [
		_make_tool("runtime_perf_metrics", "Get all performance monitors (FPS, memory, draw calls, etc.)"),
		_make_tool("runtime_rendering_stats", "Get rendering statistics from RenderingServer"),
		_make_tool("runtime_engine_info", "Get engine version, OS info, singletons, headless status"),
		_make_tool("runtime_frame_timing", "Get frame-to-frame delta in microseconds"),
		_make_tool("runtime_project_config", "Dump all ProjectSettings"),
		_make_tool("runtime_list_files", "List project files, optionally filtered by extension",
			{"filter": {"type": "string", "default": ""}, "max_depth": {"type": "integer", "default": 5}}),
		_make_tool("runtime_class_info", "Reflect a class via ClassDB (properties, methods, signals, enums)",
			{"cls_name": {"type": "string"}}, ["cls_name"]),
		_make_tool("runtime_resource_uid", "Look up a resource by path, get its UID",
			{"path": {"type": "string"}}, ["path"]),
		_make_tool("runtime_event_log", "Read entries from EventLog autoload",
			{"limit": {"type": "integer", "default": 100}, "filter": {"type": "string", "default": ""}}),
		_make_tool("runtime_object_counts", "Get object/node/resource counts"),
		_make_tool("runtime_memory_info", "Get memory usage (static, video)"),
		_make_tool("runtime_profile", "Time a GDScript expression over N iterations",
			{"code": {"type": "string"}, "iterations": {"type": "integer", "default": 1000}}, ["code"]),
	]


func dispatch_tool(tool_name: String, args: Dictionary) -> Variant:
	match tool_name:
		"runtime_perf_metrics":      return get_perf_metrics()
		"runtime_rendering_stats":    return get_rendering_stats()
		"runtime_engine_info":        return get_engine_info()
		"runtime_frame_timing":       return get_frame_timing()
		"runtime_project_config":     return get_project_config()
		"runtime_list_files":         return list_project_files(args.get("filter", ""), args.get("max_depth", 5))
		"runtime_class_info":          return get_class_info(args.get("cls_name", ""))
		"runtime_resource_uid":        return get_resource_uid(args.get("path", ""))
		"runtime_event_log":           return get_event_log(args.get("limit", 100), args.get("filter", ""))
		"runtime_object_counts":      return get_object_counts()
		"runtime_memory_info":        return get_memory_info()
		"runtime_profile":
			if not ("--mcp-developer" in OS.get_cmdline_args() or "--mcp-developer" in OS.get_cmdline_user_args()):
				return {"error": "profile requires developer mode (--mcp-developer)"}
			return profile_callable(args.get("code", ""), args.get("iterations", 1000))
		_:                            return {"error": "Unknown debug tool: " + tool_name}


static func _make_tool(name: String, description: String, properties: Dictionary = {},
		required: Array = [], async_tool: bool = false) -> Dictionary:
	var schema = {"type": "object", "properties": properties}
	if not required.is_empty():
		schema["required"] = required
	var tool = {"name": name, "description": description, "inputSchema": schema}
	if async_tool:
		tool["_async"] = true
	return tool