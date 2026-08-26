@tool
extends EditorPlugin
class_name GDScriptMcpPlugin

## GDScript MCP Bridge — Editor Plugin
## Starts an MCP server (stdio/TCP) exposing Godot Editor & Runtime as MCP tools.
## Compatible with any GDScript project (Godot 4.3+). No C# / .NET required.

const MCP_SERVER_SCRIPT = "res://addons/gdscript_mcp/runtime/host/mcp_server.gd"
const CONTEXT_STORE_SCRIPT = "res://addons/gdscript_mcp/runtime/context/mcp_context_store.gd"
const RUNTIME_CLIENT_SCRIPT = "res://addons/gdscript_mcp/editor/mcp_runtime_client.gd"
const RUNTIME_TOOLS_PATH := "res://addons/gdscript_mcp/runtime/tools/runtime/mcp_runtime_tools.gd"
const DEFAULT_PORT = 9091

const RUNTIME_PORT := 9090

var _server_instance = null
var _runtime_server_instance = null
var _dock = null
var _is_running = false
var _runtime_server_running := false
var _runtime_write_enabled := false
var _runtime_session_id := ""
var _runtime_profile := "player"
var _history: Array[Dictionary] = []
var _context_store: RefCounted = null

func _enter_tree() -> void:
	var context_script: Resource = load(CONTEXT_STORE_SCRIPT)
	if context_script != null:
		_context_store = context_script.new()
		if _context_store != null:
			_context_store.configure("user://mcp_context/editor")

	# Add dock for UI control
	_dock = preload("res://addons/gdscript_mcp/editor/mcp_dock.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_LEFT_UL, _dock)
	_dock.start_server_requested.connect(_on_start_server_requested)
	_dock.stop_server_requested.connect(_on_stop_server_requested)
	_dock.config_changed.connect(_on_config_changed)
	_dock.runtime_launch_requested.connect(_on_runtime_launch_requested)

	# Runtime-MCP läuft IN-PROCESS im Editor (ein Godot-Prozess, keine
	# separaten Spielprozesse). Der Dock verbindet sich direkt auf 9090.
	# WICHTIG: Der Start wird mehrfach verzögert/retried, weil der Editor beim
	# ersten Idle noch nicht alle Skripte kompiliert hat — ein sofortiger
	# Start würde runtime_* Tools transient als „failed to parse“ melden.
	call_deferred("_boot_runtime_server_retry", 0)

	# Auto-start if configured
	var config = _load_config()
	if config.get("auto_start", false):
		call_deferred("_start_server_internal", config)

func _exit_tree() -> void:
	_stop_runtime_server_internal()
	_stop_server()
	if _context_store != null:
		_context_store.clear()
		_context_store = null
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null

func _on_start_server_requested(config: Dictionary) -> void:
	_start_server_internal(config)

func _on_runtime_launch_requested(profile: String) -> void:
	if get_editor_interface().is_playing_scene():
		get_editor_interface().stop_playing_scene()
	var result: Dictionary = await _run_project("", true, profile, RUNTIME_PORT)
	if not bool(result.get("started", false)):
		_push_error("Spielstart fehlgeschlagen: " + str(result.get("error", "?")))
	else:
		_push_log("Spiel sichtbar gestartet (in-process, Profil " + str(result.get("profile", "player")) + ") — Runtime-MCP auf Port " + str(RUNTIME_PORT) + ", verbinde …")

func _on_stop_server_requested() -> void:
	_stop_server()

func _on_config_changed(config: Dictionary) -> void:
	_save_config(config)
	if _is_running and config.get("auto_restart", true):
		_stop_server()
		call_deferred("_start_server_internal", config)
	# In-process-Runtime-Server: Das Schreib-Gate (AllowWrites im Dock) soll
	# ohne Editor-Neustart greifen — bei Änderung Server neu konfigurieren.
	# Der Dock verbindet sich selbsttätig neu (_process-Reconnect).
	var allow_writes := bool(config.get("editor_write_enabled", false))
	if _runtime_server_running and allow_writes != _runtime_write_enabled:
		_stop_runtime_server_internal()
		call_deferred("_boot_runtime_server_retry", 0)

func _start_server_internal(config: Dictionary) -> void:
	if _is_running:
		_stop_server()

	var script = load(MCP_SERVER_SCRIPT)
	if not script:
		_push_error("MCP server script not found: " + MCP_SERVER_SCRIPT)
		return

	_server_instance = script.new()
	add_child(_server_instance)
	_server_instance.log_message.connect(_on_server_log)
	_server_instance.status_changed.connect(_on_server_status_changed)
	_server_instance.set_editor_plugin(self)
	if _context_store != null and _server_instance.has_method("set_context_store"):
		_server_instance.set_context_store(_context_store)

	var port = int(config.get("port", DEFAULT_PORT))
	var transport = str(config.get("transport", "tcp"))
	if transport == "":
		transport = "tcp"
	var server_config: Dictionary = config.duplicate(true)
	server_config["transport"] = transport
	server_config["role"] = "editor"
	server_config["session_id"] = str(server_config.get("session_id", "editor_%d" % Time.get_ticks_msec()))

	var success = _server_instance.start_server(port, transport, server_config)
	if success:
		_is_running = true
		_dock.set_server_running(true)
		_push_log("MCP Server started on " + transport + " (port " + str(port) + ")")
	else:
		_push_error("Failed to start MCP server")
		if _dock:
			_dock.set_server_running(false)
		if _server_instance != null:
			_server_instance.queue_free()
			_server_instance = null

func _stop_server() -> void:
	if _server_instance:
		_server_instance.stop_server()
		_server_instance.queue_free()
		_server_instance = null
	_is_running = false
	if _dock:
		_dock.set_server_running(false)
	_push_log("MCP Server stopped")

func _on_server_log(message: String, is_error: bool = false) -> void:
	if is_error:
		_push_error("[MCP] " + message)
	else:
		_push_log("[MCP] " + message)

func _on_server_status_changed(status: String) -> void:
	_dock.set_status_text(status)

func _push_log(msg: String) -> void:
	if _dock:
		_dock.add_log(msg, false)

func _push_error(msg: String) -> void:
	if _dock:
		_dock.add_log(msg, true)

func _load_config() -> Dictionary:
	var file = ConfigFile.new()
	var path = "user://gdscript_mcp_config.cfg"
	if file.load(path) == OK:
		var val = file.get_value("config", "settings", {})
		if val is Dictionary:
			var loaded: Dictionary = val.duplicate(true)
			if not loaded.has("role"):
				loaded["role"] = "editor"
			if int(loaded.get("port", DEFAULT_PORT)) == 9090:
				loaded["port"] = DEFAULT_PORT
			if not loaded.has("transport"):
				loaded["transport"] = "tcp"
			return loaded
	return {"port": DEFAULT_PORT, "transport": "tcp", "auto_start": false, "auto_restart": true, "editor_write_enabled": false, "role": "editor"}

func _save_config(config: Dictionary) -> void:
	var file = ConfigFile.new()
	file.set_value("config", "settings", config)
	file.save("user://gdscript_mcp_config.cfg")

# ===== Public API for other plugins/scripts =====

func execute_editor_action(action: String, params: Dictionary) -> Variant:
	match action:
		"get_scene_tree", "scene_tree":
			return _get_scene_tree()
		"find_node":
			return _find_node(str(params.get("path", "")))
		"get_node_info", "node_info":
			return _get_node_info(str(params.get("path", "")))
		"select_node":
			return _select_node(str(params.get("path", "")))
		"create_node":
			return _create_node(params)
		"delete_node":
			return _delete_node(str(params.get("path", "")))
		"set_node_property":
			return _set_node_property(str(params.get("path", "")), str(params.get("property", "")), params.get("value"))
		"apply_transaction":
			return _apply_transaction(params)
		"get_resource", "resource_read":
			return _get_resource(str(params.get("path", "")))
		"save_scene", "scene_save":
			return _save_scene(str(params.get("path", "")))
		"undo":
			return _undo_editor_action()
		"redo":
			return _redo_editor_action()
		"history":
			return {"entries": _history.duplicate(true), "count": _history.size()}
		"run_project":
			return await _run_project(str(params.get("scene", "")), bool(params.get("with_mcp", false)), str(params.get("profile", "")), int(params.get("port", 9090)), bool(params.get("wait_for_mcp", true)), int(params.get("startup_timeout_ms", 6000)))
		"stop_project", "stop_runtime":
			return _stop_project()
		"project_status", "runtime_status":
			return _project_status()
		"capture_screenshot", "screenshot":
			# Async: return GDScriptFunctionState; the server awaits it.
			return (Callable(self, "_capture_screenshot") as Callable).call(str(params.get("viewport", "")), str(params.get("format", "png")))
		_:
			return {"error": "Unknown action: " + action}

# ===== Editor Action Implementations =====

func _get_scene_tree() -> Array:
	var result = []
	var root = EditorInterface.get_edited_scene_root()
	if root:
		_collect_nodes_for_tree(root, result, 0)
	return result

func _collect_nodes_for_tree(node: Node, result: Array, depth: int) -> void:
	if depth > 20:
		return
	var info = {
		"name": node.name,
		"type": node.get_class(),
		"path": node.get_path(),
		"children": []
	}
	result.append(info)
	for child in node.get_children():
		_collect_nodes_for_tree(child, info["children"], depth + 1)

func _find_node(path: String) -> Dictionary:
	var root = EditorInterface.get_edited_scene_root()
	if not root:
		return {"error": "No scene open"}
	var node = root.get_node_or_null(path)
	if not node:
		return {"error": "Node not found: " + path}
	return {
		"name": node.name,
		"type": node.get_class(),
		"path": node.get_path(),
		"position": _get_global_position(node),
		"visible": _is_visible(node)
	}

func _get_node_info(path: String) -> Dictionary:
	var root = EditorInterface.get_edited_scene_root()
	if not root:
		return {"error": "No scene open"}
	var node = root.get_node_or_null(path)
	if not node:
		return {"error": "Node not found: " + path}

	var info = {
		"name": node.name,
		"type": node.get_class(),
		"path": node.get_path(),
		"position": _get_global_position(node),
		"rect": _get_rect(node),
		"visible": _is_visible(node),
		"properties": _get_editable_properties(node)
	}
	return info

func _get_editable_properties(node: Node) -> Dictionary:
	var props = {}
	var list = node.get_property_list()
	for prop in list:
		if prop.usage & PROPERTY_USAGE_EDITOR:
			props[prop.name] = node.get(prop.name)
	return props

func _select_node(path: String) -> bool:
	var root = EditorInterface.get_edited_scene_root()
	if not root:
		return false
	var node = root.get_node_or_null(path)
	if not node:
		return false
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)
	return true

