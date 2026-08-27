extends Node
class_name GdscriptMcpServer

## Role-aware MCP host. Runtime and editor sessions are intentionally separate.
## The node owns its lifecycle and keeps processing while the game is paused.

signal log_message(message: String, is_error: bool)
signal status_changed(status: String)

const REGISTRY_PATH := "res://addons/gdscript_mcp/runtime/core/mcp_tool_registry.gd"
const CONTEXT_STORE_PATH := "res://addons/gdscript_mcp/runtime/context/mcp_context_store.gd"
const LIFECYCLE_PATH := "res://addons/gdscript_mcp/runtime/lifecycle/mcp_lifecycle.gd"
const PROTOCOL_PATH := "res://addons/gdscript_mcp/runtime/protocol/mcp_protocol.gd"
const VISION_WORKER_PATH := "res://addons/gdscript_mcp/runtime/tools/vision/mcp_vision_worker.gd"
const AGENT_ACTIVITY_PATH := "res://addons/gdscript_mcp/runtime/tools/agent/mcp_agent_activity.gd"

const DEFAULT_PORT := 9090
const RUNTIME_TICK_INTERVAL := 0.05
const CONNECTED_TICK_INTERVAL := 0.016
const IDLE_TICK_INTERVAL := 0.15
const CONTEXT_CLEANUP_INTERVAL := 2.0
const MAX_BUFFER_BYTES := 4 * 1024 * 1024
const MAX_ASYNC_QUEUE := 32

var _role := "runtime"
var _session_id := ""
var _transport := "tcp"
var _port := DEFAULT_PORT
var _frame_budget_ms := 1.5
var _verbose := false
var _editor_write_enabled := false
var _contract_gate: RefCounted
var _profile := "player"
var _tcp_server: TCPServer
var _client: StreamPeerTCP
var _connection_generation := 0
var _running := false
var _buffer := ""
var _editor_plugin: Object
var _provided_context_store: RefCounted = null
var _registry: RefCounted
var _context_store: RefCounted
var _lifecycle: RefCounted
var _protocol: RefCounted
var _worker: Node
var _agent_activity: RefCounted
var _tools: Array = []
var _tool_index: Dictionary = {}
var _tick_accumulator := 0.0
var _context_cleanup_accumulator := 0.0
var _protocol_ready := false
var _client_protocol_version := ""
var _stdio_thread: Thread
var _stdio_mutex := Mutex.new()
var _stdio_queue: Array[String] = []
var _stdio_stop := false
var _async_busy := false
var _pending_async: Array[Dictionary] = []
var _last_tick_ms := 0
var _last_error := ""
var _evidence_cache: Dictionary = {}
var _evidence_inflight := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start_server(port: int = DEFAULT_PORT, transport: String = "tcp", config: Dictionary = {}) -> bool:
	if _running:
		_log("Server already running", true)
		return false
	_connection_generation += 1
	_role = str(config.get("role", "editor" if _editor_plugin != null else "runtime"))
	_session_id = str(config.get("session_id", "%s_%d" % [_role, Time.get_ticks_msec()]))
	_frame_budget_ms = float(config.get("frame_budget_ms", 1.5))
	_verbose = bool(config.get("verbose", false))
	_editor_write_enabled = bool(config.get("editor_write_enabled", false))
	var contract_gate_script: Resource = load("res://addons/gdscript_mcp/runtime/autonomy/mcp_contract_gate.gd")
	if contract_gate_script == null:
		_log("Failed to load contract gate", true)
		return false
	# Kein pauschales "player"-Default: Der Gate-Konstruktor wählt rollenbasiert
	# (editor → dev, runtime → player). Ein explizites --mcp-profile=qa|dev
	# schlägt weiterhin. Sonst würde jede Editor-Session als player starten und
	# die Autonomy-Workspace-Tools (Editor-Editierkanal) wären gesperrt.
	_contract_gate = contract_gate_script.new()
	_contract_gate.configure(str(config.get("profile", "")), _role)
	_profile = str(_contract_gate.get_profile())
	_port = port
	_transport = transport.to_lower()
	if _transport != "tcp" and _transport != "stdio":
		_log("Unknown transport: " + _transport, true)
		return false
	if not _is_renderer_visible():
		_log("MCP runtime session requires a visible renderer; headless mode is unsupported", true)
		return false

	var lifecycle_script: Resource = load(LIFECYCLE_PATH)
	var protocol_script: Resource = load(PROTOCOL_PATH)
	var context_script: Resource = load(CONTEXT_STORE_PATH)
	var agent_activity_script: Resource = load(AGENT_ACTIVITY_PATH)
	if lifecycle_script == null or protocol_script == null or context_script == null or agent_activity_script == null:
		_log("Failed to load MCP core modules", true)
		return false
	_lifecycle = lifecycle_script.new()
	_protocol = protocol_script.new()
	_context_store = _provided_context_store if _provided_context_store != null else context_script.new()
	_agent_activity = agent_activity_script.new()
	if _lifecycle == null or _protocol == null or _context_store == null or _agent_activity == null:
		_log("Failed to instantiate MCP core modules", true)
		return false
	if _provided_context_store == null:
		_context_store.configure("user://mcp_context/%s_%s" % [_role, _session_id])
	_lifecycle.configure(_role, _session_id, _frame_budget_ms)
	_lifecycle.start()
	_lifecycle.mark_listening(_transport, _port)
	if not _load_registry():
		_lifecycle.stop()
		_log("Failed to load tool registry", true)
		return false
	if _registry.has_method("set_role"):
		_registry.set_role(_role)
	if _registry.has_method("set_lifecycle"):
		_registry.set_lifecycle(_lifecycle)
	if _registry.has_method("set_autonomy_writes"):
		_registry.set_autonomy_writes(_resolve_autonomy_writes(config))
	if _role == "runtime":
		_create_vision_worker(config)
		if _registry.has_method("set_worker"):
			_registry.set_worker(_worker)
	_register_host_tools()

	if _transport == "tcp":
		_tcp_server = TCPServer.new()
		var listen_error := _tcp_server.listen(_port, "127.0.0.1")
		if listen_error != OK:
			_dispose_worker()
			if _context_store != null:
				_context_store.cleanup()
			_lifecycle.stop()
			_registry = null
			_tools.clear()
			_tool_index.clear()
			_tcp_server = null
			_log("Failed to listen on %d: %s" % [_port, error_string(listen_error)], true)
			return false
	else:
		_stdio_stop = false
		_stdio_thread = Thread.new()
		_stdio_thread.start(Callable(self, "_stdio_reader"))

	_running = true
	set_process(true)
	_protocol_ready = false
	_async_busy = false
	_pending_async.clear()
	_lifecycle.mark_ready()
	status_changed.emit("Running %s (%s:%d)" % [_role, _transport, _port])
	_log("MCP %s session %s live on 127.0.0.1:%d with %d tools" % [_role, _session_id, _port, _tools.size()])
	return true


