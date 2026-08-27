@tool
extends EditorPlugin
class_name GDScriptMcpPlugin

## GDScript MCP Bridge — Editor Plugin
## Starts an MCP server (stdio/TCP) exposing Godot Editor & Runtime as MCP tools.
## Compatible with any GDScript project (Godot 4.3+). No C# / .NET required.

const MCP_SERVER_SCRIPT = "res://addons/gdscript_mcp/runtime/host/mcp_server.gd"
const CONTEXT_STORE_SCRIPT = "res://addons/gdscript_mcp/runtime/context/mcp_context_store.gd"
const RUNTIME_CLIENT_SCRIPT = "res://addons/gdscript_mcp/editor/mcp_runtime_client.gd"
const DEFAULT_PORT = 9091

const RUNTIME_PORT := 9090

# Embedded-Runtime (OFFEN-1 gelöst): Der Runtime-MCP-Server wird NICHT mehr
# vom Plugin im Editor-Prozess gehostet (der Editor-Kind-Server konnte die
# Scene-Tools nie auf den Spielbaum richten — Engine.get_main_loop() lieferte
# den Editor-Tree; zudem startet play_main_scene das Spiel in Godot 4 als
# SEPARATEN Prozess). Stattdessen setzt das Plugin Env-Flags und startet das
# Spiel; der McpRuntime-Autoload bootet den Server im Kind-Prozess (echter
# Spiel-SceneTree). Das Plugin wartet auf den Handshake des Spiel-Servers.
const EMBEDDED_ENV := "MCP_EMBEDDED"
const EMBEDDED_PORT_ENV := "MCP_EMBEDDED_PORT"
const EMBEDDED_PROFILE_ENV := "MCP_EMBEDDED_PROFILE"
const EMBEDDED_WRITES_ENV := "MCP_EMBEDDED_WRITES"

# ─── Projektagnostische Auto-Registrierung ───────────────────────
# Beim Aktivieren des Plugins (Project Settings → Plugins) richtet sich
# dieses Addon selbst im aktuellen Projekt ein: die für den Runtime-MCP
# nötigen Autoloads und die application/mcp/*-Settings werden ergänzt, falls
# sie fehlen. Keine manuelle project.godot-Editierung nötig.
#
# Die Autoloads sind inert ohne den Game-Start-Flag --mcp (mcp_runtime.gd
# _ready() kehrt früh zurück); GameState/EventLog bleiben projektseitig.
const AUTOLOADS := {
	"McpRuntime": "*res://addons/gdscript_mcp/runtime/host/mcp_runtime.gd",
	"McpProjectAdapter": "*res://addons/gdscript_mcp/runtime/core/mcp_project_adapter.gd",
}
# Achtung: Die beiden Pfade unter application/mcp/* sind DEFAULTS (SnipWar).
# Andere Projekte überschreiben sie in ihrer own project.godot — das Addon
# legt sie nur an, wenn sie noch nicht existieren.
const MCP_SETTINGS := {
	"application/mcp/preflight_script": {"value": "res://scripts/preflight.gd", "type": TYPE_STRING},
	"application/mcp/main_menu_scene": {"value": "res://scenes/main_menu/main_menu.tscn", "type": TYPE_STRING},
	"application/mcp/game_state_node": {"value": "", "type": TYPE_STRING},
	"application/mcp/event_log_node": {"value": "", "type": TYPE_STRING},
	"application/mcp/project_adapter_node": {"value": "", "type": TYPE_STRING},
	"application/mcp/game_state_script": {"value": "", "type": TYPE_STRING},
}

var _server_instance = null
var _dock = null
var _is_running = false
var _runtime_profile := "player"
var _history: Array[Dictionary] = []
var _context_store: RefCounted = null

func _enter_tree() -> void:
	_register_project_integration()

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

	# Runtime-MCP startet NICHT mehr im Editor-Prozess: Der Server bootet im
	# Spiel-SceneTree (McpRuntime-Autoload + MCP_EMBEDDED-Env beim Spielstart).
	# Der Dock verbindet sich selbsttätig auf 9090, sobald das Spiel läuft.

	# Auto-start if configured
	var config = _load_config()
	if config.get("auto_start", false):
		call_deferred("_start_server_internal", config)