func _create_node(params: Dictionary) -> Dictionary:
	var parent_path := str(params.get("parent_path", "."))
	var node_type := str(params.get("type", "Node"))
	var node_name := str(params.get("name", node_type))
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"error": "No scene open"}
	var parent: Node = root if parent_path == "" or parent_path == "." else root.get_node_or_null(NodePath(parent_path))
	if parent == null:
		return {"error": "Parent not found: " + parent_path}
	var script_path := str(params.get("script", ""))
	var new_node: Node = _create_node_instance(node_type, script_path)
	if new_node == null:
		return {"error": "Failed to create node type: " + node_type}
	new_node.name = _get_unique_name(parent, node_name)
	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Create " + String(new_node.name))
	undo_redo.add_do_method(parent, "add_child", new_node)
	undo_redo.add_do_method(new_node, "set_owner", root)
	for key in params:
		if key in ["parent_path", "type", "name", "script"] or not _has_property(new_node, str(key)):
			continue
		var property_name := str(key)
		var property_value: Variant = _convert_value(params[key], _property_type(new_node, property_name))
		undo_redo.add_do_property(new_node, property_name, property_value)
		undo_redo.add_undo_property(new_node, property_name, new_node.get(property_name))
	undo_redo.add_undo_method(parent, "remove_child", new_node)
	undo_redo.add_undo_method(new_node, "set_owner", null)
	undo_redo.add_undo_reference(new_node)
	undo_redo.commit_action()
	_mark_scene_modified()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(new_node)
	_record_history("create_node", {"path": String(new_node.get_path()), "type": node_type, "name": String(new_node.name)})
	return {"path": new_node.get_path(), "name": String(new_node.name), "undoable": true}

