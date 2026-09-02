extends RefCounted
class_name McpCodeAnalyzer

## Statischer Projekt-Code-Analyzer.
## Liest .gd-Dateien aus res:// und extrahiert Input-Methoden, Signale,
## GameState-API, Szenen-Liste und Autoloads.
## Agenten nutzen das um zu verstehen, WIE ein Spiel Input verarbeitet
## bevor sie frame-genau spielen.

const MAX_FILE_SIZE := 256 * 1024
const MAX_FILES := 400


# ─── Public API ─────────────────────────────────────────────────

static func analyze_project() -> Dictionary:
	return {
		"input_methods": _analyze_input(),
		"signals": _analyze_signals(),
		"scenes": _list_scenes(),
		"autoloads": _list_autoloads(),
		"game_state_api": _analyze_game_state(),
		"mcp_tools": _list_custom_mcp_tools(),
	}


static func analyze_input() -> Dictionary:
	return _analyze_input()


static func analyze_signals() -> Array:
	return _analyze_signals()


static func analyze_game_state() -> Dictionary:
	return _analyze_game_state()


# ─── Input Detection ────────────────────────────────────────────

static func _analyze_input() -> Dictionary:
	var methods := {
		"_input": [] as Array,
		"_unhandled_input": [] as Array,
		"_gui_input": [] as Array,
		"is_action_pressed": [] as Array,
		"is_action_just_pressed": [] as Array,
		"InputEventMouseButton": [] as Array,
		"InputEventKey": [] as Array,
		"InputEventScreenTouch": [] as Array,
	}
	var files := _list_gd_files()
	if files.size() > MAX_FILES:
		files.resize(MAX_FILES)
	for file in files:
		var content := _read_file_safe(file)
		if content == "":
			continue
		for method in methods.keys():
			if method in content:
				var arr: Array = methods[method]
				arr.append(file)
	return methods


# ─── Signal Detection ───────────────────────────────────────────

static func _analyze_signals() -> Array:
	var signals: Array = []
	var files := _list_gd_files()
	if files.size() > MAX_FILES:
		files.resize(MAX_FILES)
	for file in files:
		var content := _read_file_safe(file)
		if content == "":
			continue
		for line in content.split("\n"):
			var stripped := line.strip_edges()
			if stripped.begins_with("signal "):
				signals.append({
					"file": file,
					"signal": stripped.trim_prefix("signal ").get_slice("(", 0).strip_edges(),
				})
	return signals


# ─── Scene List ─────────────────────────────────────────────────

static func _list_scenes() -> Array:
	var scenes: Array = []
	var da := DirAccess.open("res://")
	if da == null:
		return scenes
	_find_files_recursive(da, scenes, 0, 6, [".tscn", ".scn"])
	return scenes


# ─── Autoloads ──────────────────────────────────────────────────

static func _list_autoloads() -> Array:
	var autoloads: Array = []
	var config := ConfigFile.new()
	if config.load("res://project.godot") != OK:
		return autoloads
	for key in config.get_section_keys("autoload"):
		var path := config.get_value("autoload", key)
		autoloads.append({"name": key, "path": str(path).trim_prefix("*")})
	return autoloads


# ─── GameState API ──────────────────────────────────────────────