func _exit_tree() -> void:
	_clear_embedded_env()
	_stop_server()
	if _context_store != null:
		_context_store.clear()
		_context_store = null
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null

## Legt fehlende Autoloads und application/mcp/*-Settings im aktuellen
## Projekt an (idempotent: nur wenn abweichend). Schreibt project.godot nur,
## wenn sich tatsächlich etwas ändert — kein Dirty-State bei reinen Starts.
func _register_project_integration() -> void:
	var changed := false

	# 1. Autoloads registrieren (McpRuntime + McpProjectAdapter)
	for autoload_name: String in AUTOLOADS:
		var setting := "autoload/" + autoload_name
		var desired: String = AUTOLOADS[autoload_name]
		var current: Variant = ProjectSettings.get_setting(setting, null)
		if str(current) != desired or current == null:
			ProjectSettings.set_setting(setting, desired)
			changed = true
			push_warning("[GDScriptMcp] Autoload hinzugefügt: " + autoload_name)

	# 2. application/mcp/*-Settings ergänzen (nur fehlende)
	for setting: String in MCP_SETTINGS:
		if not ProjectSettings.has_setting(setting):
			var info: Dictionary = MCP_SETTINGS[setting]
			ProjectSettings.set_setting(setting, info.get("value"))
			changed = true
			push_warning("[GDScriptMcp] Setting gesetzt: " + setting)

	if changed:
		ProjectSettings.save()


func _on_start_server_requested(config: Dictionary) -> void:
	_start_server_internal(config)

func _on_runtime_launch_requested(profile: String) -> void:
	if get_editor_interface().is_playing_scene():
		get_editor_interface().stop_playing_scene()
	var result: Dictionary = await _run_project("", true, profile, RUNTIME_PORT)
	if not bool(result.get("started", false)):
		_push_error("Spielstart fehlgeschlagen: " + str(result.get("error", "?")))
	else:
		_push_log("Spiel sichtbar gestartet (eigener Prozess, Profil " + str(result.get("profile", "player")) + ") — Runtime-MCP auf Port " + str(RUNTIME_PORT) + ", verbinde …")

func _on_stop_server_requested() -> void:
	_stop_server()

func _on_config_changed(config: Dictionary) -> void:
	_save_config(config)
	if _is_running and config.get("auto_restart", true):
		_stop_server()
		call_deferred("_start_server_internal", config)
	elif not _is_running and config.get("auto_start", false):
		# Auto-Start wird sonst nur beim Editor-Start ausgewertet — ein mitten
		# in der Session aktivierter Auto-Start startet den Editor-Server sofort.
		call_deferred("_start_server_internal", config)
	# Das Schreib-Gate (AllowWrites) greift beim NÄCHSTEN Spielstart: Der
	# Runtime-Server bootet im Spiel-SceneTree (MCP_EMBEDDED) und liest
	# MCP_EMBEDDED_WRITES beim Boot. Ein laufendes Spiel übernimmt die
	# Änderung nicht mehr live (kein In-Process-Server mehr im Editor).

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
		# EMBEDDED-WECHSEL (OFFEN-1): play_main_scene startet das Spiel in
		# Godot 4 als SEPARATEN Prozess. Der Runtime-MCP-Server bootet NICHT im
		# Editor — der McpRuntime-Autoload im Spielprozess startet ihn im
		# echten Spiel-SceneTree, sobald MCP_EMBEDDED gesetzt ist (der
		# Child-Prozess erbt die Env-Variablen). Damit zeigt
		# Engine.get_main_loop() im Server auf den SPIEL-Baum, und alle
		# Scene-/UX-/Input-Tools arbeiten auf dem echten Spiel. Das Plugin
		# setzt die Env-Flags, startet das Spiel und wartet auf den Handshake.
		var safe_profile := profile.strip_edges().to_lower()
		if safe_profile != "" and safe_profile not in ["player", "qa", "dev"]:
			return {"started": false, "mcp": false, "error": "profile must be player, qa, or dev"}
		if safe_profile == "":
			safe_profile = _runtime_profile
		if safe_profile == "":
			safe_profile = _read_dock_profile()
		if safe_profile == "":
			safe_profile = "player"
		var safe_port := clampi(port, 1024, 65535)
		_runtime_profile = safe_profile
		_set_embedded_env(safe_profile, safe_port)
		if scene_path != "":
			get_editor_interface().play_custom_scene(scene_path)
		else:
			get_editor_interface().play_main_scene()
		if wait_for_mcp:
			var liveness: Dictionary = await _wait_for_runtime_mcp(safe_port, startup_timeout_ms)
			return {
				"started": true,
				"mcp": true,
				"in_process": false,
				"separate_process": true,
				"embedded": true,
				"port": safe_port,
				"profile": safe_profile,
				"scene": scene_path,
				"mcp_ready": bool(liveness.get("ready", false)),
				"mcp_liveness": liveness,
			}
		return {
			"started": true,
			"mcp": true,
			"in_process": false,
			"separate_process": true,
			"embedded": true,
			"port": safe_port,
			"profile": safe_profile,
			"scene": scene_path,
		}
	if scene_path != "":
		get_editor_interface().play_custom_scene(scene_path)
	else:
		get_editor_interface().play_main_scene()
	return {"started": true, "mcp": false, "scene": scene_path}