func _create_node_instance(type_name: String, script_path: String) -> Node:
	if ClassDB.class_exists(type_name):
		var instance: Object = ClassDB.instantiate(type_name)
		if instance is Node:
			var node: Node = instance as Node
			if script_path != "" and ResourceLoader.exists(script_path):
				var script_res = load(script_path)
				if script_res:
					node.set_script(script_res)
			return node

	if script_path != "" and ResourceLoader.exists(script_path):
		var script_res = load(script_path)
		if script_res and script_res is Script:
			var instance = script_res.new()
			if instance:
				return instance

	return null

func _get_unique_name(parent: Node, base_name: String) -> String:
	var name = base_name
	var counter = 1
	while parent.has_node(name):
		name = base_name + "_" + str(counter)
		counter += 1
	return name

func _delete_node(path: String) -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"deleted": false, "error": "No scene open"}
	var node: Node = root if path == "" or path == "." else root.get_node_or_null(NodePath(path))
	if node == null or node == root:
		return {"deleted": false, "error": "Node cannot be deleted: " + path}
	var parent: Node = node.get_parent()
	var owner_node: Node = node.owner
	var index := node.get_index()
	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Delete " + String(node.name))
	undo_redo.add_do_method(parent, "remove_child", node)
	undo_redo.add_do_method(node, "set_owner", null)
	undo_redo.add_undo_method(parent, "add_child", node)
	undo_redo.add_undo_method(parent, "move_child", node, index)
	if owner_node != null:
		undo_redo.add_undo_method(node, "set_owner", owner_node)
	undo_redo.add_undo_reference(node)
	undo_redo.commit_action()
	_mark_scene_modified()
	_record_history("delete_node", {"path": path, "name": String(node.name)})
	return {"deleted": true, "undoable": true, "path": path}