func stop_server() -> void:
	if not _running and _tcp_server == null and _stdio_thread == null:
		return
	_running = false
	_stdio_stop = true
	set_process(false)
	if _stdio_thread != null:
		_stdio_thread.wait_to_finish()
		_stdio_thread = null
	if _client != null:
		_client.disconnect_from_host()
		_client = null
	if _tcp_server != null:
		_tcp_server.stop()
		_tcp_server = null
	_connection_generation += 1
	_pending_async.clear()
	_async_busy = false
	_dispose_worker()
	if _context_store != null:
		_context_store.cleanup()
	if _lifecycle != null:
		_lifecycle.stop()
	_registry = null
	_tools.clear()
	_tool_index.clear()
	_buffer = ""
	_protocol_ready = false
	_stdio_mutex.lock()
	_stdio_queue.clear()
	_stdio_mutex.unlock()
	status_changed.emit("Stopped %s" % _role)
	_log("MCP %s session stopped" % _role)


func set_editor_plugin(plugin: Node) -> void:
	_editor_plugin = plugin
	if _running and _role == "editor":
		_register_editor_tools()


func set_context_store(store: RefCounted) -> void:
	if _running:
		return
	_provided_context_store = store


func get_transport() -> String:
	return _transport


func get_port() -> int:
	return _port


func is_running() -> bool:
	return _running


func get_role() -> String:
	return _role


func get_session_id() -> String:
	return _session_id


func get_context_store() -> RefCounted:
	return _context_store


func get_lifecycle_state() -> Dictionary:
	var extra := {
		"running": _running,
		"transport": _transport,
		"port": _port,
		"role": _role,
		"session_id": _session_id,
		"profile": _profile,
		"contract_violations": _contract_gate.get_blocked_calls() if _contract_gate != null else 0,
		"renderer": "visible" if _is_renderer_visible() else "unavailable",
		"client_connected": _client != null and _client.get_status() == StreamPeerTCP.STATUS_CONNECTED,
		"tick_interval_ms": int(CONNECTED_TICK_INTERVAL * 1000.0) if _client != null else int(IDLE_TICK_INTERVAL * 1000.0),
		"tool_count": _tools.size(),
		"protocol_ready": _protocol_ready,
		"protocol_version": _client_protocol_version if _protocol_ready else "",
		"async_busy": _async_busy,
		"async_pending": _pending_async.size(),
		"process_mode": "ALWAYS",
		"editor_write_enabled": _editor_write_enabled,
		"autonomy_writes": _registry.get_autonomy_writes() if _registry != null and _registry.has_method("get_autonomy_writes") else false,
		"context_root": _context_store.get_root_path() if _context_store != null else "",
		"context_cache": _context_store.get_stats() if _context_store != null else {},
		"runtime": _registry.get_runtime_status() if _registry != null and _registry.has_method("get_runtime_status") else {},
		"last_error": _last_error,
		"events": _lifecycle.events_since(0, 16) if _lifecycle != null else {},
	}
	if _registry != null and _registry.has_method("get_watch_status"):
		extra["watch"] = _registry.get_watch_status()
	if _lifecycle != null:
		return _lifecycle.status(extra)
	return extra


func _process(delta: float) -> void:
	if not _running:
		return
	_tick_accumulator += delta
	var interval := CONNECTED_TICK_INTERVAL if _client != null else IDLE_TICK_INTERVAL
	if _tick_accumulator < interval:
		return
	_tick_accumulator = 0.0
	_last_tick_ms = Time.get_ticks_msec()
	if _transport == "tcp":
		_poll_tcp()
	else:
		_drain_stdio()
	if _registry != null and _registry.has_method("tick"):
		var game_process_ms: float = float(Performance.get_monitor(Performance.TIME_PROCESS))
		_registry.tick(delta, _lifecycle.can_run_visual() if _lifecycle != null else true)
		if _lifecycle != null:
			_lifecycle.tick(delta, game_process_ms, _pending_async.size())
	_context_cleanup_accumulator += delta
	if _context_store != null and _context_cleanup_accumulator >= CONTEXT_CLEANUP_INTERVAL:
		_context_cleanup_accumulator = 0.0
		_context_store.cleanup()