## Setzt die Env-Flags für den Embedded-Runtime: Der McpRuntime-Autoload im
## Spiel-SceneTree bootet den MCP-Server mit Profil/Port/Write-Gate.
func _set_embedded_env(profile: String, port: int) -> void:
	OS.set_environment(EMBEDDED_ENV, "1")
	OS.set_environment(EMBEDDED_PORT_ENV, str(port))
	OS.set_environment(EMBEDDED_PROFILE_ENV, profile)
	var dock_config := _load_config()
	OS.set_environment(EMBEDDED_WRITES_ENV, "1" if bool(dock_config.get("editor_write_enabled", false)) else "0")


func _clear_embedded_env() -> void:
	OS.set_environment(EMBEDDED_ENV, "")
	OS.set_environment(EMBEDDED_PORT_ENV, "")
	OS.set_environment(EMBEDDED_PROFILE_ENV, "")
	OS.set_environment(EMBEDDED_WRITES_ENV, "")


## Wartet auf den Runtime-MCP-Server IM SPIEL (Liveness-Probe mit demselben
## persistenten Client, den auch der Dock nutzt). Kein Editor-Server-Hosting.
func _wait_for_runtime_mcp(port: int, timeout_ms: int) -> Dictionary:
	var script: Resource = load(RUNTIME_CLIENT_SCRIPT)
	if script == null:
		return {"ready": false, "error": "runtime client script missing"}
	var probe: RefCounted = script.new()
	var connect_result: int = probe.connect_to("127.0.0.1", port)
	if connect_result != OK:
		probe.close()
		return {"ready": false, "error": "runtime connect failed: %s" % error_string(connect_result)}
	var receipt: Dictionary = await probe.wait_until_ready(maxi(1000, timeout_ms))
	probe.close()
	return receipt


func _stop_project() -> Dictionary:
	var result := {"stopped": false, "mode": "embedded"}
	_clear_embedded_env()
	if get_editor_interface().is_playing_scene():
		get_editor_interface().stop_playing_scene()
		result["editor_scene_stopped"] = true
		result["stopped"] = true
	else:
		result["reason"] = "no editor play session active"
	return result


func _project_status() -> Dictionary:
	var embedded := OS.get_environment(EMBEDDED_ENV) == "1"
	return {
		"in_process": false,
		"separate_process": true,
		"embedded": embedded,
		"runtime_server_running": embedded,
		"runtime_mcp_ready": embedded and get_editor_interface().is_playing_scene(),
		"port": RUNTIME_PORT,
		"profile": _runtime_profile,
		"editor_playing": get_editor_interface().is_playing_scene(),
		"playing_scene": get_editor_interface().get_playing_scene(),
	}


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