func _set_node_property(path: String, property: String, value: Variant) -> Dictionary:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"changed": false, "error": "No scene open"}
	var node: Node = root if path == "" or path == "." else root.get_node_or_null(NodePath(path))
	if node == null or not _has_property(node, property):
		return {"changed": false, "error": "Property not found: " + property}
	var converted_value := _convert_value(value, _property_type(node, property))
	var previous_value: Variant = node.get(property)
	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: Set " + property)
	undo_redo.add_do_property(node, property, converted_value)
	undo_redo.add_undo_property(node, property, previous_value)
	undo_redo.commit_action()
	_mark_scene_modified()
	EditorInterface.get_inspector().refresh()
	_record_history("set_node_property", {"path": path, "property": property})
	return {"changed": true, "undoable": true, "path": path, "property": property}

func _apply_transaction(params: Dictionary) -> Dictionary:
	var operations: Array = params.get("operations", [])
	if operations.is_empty():
		return {"committed": false, "error": "No operations"}
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return {"committed": false, "error": "No scene open"}
	var prepared: Array[Dictionary] = []
	for raw_operation in operations:
		if not raw_operation is Dictionary:
			return {"committed": false, "error": "Transaction operation must be an object"}
		var operation: Dictionary = raw_operation
		var path := str(operation.get("path", ""))
		var property_name := str(operation.get("property", ""))
		var node: Node = root if path == "" or path == "." else root.get_node_or_null(NodePath(path))
		if node == null or not _has_property(node, property_name):
			return {"committed": false, "error": "Invalid transaction target: " + path + "." + property_name}
		prepared.append({"node": node, "path": path, "property": property_name, "value": _convert_value(operation.get("value"), _property_type(node, property_name)), "previous": node.get(property_name)})
	var label := str(params.get("label", "MCP edit"))
	var undo_redo := get_undo_redo()
	undo_redo.create_action("MCP: " + label)
	for prepared_operation in prepared:
		undo_redo.add_do_property(prepared_operation.node, prepared_operation.property, prepared_operation.value)
		undo_redo.add_undo_property(prepared_operation.node, prepared_operation.property, prepared_operation.previous)
	undo_redo.commit_action()
	_mark_scene_modified()
	EditorInterface.get_inspector().refresh()
	_record_history("transaction", {"label": label, "operations": prepared.size()})
	return {"committed": true, "undoable": true, "operations": prepared.size(), "label": label}