func _load_registry() -> bool:
	var registry_script: Resource = load(REGISTRY_PATH)
	if registry_script == null:
		return false
	_registry = registry_script.new()
	if _registry == null:
		return false
	# Set role and session dependencies before lazy loading; editor sessions
	# must never instantiate runtime, vision, UX, or E2E modules.
	if _registry.has_method("set_role"):
		_registry.set_role(_role)
	if _registry.has_method("set_context_store"):
		_registry.set_context_store(_context_store)
	if _registry.has_method("set_lifecycle"):
		_registry.set_lifecycle(_lifecycle)
	_tools = _registry.get_all_tools()
	_rebuild_tool_index()
	return _role == "editor" or not _tools.is_empty()


func _register_host_tools() -> void:
	var contracts = load("res://addons/gdscript_mcp/runtime/autonomy/mcp_autonomy_contracts.gd")
	var host_tools := [
		{
			"name": "runtime_mcp_status",
			"description": "Read MCP role, lifecycle, queue, performance and artifact status",
			"inputSchema": {"type": "object", "properties": {}},
		},
		{
			"name": "runtime_mcp_events",
			"description": "Read incremental MCP lifecycle events and budget drops",
			"inputSchema": {"type": "object", "properties": {"cursor": {"type": "integer", "default": 0}, "limit": {"type": "integer", "default": 32}}},
		},
		{
			"name": "runtime_agent_goal_set",
			"description": "Declare the agent's current goal so humans and logs can see what is being worked on (transparency; mutates agent telemetry only)",
			"inputSchema": {"type": "object", "properties": {"goal": {"type": "string"}}, "required": ["goal"]},
		},
		{
			"name": "runtime_agent_activity",
			"description": "Read what the agent is currently doing: goal, last tool calls with args, timings and errors - without asking the agent",
			"inputSchema": {"type": "object", "properties": {"limit": {"type": "integer", "default": 20}}},
		},
		{
			"name": "runtime_visual_evidence",
			"description": "Return the latest automatic visual analysis (screenshot + OCR) that the server captured in the background after an unexpected tool result. status: none | pending | ready. wait_ms polls up to that many ms for an in-flight analysis (0 = return immediately). capture=true starts a fresh analysis when none is cached yet.",
			"inputSchema": {"type": "object", "properties": {"wait_ms": {"type": "integer", "default": 0}, "capture": {"type": "boolean", "default": false}}},
		},
	]
	for host_tool in host_tools:
		var normalized = McpAutonomyContracts.normalize_tool(host_tool, "host") if contracts != null else host_tool
		_tools.append(normalized)
	if _role == "editor":
		_register_editor_tools()
	_rebuild_tool_index()


func _register_editor_tools() -> void:
	var definitions := [
		_make_tool("editor_scene_tree", "Read the currently edited scene tree", {}),
		_make_tool("editor_find_node", "Find a node in the currently edited scene", {"path": {"type": "string"}}, ["path"]),
		_make_tool("editor_node_info", "Inspect a node and editable properties", {"path": {"type": "string"}}, ["path"]),
		_make_tool("editor_select_node", "Select a node in the Godot editor", {"path": {"type": "string"}}, ["path"]),
		_make_tool("editor_apply_transaction", "Apply an undoable editor mutation without saving to disk", {"operations": {"type": "array"}, "label": {"type": "string", "default": "MCP edit"}}, ["operations"]),
		_make_tool("editor_create_node", "Create a node through Godot Undo/Redo", {"parent_path": {"type": "string"}, "type": {"type": "string"}, "name": {"type": "string"}}, ["parent_path", "type"]),
		_make_tool("editor_delete_node", "Delete a node through Godot Undo/Redo", {"path": {"type": "string"}}, ["path"]),
		_make_tool("editor_set_node_property", "Set a node property through Godot Undo/Redo", {"path": {"type": "string"}, "property": {"type": "string"}, "value": {}}, ["path", "property", "value"]),
		_make_tool("editor_resource_read", "Inspect a project resource", {"path": {"type": "string"}}, ["path"]),
		_make_tool("editor_screenshot", "Capture the edited editor viewport as a local artifact", {"viewport": {"type": "string", "default": ""}, "format": {"type": "string", "enum": ["png", "jpg"], "default": "png"}}, [], true),
		_make_tool("editor_run_project", "Start the project from the editor. with_mcp=true launches the game as a separate process and waits for a verified runtime MCP handshake before returning", {"scene": {"type": "string", "default": ""}, "with_mcp": {"type": "boolean", "default": false}, "profile": {"type": "string", "enum": ["player", "qa", "dev"], "default": "player"}, "port": {"type": "integer", "default": 9090}, "wait_for_mcp": {"type": "boolean", "default": true}, "startup_timeout_ms": {"type": "integer", "default": 6000}}, [], true),
		_make_tool("editor_stop_project", "Stop the runtime process started through editor_run_project, or stop the editor's active play session", {}),
		_make_tool("editor_project_status", "Read the editor/runtime transition state, tracked PID, scene and MCP liveness metadata", {}),
		_make_tool("editor_logs_read", "Read the MCP editor-session log (lifecycle events) plus the engine log tail when a --log-file is configured", {"cursor": {"type": "integer", "default": 0}, "limit": {"type": "integer", "default": 50}, "include_file": {"type": "boolean", "default": true}}),
		_make_tool("editor_scene_save", "Explicitly save the edited scene; mutations never save implicitly", {"path": {"type": "string", "default": ""}}),
		_make_tool("editor_undo", "Undo the latest editor transaction", {}),
		_make_tool("editor_redo", "Redo the latest editor transaction", {}),
		_make_tool("editor_history", "Read editor mutation history", {}),
	]
	for definition in definitions:
		if not _tool_index.has(str(definition.get("name", ""))):
			var normalized := McpAutonomyContracts.normalize_tool(definition, "editor")
			_tools.append(normalized)
	_rebuild_tool_index()