static func _analyze_game_state() -> Dictionary:
	var gs_files: Array = []
	var configured_state_path := str(ProjectSettings.get_setting("application/mcp/game_state_script", ""))
	if configured_state_path.begins_with("res://") and configured_state_path.ends_with(".gd"):
		gs_files.append(configured_state_path)
	var autoloads := _list_autoloads()
	for autoload in autoloads:
		var autoload_path := str(autoload.get("path", ""))
		if autoload_path.ends_with(".gd") and autoload_path not in gs_files:
			gs_files.append(autoload_path)
	if gs_files.is_empty():
		gs_files.append_array(_find_named_scripts("game_state"))

	var public_methods: Array = []
	var public_vars: Array = []
	for file in gs_files:
		var content := _read_file_safe(file)
		if content == "":
			continue
		for line in content.split("\n"):
			var stripped := line.strip_edges()
			if stripped.begins_with("func ") and not stripped.begins_with("func _"):
				public_methods.append({
					"file": file,
					"method": stripped.trim_prefix("func ").get_slice("(", 0).strip_edges(),
				})
			if stripped.begins_with("var ") and not stripped.begins_with("var _"):
				public_vars.append({
					"file": file,
					"variable": stripped.trim_prefix("var ").get_slice(":", 0).get_slice("=", 0).strip_edges(),
				})

	return {
		"files_scanned": gs_files.size(),
		"public_methods": public_methods,
		"public_variables": public_vars,
		"method_count": public_methods.size(),
	}


# ─── Custom MCP Tools ───────────────────────────────────────────

static func _find_named_scripts(fragment: String) -> Array:
	var matches: Array = []
	for file in _list_gd_files():
		if str(file).get_file().to_lower().contains(fragment.to_lower()):
			matches.append(file)
	return matches


static func _list_custom_mcp_tools() -> Array:
	var tools: Array = []
	var da := DirAccess.open("res://mcp_tools")
	if da == null:
		return tools
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if entry.ends_with(".gd") and not entry.begins_with("."):
			var full := "res://mcp_tools/" + entry
			var content := _read_file_safe(full)
			if content != "":
				tools.append({"file": full, "size_lines": content.split("\n").size()})
		entry = da.get_next()
	da.list_dir_end()
	return tools


# ─── Helpers ────────────────────────────────────────────────────

static func _list_gd_files() -> Array:
	var files: Array = []
	var da := DirAccess.open("res://")
	if da == null:
		return files
	_find_files_recursive(da, files, 0, 8, [".gd"])
	return files


static func _find_files_recursive(da: DirAccess, result: Array, depth: int, max_depth: int, extensions: Array) -> void:
	if depth > max_depth:
		return
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = da.get_next()
			continue
		var full := da.get_current_dir().path_join(entry)
		if da.current_is_dir():
			if entry.begins_with(".") or entry in [".godot", "addons", "test", "tests", "user_data"]:
				entry = da.get_next()
				continue
			var sub := DirAccess.open(full)
			if sub != null:
				_find_files_recursive(sub, result, depth + 1, max_depth, extensions)
		else:
			for ext in extensions:
				if entry.ends_with(ext):
					result.append(full)
					break
		entry = da.get_next()
	da.list_dir_end()


static func _read_file_safe(file_path: String) -> String:
	if not FileAccess.file_exists(file_path):
		return ""
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return ""
	var content := f.get_as_text()
	if content.length() > MAX_FILE_SIZE:
		content = content.substr(0, MAX_FILE_SIZE)
	return content


# ─── Tool Definitions ───────────────────────────────────────────

static func get_tool_defs() -> Array:
	return [
		_make("runtime_analyze_project", "Full project analysis: input methods, signals, scenes, autoloads, GameState API, custom MCP tools"),
		_make("runtime_analyze_input", "Scan all .gd files for _input, _unhandled_input, is_action_pressed patterns"),
		_make("runtime_analyze_signals", "List all GDScript signal declarations in the project"),
		_make("runtime_analyze_game_state", "Extract GameState public API: methods and variables"),
	]


static func _make(name: String, description: String, properties: Dictionary = {}, required: Array = []) -> Dictionary:
	var schema := {"type": "object", "properties": properties}
	if not required.is_empty():
		schema["required"] = required
	return {"name": name, "description": description, "inputSchema": schema}


func dispatch_tool(tool_name: String, _args: Dictionary) -> Variant:
	match tool_name:
		"runtime_analyze_project": return analyze_project()
		"runtime_analyze_input": return analyze_input()
		"runtime_analyze_signals": return analyze_signals()
		"runtime_analyze_game_state": return analyze_game_state()
		_: return {"error": "Unknown code analyzer tool: " + tool_name}