func _undo_editor_action() -> Dictionary:
	var undo_redo := get_undo_redo()
	if not undo_redo.has_undo():
		return {"undone": false, "reason": "empty"}
	undo_redo.undo()
	EditorInterface.get_inspector().refresh()
	return {"undone": true}

func _redo_editor_action() -> Dictionary:
	var undo_redo := get_undo_redo()
	if not undo_redo.has_redo():
		return {"redone": false, "reason": "empty"}
	undo_redo.redo()
	EditorInterface.get_inspector().refresh()
	return {"redone": true}

func _has_property(node: Object, property_name: String) -> bool:
	for raw_property in node.get_property_list():
		var property: Dictionary = raw_property
		if str(property.get("name", "")) == property_name:
			return true
	return false

func _property_type(node: Object, property_name: String) -> int:
	for raw_property in node.get_property_list():
		var property: Dictionary = raw_property
		if str(property.get("name", "")) == property_name:
			return int(property.get("type", TYPE_NIL))
	return TYPE_NIL

func _mark_scene_modified() -> void:
	get_editor_interface().mark_scene_as_unsaved()

func _record_history(action: String, details: Dictionary) -> void:
	_history.append({"action": action, "details": details.duplicate(true), "timestamp_ms": Time.get_ticks_msec()})
	if _history.size() > 128:
		_history.pop_front()

func _convert_value(value: Variant, target_type: int) -> Variant:
	if value is Dictionary:
		var dictionary: Dictionary = value
		if target_type == TYPE_VECTOR2 and dictionary.has("x") and dictionary.has("y"):
			return Vector2(float(dictionary.get("x", 0.0)), float(dictionary.get("y", 0.0)))
		if target_type == TYPE_VECTOR3 and dictionary.has("x") and dictionary.has("y") and dictionary.has("z"):
			return Vector3(float(dictionary.get("x", 0.0)), float(dictionary.get("y", 0.0)), float(dictionary.get("z", 0.0)))
		if target_type == TYPE_COLOR and dictionary.has("r") and dictionary.has("g") and dictionary.has("b"):
			return Color(float(dictionary.get("r", 0.0)), float(dictionary.get("g", 0.0)), float(dictionary.get("b", 0.0)), float(dictionary.get("a", 1.0)))
	match target_type:
		TYPE_INT: return int(value)
		TYPE_FLOAT: return float(value)
		TYPE_BOOL: return bool(value)
		TYPE_STRING: return str(value)
		TYPE_NODE_PATH: return NodePath(str(value))
		_: return value

func _get_resource(path: String) -> Dictionary:
	if not _is_project_resource_path(path):
		return {"error": "Resource path must stay inside the project: " + path}
	var res = ResourceLoader.load(path)
	if not res:
		return {"error": "Resource not found: " + path}
	return {
		"path": path,
		"type": res.get_class(),
		"metadata": _get_resource_metadata(res)
	}