func _make_tool(name: String, description: String, properties: Dictionary = {}, required: Array = [], async_tool: bool = false) -> Dictionary:
	var schema := {"type": "object", "properties": properties}
	if not required.is_empty():
		schema["required"] = required
	var tool := {"name": name, "description": description, "inputSchema": schema}
	if async_tool:
		tool["_async"] = true
	return tool


func _rebuild_tool_index() -> void:
	_tool_index.clear()
	for tool in _tools:
		if tool is Dictionary:
			_tool_index[str(tool.get("name", ""))] = tool


func _poll_tcp() -> void:
	if _tcp_server != null and _tcp_server.is_connection_available():
		if _client != null:
			_client.disconnect_from_host()
		_client = _tcp_server.take_connection()
		# TCP_NODELAY auf dem akzeptierten Socket: ohne das Flag kann Nagle
		# jedes MCP-Response um bis zu 40 ms verzögern (eine Hauptquelle für
		# "Agent to game time"-Latenz bei Chatty-Tool-Calls auf localhost).
		_client.set_no_delay(true)
		_connection_generation += 1
		_pending_async.clear()
		_buffer = ""
		_protocol_ready = false
		_log("Remote client connected")
	if _client == null:
		return
	if _client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_connection_generation += 1
		_pending_async.clear()
		_client = null
		_protocol_ready = false
		_log("Remote client disconnected")
		return
	var available := _client.get_available_bytes()
	if available <= 0:
		return
	var buffered_bytes := _buffer.to_utf8_buffer().size()
	if buffered_bytes + available > MAX_BUFFER_BYTES:
		_connection_generation += 1
		_client.disconnect_from_host()
		_client = null
		_buffer = ""
		_note_error("request buffer exceeded limit")
		return
	var packet: Array = _client.get_data(available)
	if packet.size() < 2 or int(packet[0]) != OK:
		return
	var bytes: PackedByteArray = packet[1] as PackedByteArray
	if bytes == null:
		return
	_buffer += bytes.get_string_from_utf8()
	_process_buffer()


func _stdio_reader() -> void:
	var line := ""
	while not _stdio_stop:
		var character := OS.read_string_from_stdin()
		if character == "":
			OS.delay_msec(5)
			continue
		if character == "\n":
			if line != "":
				_stdio_mutex.lock()
				_stdio_queue.append(line)
				_stdio_mutex.unlock()
			line = ""
		else:
			line += character
	if line != "":
		_stdio_mutex.lock()
		_stdio_queue.append(line)
		_stdio_mutex.unlock()


func _drain_stdio() -> void:
	var lines: Array[String] = []
	_stdio_mutex.lock()
	lines = _stdio_queue.duplicate()
	_stdio_queue.clear()
	_stdio_mutex.unlock()
	for line in lines:
		_handle_line(line.strip_edges())


func _process_buffer() -> void:
	while true:
		var newline_index := _buffer.find("\n")
		if newline_index < 0:
			return
		var line := _buffer.substr(0, newline_index).strip_edges()
		_buffer = _buffer.substr(newline_index + 1)
		if line != "":
			_handle_line(line)


func _handle_line(line: String) -> void:
	var parsed: Dictionary = _protocol.parse_message(line)
	if not bool(parsed.get("ok", false)):
		_send_response(null, null, str(parsed.get("error", "Parse error: invalid JSON")), -32700)
		return
	var message: Dictionary = parsed.get("message", {})
	if not message.has("method"):
		return
	var params: Variant = message.get("params", {})
	_handle_request(message.get("id"), str(message.get("method", "")), params if params is Dictionary else {})


func _handle_request(id: Variant, method: String, params: Dictionary) -> void:
	match method:
		"initialize":
			_client_protocol_version = _protocol.negotiate_protocol_version(str(params.get("protocolVersion", "")))
			_protocol_ready = true
			_send_response(id, {
				"protocolVersion": _client_protocol_version,
				"capabilities": {
					"tools": {"listChanged": true},
					"resources": {"listChanged": true}
				},
				"serverInfo": {"name": "gdscript-mcp-bridge", "version": "4.0.0", "role": _role},
			}, "", 0)
		"initialized":
			_send_response(id, {"ready": true, "lifecycle": get_lifecycle_state()}, "", 0)
		"tools/list":
			_send_response(id, {"tools": _tools}, "", 0)
		"tools/call":
			_handle_tool_call(id, params)
		"resources/list":
			_handle_resources_list(id)
		"resources/read":
			_handle_resources_read(id, params)
		"ping":
			_send_response(id, {"lifecycle": get_lifecycle_state()}, "", 0)
		_:
			_send_response(id, null, "Method not found: " + method, -32601)


