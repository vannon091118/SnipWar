extends Node

## Runtime MCP host. It creates the MCP server as a child Node and leaves
## transport polling to that server's own _process lifecycle.
## Usage: godot -- --mcp [--mcp-port 9090] [--mcp-transport tcp]

const DEFAULT_PORT := 9090
const MCP_SERVER_PATH := "res://addons/gdscript_mcp/runtime/host/mcp_server.gd"
const INPUT_SCHEDULER_PATH := "res://addons/gdscript_mcp/runtime/tools/runtime/mcp_input_scheduler.gd"

var _server: Node
var _transport := ""
var _virtual_mouse_scheduler: Node


func _init() -> void:
	# The MCP host must outlive game pauses: same guarantee as the server child.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)


func _ready() -> void:
	var user_args := OS.get_cmdline_user_args()
	if not "--mcp" in user_args:
		return
	# Live-MCP requires a visible renderer. Headless / dummy renderers cannot
	# produce screenshots and the server must refuse to start.
	if OS.has_feature("headless") or "--headless" in OS.get_cmdline_args():
		push_warning("[McpRuntime] MCP server requires a visible renderer (--headless is not supported)")
		return
	var port := _parse_int_arg(user_args, "--mcp-port", DEFAULT_PORT)
	_transport = _parse_string_arg(user_args, "--mcp-transport", "tcp")
	var config := {
		"role": "runtime",
		"session_id": _parse_string_arg(user_args, "--mcp-session", "runtime_%d" % Time.get_ticks_msec()),
		"frame_budget_ms": _parse_float_arg(user_args, "--mcp-frame-budget", 1.5),
		"mcp_virtual_mouse": not ("--mcp-real-mouse" in user_args),
		"mcp_block_physical_mouse": not ("--mcp-allow-physical-mouse" in user_args),
		"mcp_virtual_mouse_cursor": not ("--mcp-hide-virtual-cursor" in user_args),
		"vision_worker_enabled": not ("--mcp-no-vision-worker" in user_args),
		"vision_worker_command": _parse_string_arg(user_args, "--mcp-vision-command", "node"),
		"vision_worker_script": _parse_string_arg(user_args, "--mcp-vision-script", "res://addons/gdscript_mcp/client/vision_worker.js"),
		"vision_worker_port": _parse_int_arg(user_args, "--mcp-vision-port", port + 37),
		"autonomy_writes": "--mcp-autonomy-writes" in user_args,
	}
	# Defer BOTH the scheduler attach and the server boot: during autoload
	# _ready() the SceneTree root is still setting up children, so a direct
	# add_child() would fail and leave the virtual-mouse scheduler detached
	# (with a second instance later created by the E2E driver's get_or_create).
	call_deferred("_activate_virtual_mouse", config)
	call_deferred("_boot_server", port, _transport, config)


func _input(event: InputEvent) -> void:
	if _virtual_mouse_scheduler == null or not is_instance_valid(_virtual_mouse_scheduler):
		return
	if not bool(_virtual_mouse_scheduler.call("is_physical_mouse_blocked")):
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		if event.has_meta(&"mcp_virtual_input") and bool(event.get_meta(&"mcp_virtual_input", false)):
			return
		if _virtual_mouse_scheduler.has_method("record_blocked_physical_mouse_event"):
			_virtual_mouse_scheduler.call("record_blocked_physical_mouse_event")
		get_viewport().set_input_as_handled()


func get_virtual_mouse_position() -> Vector2:
	if _virtual_mouse_scheduler != null and is_instance_valid(_virtual_mouse_scheduler) and _virtual_mouse_scheduler.has_method("get_virtual_mouse_status"):
		var status: Dictionary = _virtual_mouse_scheduler.call("get_virtual_mouse_status")
		var position: Dictionary = status.get("position", {})
		return Vector2(float(position.get("x", 0.0)), float(position.get("y", 0.0)))
	return get_viewport().get_mouse_position()


func get_virtual_mouse_status() -> Dictionary:
	if _virtual_mouse_scheduler != null and is_instance_valid(_virtual_mouse_scheduler) and _virtual_mouse_scheduler.has_method("get_virtual_mouse_status"):
		return _virtual_mouse_scheduler.call("get_virtual_mouse_status")
	return {"active": false, "physical_mouse_blocked": false}


func _activate_virtual_mouse(config: Dictionary) -> void:
	if not bool(config.get("mcp_virtual_mouse", true)):
		return
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	var existing := tree.root.get_node_or_null("McpInputScheduler")
	if existing != null:
		_virtual_mouse_scheduler = existing
	else:
		var scheduler_script: Resource = load(INPUT_SCHEDULER_PATH)
		if scheduler_script == null:
			return
		_virtual_mouse_scheduler = scheduler_script.new() as Node
		if _virtual_mouse_scheduler == null:
			return
		_virtual_mouse_scheduler.name = "McpInputScheduler"
		tree.root.add_child(_virtual_mouse_scheduler)
	if _virtual_mouse_scheduler.has_method("activate_virtual_mouse"):
		_virtual_mouse_scheduler.call("activate_virtual_mouse", str(config.get("session_id", "runtime")), Vector2(-1.0, -1.0), bool(config.get("mcp_block_physical_mouse", true)), bool(config.get("mcp_virtual_mouse_cursor", true)))


func _deactivate_virtual_mouse() -> void:
	if _virtual_mouse_scheduler != null and is_instance_valid(_virtual_mouse_scheduler) and _virtual_mouse_scheduler.has_method("deactivate_virtual_mouse"):
		_virtual_mouse_scheduler.call("deactivate_virtual_mouse")
	_virtual_mouse_scheduler = null


func _is_running() -> bool:
	return _server != null and is_instance_valid(_server) and _server.has_method("is_running") and _server.is_running()


func get_server() -> Node:
	return _server


func _boot_server(port: int, transport: String, config: Dictionary = {}) -> void:
	if not ResourceLoader.exists(MCP_SERVER_PATH):
		push_warning("[McpRuntime] MCP server script not found: " + MCP_SERVER_PATH)
		_deactivate_virtual_mouse()
		return
	var script: Resource = load(MCP_SERVER_PATH)
	if script == null:
		push_error("[McpRuntime] Failed to load MCP server script")
		_deactivate_virtual_mouse()
		return
	_server = script.new() as Node
	if _server == null:
		push_error("[McpRuntime] MCP server script did not instantiate a Node")
		_deactivate_virtual_mouse()
		return
	add_child(_server)
	if not _server.start_server(port, transport, config):
		push_warning("[McpRuntime] MCP server failed to start")
		_deactivate_virtual_mouse()
		_server.queue_free()
		_server = null
		return
	print("[McpRuntime] MCP server live on 127.0.0.1:" + str(port))


func _parse_int_arg(args: PackedStringArray, flag: String, default_value: int) -> int:
	for i in args.size():
		if args[i] == flag and i + 1 < args.size():
			return int(args[i + 1])
	return default_value


func _parse_string_arg(args: PackedStringArray, flag: String, default_value: String) -> String:
	for i in args.size():
		if args[i] == flag and i + 1 < args.size():
			return args[i + 1]
	return default_value


func _parse_float_arg(args: PackedStringArray, flag: String, default_value: float) -> float:
	for i in args.size():
		if args[i] == flag and i + 1 < args.size():
			return float(args[i + 1])
	return default_value


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _server != null and is_instance_valid(_server) and _server.has_method("stop_server"):
			_server.stop_server()
		_deactivate_virtual_mouse()