func _get_resource_metadata(res: Resource) -> Dictionary:
	var meta = {}
	if res is Texture2D:
		meta = {"width": res.get_width(), "height": res.get_height()}
	elif res is PackedScene:
		meta = {"scene_path": res.resource_path}
	elif res is Script:
		meta = {"class_name": res.get_class_name()}
	return meta

func _save_scene(path: String) -> bool:
	if path != "" and not _is_project_resource_path(path):
		return false
	var scene_root = get_editor_interface().get_edited_scene_root()
	if not scene_root:
		return false
	var save_path = path if path != "" else scene_root.scene_file_path
	if save_path == "":
		return false
	var packed = PackedScene.new()
	packed.pack(scene_root)
	var err = ResourceSaver.save(packed, save_path)
	return err == OK

func _run_project(scene_path: String, with_mcp: bool = false, profile: String = "", port: int = RUNTIME_PORT, wait_for_mcp: bool = true, startup_timeout_ms: int = 6000) -> Variant:
	if scene_path != "" and not _is_project_resource_path(scene_path):
		return {"started": false, "error": "scene path must stay inside the project"}
	if with_mcp:
		# IN-PROCESS-Wechsel: Das Spiel läuft im selben Godot-Prozess wie der
		# Editor (play_main_scene / play_custom_scene). Der Runtime-MCP-Server
		# wird beim Plugin-Start gestartet und hier nur noch mit dem aktuellen
		# Play-Goal-Profil neu konfiguriert. Kein OS.create_process — genau ein
		# Godot läuft; der Dock verbindet sich direkt auf RUNTIME_PORT.
		var safe_profile := profile.strip_edges().to_lower()
		if safe_profile != "" and safe_profile not in ["player", "qa", "dev"]:
			return {"started": false, "mcp": false, "error": "profile must be player, qa, or dev"}
		if safe_profile == "":
			safe_profile = _runtime_profile
		var safe_port := clampi(port, 1024, 65535)
		if not _start_runtime_server_internal(safe_profile, safe_port):
			return {"started": false, "mcp": false, "error": "in-process runtime MCP server could not be started"}
		if scene_path != "":
			get_editor_interface().play_custom_scene(scene_path)
		else:
			get_editor_interface().play_main_scene()
		return {
			"started": true,
			"mcp": true,
			"in_process": true,
			"port": safe_port,
			"profile": safe_profile,
			"scene": scene_path,
			"session_id": _runtime_session_id,
			"mcp_ready": _runtime_server_running,
		}
	if scene_path != "":
		get_editor_interface().play_custom_scene(scene_path)
	else:
		get_editor_interface().play_main_scene()
	return {"started": true, "mcp": false, "scene": scene_path}


func _stop_project() -> Dictionary:
	var result := _stop_runtime_server_internal()
	if get_editor_interface().is_playing_scene():
		get_editor_interface().stop_playing_scene()
		result["editor_scene_stopped"] = true
		result["stopped"] = true
	elif not bool(result.get("stopped", false)):
		result["reason"] = "no in-process runtime MCP or editor play session"
	return result


func _project_status() -> Dictionary:
	return {
		"in_process": true,
		"runtime_server_running": _runtime_server_running,
		"runtime_mcp_ready": _runtime_server_running and _runtime_server_instance != null and bool(_runtime_server_instance.call("is_running")),
		"port": RUNTIME_PORT,
		"profile": _runtime_profile,
		"session_id": _runtime_session_id,
		"editor_playing": get_editor_interface().is_playing_scene(),
		"playing_scene": get_editor_interface().get_playing_scene(),
	}