func _handle_resources_list(id: Variant) -> void:
	var resources: Array = [
		{
			"uri": "godot://agent/activity",
			"name": "Agent Activity Feed",
			"description": "Current goal, last tool calls, timings and errors - agent transparency without asking the agent",
			"mimeType": "application/json"
		},
		{
			"uri": "godot://scene/current",
			"name": "Current Scene Tree",
			"description": "Live authoritative scene hierarchy and controls",
			"mimeType": "application/json"
		},
		{
			"uri": "godot://logs/recent",
			"name": "Recent Logs & Anomalies",
			"description": "Recent MCP and engine logs",
			"mimeType": "application/json"
		},
		{
			"uri": "godot://gameState/summary",
			"name": "Game State Summary",
			"description": "Faction economy, research, fleet and planet census",
			"mimeType": "application/json"
		},
		{
			"uri": "godot://test/results",
			"name": "Last Test Trace",
			"description": "Evidence trace of the last executed chain or scenario",
			"mimeType": "application/json"
		}
	]
	_send_response(id, {"resources": resources}, "", 0)


func _handle_resources_read(id: Variant, params: Dictionary) -> void:
	var uri := str(params.get("uri", ""))
	var data: Variant = null
	match uri:
		"godot://agent/activity":
			if _agent_activity != null:
				data = _agent_activity.get_feed(30)
			else:
				data = {"goal": "", "entries": []}
		"godot://scene/current":
			if _registry != null:
				data = _registry.dispatch("runtime_get_scene_tree", {"root_path": "/root", "max_depth": 4, "max_nodes": 200})
		"godot://logs/recent":
			if _lifecycle != null:
				data = _lifecycle.events_since(0, 50)
			else:
				data = {"logs": []}
		"godot://gameState/summary":
			if _registry != null:
				data = _registry.dispatch("game_state_summary", {"faction": "a"})
		"godot://test/results":
			if _registry != null:
				data = _registry.dispatch("runtime_chain_trace", {})
		_:
			_send_response(id, null, "Resource not found: " + uri, -32602)
			return

	if data == null:
		data = {}
	var text_payload := JSON.stringify(_sanitize_result(data))
	_send_response(id, {
		"contents": [
			{
				"uri": uri,
				"mimeType": "application/json",
				"text": text_payload
			}
		]
	}, "", 0)


func send_notification(method: String, params: Dictionary = {}) -> void:
	var msg: Dictionary = {"jsonrpc": "2.0", "method": method}
	if not params.is_empty():
		msg["params"] = params
	var encoded := JSON.stringify(msg) + "\n"
	if _transport == "tcp" and _client != null:
		_client.put_data(encoded.to_utf8_buffer())
	elif _transport == "stdio":
		print(encoded.strip_edges())


func notify_tools_changed() -> void:
	send_notification("notifications/tools/list_changed")


func notify_resources_changed() -> void:
	send_notification("notifications/resources/list_changed")