func _start_runtime_server_internal(profile: String = "", port: int = RUNTIME_PORT) -> bool:
	var safe_profile := profile.strip_edges().to_lower() if profile != "" else ""
	if safe_profile == "":
		safe_profile = _runtime_profile
	if safe_profile == "":
		# Im Editor ist McpRuntime inaktiv; das Play-Goal kommt aus dem Dock.
		safe_profile = _read_dock_profile()
	if safe_profile == "" or safe_profile not in ["player", "qa", "dev"]:
		safe_profile = "player"
	if _runtime_server_instance != null and is_instance_valid(_runtime_server_instance):
		if _runtime_server_running and _runtime_profile == safe_profile and int(_runtime_server_instance.call("get_port")) == port:
			return true
		_stop_runtime_server_internal()
	var script: Resource = load(MCP_SERVER_SCRIPT)
	if script == null:
		_push_error("MCP server script not found: " + MCP_SERVER_SCRIPT)
		return false
	_runtime_server_instance = script.new()
	add_child(_runtime_server_instance)
	_runtime_server_instance.log_message.connect(_on_runtime_server_log)
	# Das Dock-Schreib-Gate (AllowWrites) gilt auch für den In-Process-
	# Runtime-Server: Nur so kann der Agent über dieselbe Dock-Verbindung
	# frei zwischen Edit (runtime_autonomy_write/patch) und Ingame wechseln.
	var dock_config := _load_config()
	var allow_writes := bool(dock_config.get("editor_write_enabled", false))
	var server_config := {
		"role": "runtime",
		"profile": safe_profile,
		"session_id": "runtime_%d" % Time.get_ticks_msec(),
		"mcp_virtual_mouse": true,
		"mcp_block_physical_mouse": true,
		"mcp_virtual_mouse_cursor": true,
		"vision_worker_enabled": false,
		"editor_write_enabled": allow_writes,
		"autonomy_writes": allow_writes,
	}
	var success: bool = _runtime_server_instance.start_server(port, "tcp", server_config)
	if not success:
		_runtime_server_instance.queue_free()
		_runtime_server_instance = null
		_runtime_server_running = false
		_push_error("Runtime-MCP (in-process) konnte nicht starten auf Port " + str(port))
		return false
	_runtime_server_running = true
	_runtime_write_enabled = allow_writes
	_runtime_session_id = str(server_config.get("session_id", ""))
	_runtime_profile = safe_profile
	_push_log("Runtime-MCP in-process aktiv auf 127.0.0.1:" + str(port) + " (Profil " + safe_profile + ")")
	return true


func _stop_runtime_server_internal() -> Dictionary:
	if _runtime_server_instance == null or not is_instance_valid(_runtime_server_instance):
		_runtime_server_running = false
		return {"stopped": false, "mode": "runtime_server", "reason": "no in-process runtime server"}
	var was_running: bool = _runtime_server_running
	_runtime_server_instance.stop_server()
	_runtime_server_instance.queue_free()
	_runtime_server_instance = null
	_runtime_server_running = false
	return {"stopped": was_running, "mode": "runtime_server", "was_running": was_running}


func _on_runtime_server_log(message: String, is_error: bool = false) -> void:
	if is_error:
		_push_error("[Runtime-MCP] " + message)
	else:
		_push_log("[Runtime-MCP] " + message)


func _boot_runtime_server_retry(attempt: int) -> void:
	if _runtime_server_running:
		return
	if attempt >= 40:
		_push_error("Runtime-MCP (in-process) konnte nach mehreren Versuchen nicht starten")
		return
	# Der load()-Cache des Editors kann mcp_runtime_tools.gd transient als
	# "nicht instanziierbar" liefern (asynchroner Skriptserver-Compile). Der
	# Check kompiliert deshalb frisch aus dem Quelltext — cache-unabhängig.
	# Erst wenn das Skript wirklich parse-bar ist, startet der Server (sonst
	# fehlen runtime_* Tools still).
	if attempt > 0:
		await get_tree().create_timer(0.5, true).timeout
	if _runtime_tools_ready():
		if _start_runtime_server_internal():
			return
	call_deferred("_boot_runtime_server_retry", attempt + 1)