func _handle_tool_call(id: Variant, params: Dictionary) -> void:
	var request_generation := _connection_generation
	var tool_name := str(params.get("name", ""))
	var raw_args: Variant = params.get("arguments", {})
	var args: Dictionary = raw_args if raw_args is Dictionary else {}
	if tool_name == "runtime_mcp_status":
		_send_tool_result_atomic(id, get_lifecycle_state())
		return
	if tool_name == "runtime_mcp_events":
		var cursor := int(args.get("cursor", 0))
		var limit := clampi(int(args.get("limit", 32)), 1, 128)
		_send_tool_result_atomic(id, _lifecycle.events_since(cursor, limit) if _lifecycle != null else {"entries": [], "count": 0, "next_cursor": cursor})
		return
	if tool_name == "runtime_agent_goal_set":
		var goal := str(args.get("goal", "")).strip_edges()
		if goal == "":
			_send_response(id, null, "goal must not be empty", -32602)
			return
		var goal_result: Variant = _agent_activity.set_goal(goal) if _agent_activity != null else {"ok": true, "goal": goal}
		_send_tool_result_atomic(id, goal_result)
		return
	if tool_name == "runtime_agent_activity":
		var feed_limit := clampi(int(args.get("limit", 20)), 1, 100)
		var feed: Variant = _agent_activity.get_feed(feed_limit) if _agent_activity != null else {"goal": "", "entries": [], "count": 0, "total_calls": 0}
		_send_tool_result_atomic(id, feed)
		return
	if tool_name == "runtime_visual_evidence":
		_handle_visual_evidence(id, args, request_generation)
		return
	if tool_name == "editor_logs_read":
		# Kein Plugin-Kontext nötig: Session-Logs leben im Server (Lifecycle).
		var log_cursor := int(args.get("cursor", 0))
		var log_limit := clampi(int(args.get("limit", 50)), 1, 200)
		var events: Dictionary = _lifecycle.events_since(log_cursor, log_limit) if _lifecycle != null else {"entries": [], "count": 0, "next_cursor": log_cursor}
		var result: Dictionary = {"source": "mcp_editor", "entries": events.get("entries", []), "next_cursor": events.get("next_cursor", log_cursor)}
		if bool(args.get("include_file", true)):
			result["engine_log_tail"] = _read_engine_log_tail()
		_send_tool_result_atomic(id, result)
		return
	# MCP handshake gate: host tools (status/events) stay callable for health
	# probes, but every other tool requires the client to have run initialize.
	if not _protocol_ready:
		_send_response(id, null, "Server not initialized: call initialize first", -32002)
		return
	if not _tool_index.has(tool_name):
		_send_response(id, null, "Tool not found: " + tool_name, -32601)
		return
	var is_editor_tool := tool_name.begins_with("editor_")
	var is_host_tool := tool_name == "runtime_mcp_status" or tool_name == "runtime_mcp_events"
	if is_editor_tool and _role != "editor":
		_send_response(id, null, "Editor tool called on runtime session", -32001)
		return
	# The editor session may use the journaled autonomy workspace as its
	# project-edit channel. It is deliberately narrower than runtime access:
	# only runtime_autonomy_* is allowed through this exception, and its own
	# mutation gate still decides whether writes are authorized.
	var is_editor_autonomy_tool := tool_name.begins_with("runtime_autonomy_")
	if not is_editor_tool and not is_host_tool and not is_editor_autonomy_tool and _role == "editor" and tool_name.begins_with("runtime_"):
		_send_response(id, null, "Runtime tool called on editor session", -32001)
		return
	if is_editor_tool:
		if _is_editor_write_tool(tool_name) and not _editor_write_enabled:
			_send_response(id, null, "Editor write actions are disabled for this session", -32003)
			return
		if _editor_plugin == null:
			_send_response(id, null, "Editor plugin not available", -32000)
			return
		var editor_result: Variant = _editor_plugin.execute_editor_action(tool_name.trim_prefix("editor_"), args)
		if typeof(editor_result) == TYPE_OBJECT and (editor_result as Object).has_method("resume"):
			editor_result = await editor_result
		if request_generation == _connection_generation:
			_send_tool_result_atomic(id, editor_result)
		return
	# Verbindlicher Spieler-Vertrag: Session-Profil-Gate vor jedem Runtime-Tool.
	# Verstöße werden gezählt (runtime_mcp_status → contract_violations) und als
	# Lifecycle-Event protokolliert — ein Agent kann sie über runtime_mcp_events
	# lesen und den Modus wechseln (--mcp-profile=qa|dev), statt den Vertrag zu brechen.
	if _contract_gate != null:
		var gate_check: Dictionary = _contract_gate.check(tool_name)
		if not bool(gate_check.get("allowed", false)):
			var reason := str(gate_check.get("reason", "contract violation"))
			if _lifecycle != null:
				_lifecycle.note_event("warning", reason, "mcp", "contract")
				_lifecycle.note_error("contract violation: " + tool_name)
			log_message.emit("CONTRACT VIOLATION: " + reason, true)
			_send_response(id, null, reason, -32003)
			return
	if _role == "runtime" and not _is_game_running():
		_send_response(id, null, "Game not running", -32000)
		return
	var tool: Dictionary = _tool_index[tool_name]
	if bool(tool.get("_async", false)):
		if _async_busy:
			if _pending_async.size() >= MAX_ASYNC_QUEUE:
				_note_error("async queue full")
				_send_response(id, null, "Async queue full", -32002)
				return
			_pending_async.append({"id": id, "name": tool_name, "args": args, "generation": _connection_generation})
			return
		_async_busy = true
		if _lifecycle != null:
			_lifecycle.mark_busy(true)
		_run_async_tool(id, tool_name, args, _connection_generation)
		return
	var started_ms: int = _lifecycle.begin_tool(tool_name) if _lifecycle != null else 0
	var result: Variant = _registry.dispatch(tool_name, args)
	if _lifecycle != null:
		_lifecycle.end_tool(tool_name, started_ms)
		if _protocol.result_is_error(result):
			_lifecycle.note_error(str(result.get("error", "")))
	if _agent_activity != null:
		_agent_activity.record_tool(tool_name, args, float(Time.get_ticks_msec() - started_ms), not _protocol.result_is_error(result), str(result.get("error", "")) if _protocol.result_is_error(result) else "")
	if request_generation == _connection_generation:
		_send_tool_result_with_visual_evidence(id, tool_name, result, _connection_generation)


func _run_async_tool(id: Variant, tool_name: String, args: Dictionary, generation: int) -> void:
	var started_ms: int = _lifecycle.begin_tool(tool_name) if _lifecycle != null else 0
	var result: Variant = await _registry.dispatch_async(tool_name, args)
	if _lifecycle != null:
		_lifecycle.end_tool(tool_name, started_ms)
		if _protocol.result_is_error(result):
			_lifecycle.note_error(str(result.get("error", "")))
	if _agent_activity != null:
		_agent_activity.record_tool(tool_name, args, float(Time.get_ticks_msec() - started_ms), not _protocol.result_is_error(result), str(result.get("error", "")) if _protocol.result_is_error(result) else "")
	if generation == _connection_generation:
		_send_tool_result_atomic(id, result)
	_async_busy = false
	if _lifecycle != null:
		_lifecycle.mark_busy(false)
	while not _pending_async.is_empty():
		var next: Dictionary = _pending_async.pop_front()
		if int(next.get("generation", -1)) != _connection_generation:
			continue
		_async_busy = true
		if _lifecycle != null:
			_lifecycle.mark_busy(true)
		_run_async_tool(next.get("id"), str(next.get("name", "")), next.get("args", {}), _connection_generation)
		break