func _runtime_tools_ready() -> bool:
	# Frisch aus Quelltext kompilieren: unabhängig vom Editor-Skriptserver-Cache
	# und liefert den echten Compile-Status des Skripts.
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(RUNTIME_TOOLS_PATH)
	script.resource_path = RUNTIME_TOOLS_PATH
	return script.reload() == OK and script.can_instantiate()


func _read_dock_profile() -> String:
	var file := ConfigFile.new()
	if file.load("user://gdscript_mcp_profile.cfg") == OK:
		var stored := str(file.get_value("profile", "name", "")).strip_edges().to_lower()
		if stored in ["player", "qa", "dev"]:
			return stored
	return ""


func _is_project_resource_path(path: String) -> bool:
	var normalized := path.strip_edges().simplify_path()
	return normalized.begins_with("res://") and not normalized.contains("..")

func _capture_screenshot(viewport_path: String, format: String) -> Dictionary:
	var viewport_node: Viewport = get_editor_interface().get_editor_viewport_2d()
	if viewport_path != "":
		var root = get_editor_interface().get_edited_scene_root()
		if root:
			var found = root.find_child(viewport_path, true, false)
			if found and found is Viewport:
				viewport_node = found as Viewport
			else:
				return {"error": "Viewport not found: " + viewport_path}
		else:
			return {"error": "No scene root"}

	if viewport_node == null:
		return {"error": "No viewport available"}
	var texture: Texture2D = viewport_node.get_texture()
	if texture == null or not texture.get_rid().is_valid():
		return {"error": "Editor viewport texture is unavailable"}

	# Godot 4.7: await frame_post_draw before get_image().
	await RenderingServer.frame_post_draw
	var image: Image = texture.get_image()
	if image == null or image.is_empty():
		return {"error": "Empty image"}

	var normalized_format := "jpg" if format == "jpg" or format == "jpeg" else "png"
	if _context_store == null:
		return {"error": "Editor context store unavailable"}
	var context: Dictionary = _context_store.write_image(image, normalized_format, {
		"source": "editor_viewport",
		"viewport": viewport_path,
	})
	if context.has("error"):
		return context
	return {
		"context_id": context.get("context_id", ""),
		"context": context,
		"artifact": context,
		"format": normalized_format,
		"mime_type": "image/jpeg" if normalized_format == "jpg" else "image/png",
		"width": image.get_width(),
		"height": image.get_height(),
		"size_bytes": context.get("size_bytes", 0),
	}

func _get_global_position(node: Node) -> Dictionary:
	if node is Control:
		var control_pos := (node as Control).global_position
		return {"x": control_pos.x, "y": control_pos.y}
	if node is Node2D:
		var node_pos := (node as Node2D).global_position
		return {"x": node_pos.x, "y": node_pos.y}
	if node is CanvasItem:
		var canvas_pos := (node as CanvasItem).get_global_transform().origin
		return {"x": canvas_pos.x, "y": canvas_pos.y}
	if node is Node3D:
		var node_3d_pos := (node as Node3D).global_position
		return {"x": node_3d_pos.x, "y": node_3d_pos.y, "z": node_3d_pos.z}
	return {"x": 0, "y": 0}

func _get_rect(node: Node) -> Dictionary:
	if node is Control:
		var control := node as Control
		var control_rect := control.get_global_rect()
		return {"x": control_rect.position.x, "y": control_rect.position.y, "width": control_rect.size.x, "height": control_rect.size.y}
	var position := _get_global_position(node)
	return {"x": position.get("x", 0), "y": position.get("y", 0), "width": 0, "height": 0}

func _is_visible(node: Node) -> bool:
	if node is CanvasItem:
		return node.visible and _is_parent_visible(node)
	if node is Node3D:
		return node.visible
	return true

func _is_parent_visible(node: Node) -> bool:
	var parent = node.get_parent()
	while parent:
		if parent is CanvasItem and not parent.visible:
			return false
		parent = parent.get_parent()
	return true