## PFLICHT-Regel: Folgt auf ein Tool-Ergebnis eine unerwartete Lage (Fehler,
## daneben gegangener Klick, leerer Scan), wird automatisch eine Bild-/OCR-Analyse
## angestoßen und als visual_evidence an die Antwort angehängt — der Agent sieht
## sofort den echten Bildschirmzustand, statt nur einen Fehlercode zu raten.
const UNEXPECTED_VISUAL_EXCLUSIONS: Array[String] = [
	"runtime_screenshot", "runtime_ux_analyze", "runtime_ux_read",
	"runtime_get_pixel", "runtime_get_pixel_region", "runtime_find_color",
	"runtime_find_all_colors", "runtime_count_color_pixels", "runtime_image_diff",
	"runtime_wait_for_stable", "runtime_frame_changed", "runtime_find_template",
	"runtime_context_release", "runtime_vision_worker_analyze", "runtime_vision_status",
	"runtime_mcp_status", "runtime_mcp_events", "editor_logs_read",
	"runtime_agent_goal_set", "runtime_agent_activity",
]

func _is_unexpected_result(result: Variant) -> bool:
	if not (result is Dictionary):
		return false
	var data: Dictionary = result
	if _protocol.result_is_error(data):
		return true
	if data.has("ok") and not bool(data.get("ok", true)):
		return true
	if data.has("_error") and bool(data.get("_error", false)):
		return true
	if data.has("clicked") and not bool(data.get("clicked", true)):
		return true
	if data.has("moved") and not bool(data.get("moved", true)):
		return true
	if data.has("controls") and data.get("controls") is Array and (data.get("controls") as Array).is_empty():
		return true
	return false

## ENTKOPPELT: Die Antwort wird SOFORT gesendet (die Aktion blockiert nie auf
## Screenshot/OCR). Bei unerwarteter Lage wird die Analyse als Fire-and-forget
## im Hintergrund gestartet und in _evidence_cache abgelegt — der Agent holt sie
## gezielt über runtime_visual_evidence, wenn er sie braucht.
func _send_tool_result_with_visual_evidence(id: Variant, tool_name: String, result: Variant, generation: int) -> void:
	if tool_name in UNEXPECTED_VISUAL_EXCLUSIONS or not _is_unexpected_result(result):
		_send_tool_result_atomic(id, result)
		return
	_start_background_evidence()
	if result is Dictionary:
		(result as Dictionary)["visual_evidence"] = {"status": "pending", "hint": "call runtime_visual_evidence (wait_ms) to fetch the analysis"}
	if generation == _connection_generation:
		_send_tool_result_atomic(id, result)


func _handle_visual_evidence(id: Variant, args: Dictionary, generation: int) -> void:
	var wait_ms := clampi(int(args.get("wait_ms", 0)), 0, 10000)
	if bool(args.get("capture", false)) and not _evidence_inflight and _evidence_cache.is_empty():
		_start_background_evidence()
	var waited := 0
	while _evidence_inflight and waited < wait_ms:
		await get_tree().create_timer(0.05).timeout
		waited += 50
		if generation != _connection_generation:
			return
	var status := "none"
	if not _evidence_cache.is_empty():
		status = "ready"
	elif _evidence_inflight:
		status = "pending"
	_send_tool_result_atomic(id, {"ok": true, "status": status, "evidence": _evidence_cache})


func _start_background_evidence() -> void:
	if _evidence_inflight:
		return
	_evidence_inflight = true
	_run_background_evidence()


func _run_background_evidence() -> void:
	var evidence := await _capture_visual_evidence()
	if not evidence.is_empty():
		_evidence_cache = evidence
	_evidence_inflight = false

func _capture_visual_evidence() -> Dictionary:
	var evidence: Dictionary = {}
	var shot: Variant = await _registry.dispatch_async("runtime_screenshot", {"persist_context": true})
	if shot is Dictionary and not shot.has("error") and not bool((shot as Dictionary).get("_error", false)):
		var shot_data: Dictionary = shot
		var quality: Dictionary = shot_data.get("screen_quality", {}) if shot_data.get("screen_quality") is Dictionary else {}
		evidence["screenshot"] = {
			"context_id": str(shot_data.get("context_id", "")),
			"width": int(shot_data.get("width", 0)),
			"height": int(shot_data.get("height", 0)),
			"quality": str(quality.get("quality", "")),
		}
		var context_id := str(shot_data.get("context_id", ""))
		if context_id != "" and _worker != null and is_instance_valid(_worker) and _worker.has_method("request"):
			var ocr_result: Variant = await _worker.request("ocr", {"context_id": context_id})
			if ocr_result is Dictionary:
				var ocr_data: Dictionary = ocr_result
				if ocr_data.has("ocr") and ocr_data.get("ocr") is Dictionary:
					evidence["ocr"] = ocr_data.get("ocr")
				elif ocr_data.has("error"):
					evidence["ocr"] = {"available": false, "reason": str(ocr_data.get("error", "vision worker error"))}
	return evidence


## Ein Schreib-Gate für beide Editier-Welten: Der Editor-Dock aktiviert
## Schreibzugriffe über "editor_write_enabled"; die Autonomy-Workspace-Tools
## (runtime_autonomy_write/patch/export) hängen am selben Gate. Vorher wurde
## autonomy_writes nie gesetzt → Editor-Editieren über das Panel war trotz
## "Allow write actions" gesperrt (echte Lücke im Edit↔Ingame-Wechsel).
static func _resolve_autonomy_writes(config: Dictionary) -> bool:
	return bool(config.get("autonomy_writes", false)) or bool(config.get("editor_write_enabled", false))


## Liest den Tail der Engine-Log-Datei, falls der Editor mit --log-file
## gestartet wurde (dokumentierter Start des Editor-MCP: --log-file).
func _read_engine_log_tail() -> Array:
	var log_path := ""
	var cmdline := OS.get_cmdline_args()
	var arg_index := cmdline.find("--log-file")
	if arg_index >= 0 and arg_index + 1 < cmdline.size():
		log_path = cmdline[arg_index + 1]
	else:
		for arg in cmdline:
			if arg.begins_with("--log-file="):
				log_path = arg.trim_prefix("--log-file=")
				break
	if log_path == "" or not FileAccess.file_exists(log_path):
		return []
	var file := FileAccess.open(log_path, FileAccess.READ)
	if file == null:
		return []
	var lines: Array = []
	file.seek_end()
	var size := file.get_length()
	var tail_bytes := mini(64 * 1024, size)
	file.seek(maxi(0, size - tail_bytes))
	if tail_bytes < size:
		file.get_line()  # verwerfe erste halbe Zeile
	while not file.eof_reached():
		var line := file.get_line()
		lines.append(line)
	file.close()
	return lines.slice(maxi(0, lines.size() - 200), lines.size())


func _is_editor_write_tool(tool_name: String) -> bool:
	return tool_name in [
		"editor_apply_transaction", "editor_create_node", "editor_delete_node",
		"editor_set_node_property", "editor_scene_save", "editor_undo",
		"editor_redo",
	]


func _is_game_running() -> bool:
	var main_loop := Engine.get_main_loop()
	return main_loop is SceneTree and (main_loop as SceneTree).current_scene != null


func _is_renderer_visible() -> bool:
	if _role == "editor":
		return Engine.is_editor_hint() or not OS.has_feature("headless")
	if OS.has_feature("headless") or "--headless" in OS.get_cmdline_args():
		return false
	var main_loop := Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return false
	var root := (main_loop as SceneTree).root
	if root == null:
		return false
	var texture := root.get_texture()
	return texture != null and texture.get_rid().is_valid()


func _dispose_worker() -> void:
	if _worker == null:
		return
	if _worker.has_method("stop_worker"):
		_worker.stop_worker()
	_worker.queue_free()
	_worker = null


func _create_vision_worker(config: Dictionary) -> void:
	var worker_script: Resource = load(VISION_WORKER_PATH)
	if worker_script == null:
		_note_error("Vision worker supervisor could not be loaded")
		return
	_worker = worker_script.new() as Node
	if _worker == null:
		_note_error("Vision worker supervisor did not instantiate")
		return
	_worker.name = "McpVisionWorker"
	add_child(_worker)
	if _worker.has_method("configure"):
		_worker.configure({
			"vision_worker_enabled": bool(config.get("vision_worker_enabled", true)),
			"vision_worker_command": str(config.get("vision_worker_command", "node")),
			"vision_worker_script": str(config.get("vision_worker_script", "res://addons/gdscript_mcp/client/vision_worker.js")),
			"vision_worker_port": int(config.get("vision_worker_port", 9127)),
			"vision_worker_ocr_command": str(config.get("vision_worker_ocr_command", "")),
			"context_root": _context_store.get_root_path() if _context_store != null else "",
		})


func _send_tool_result_atomic(id: Variant, result: Variant) -> void:
	var sanitized := _sanitize_result(result)
	var trim_result: Dictionary = McpProtocol.trim_result_to_budget(sanitized)
	var payload: Variant = trim_result.get("value", sanitized)
	if not bool(trim_result.get("fits", true)) and payload is Dictionary:
		(payload as Dictionary)["_response_truncated"] = true
		(payload as Dictionary)["_response_bytes"] = int(trim_result.get("trimmed_bytes", 0))
		(payload as Dictionary)["_truncated_fields"] = trim_result.get("truncated_fields", [])
	if not bool(trim_result.get("fits", true)):
		note_truncation(int(trim_result.get("original_bytes", 0)), int(trim_result.get("trimmed_bytes", 0)))
	var content: Array = [_protocol.text_content(JSON.stringify(payload))]
	_send_response(id, _protocol.tool_result(content, _protocol.result_is_error(result)), "", 0)


func note_truncation(original_bytes: int, trimmed_bytes: int) -> void:
	if _lifecycle != null:
		_lifecycle.note_event("warning", "Tool result trimmed %d → %d bytes" % [original_bytes, trimmed_bytes], "mcp", "budget")


func _sanitize_result(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			var key_text := str(key)
			# Only strip an explicit in-memory image marker if present. The
			# artifact-first pipeline never sends raw image bytes, so there is
			# no generic "data" field to remove — dropping any dictionary key
			# named "data" would risk real data loss in game-sourced results.
			if key_text == "_mcp_image":
				continue
			result[key_text] = _sanitize_result(value[key])
		return result
	if value is Array:
		var array: Array = []
		for item in value:
			array.append(_sanitize_result(item))
		return array
	if value is Object:
		return {"_class": value.get_class()}
	return value


func _send_response(id: Variant, result: Variant, error_message: String, code: int) -> void:
	var encoded: String = _protocol.encode_response(id, result, error_message, code)
	if _transport == "tcp" and _client != null:
		_client.put_data(encoded.to_utf8_buffer())
	elif _transport == "stdio":
		print(encoded.strip_edges())


func _note_error(message: String) -> void:
	_last_error = message
	if _lifecycle != null:
		_lifecycle.note_error(message)
	_log(message, true)


func _log(message: String, is_error: bool = false) -> void:
	if is_error:
		_last_error = message
	if _lifecycle != null:
		_lifecycle.note_event("error" if is_error else "info", message, "mcp", "server")
	log_message.emit(message, is_error)
	if _verbose or is_error:
		print("[McpServer/%s] %s" % [_role, message])
