extends Node

## Supervises one local Python vision worker per MCP runtime session.
## The worker reads local context artifacts; image bytes never cross MCP.

const DEFAULT_COMMAND := "python"
const DEFAULT_PORT := 9127
const DEFAULT_SCRIPT := "res://addons/gdscript_mcp/client/vision_worker.py"

var _script_path := DEFAULT_SCRIPT
var _context_root := ""
var _ocr_command := ""
const CONNECT_TIMEOUT_MS := 2500
const REQUEST_TIMEOUT_MS := 60000
const MAX_PENDING := 4
const MAX_BUFFER_BYTES := 1024 * 1024

var _command := DEFAULT_COMMAND
var _port := DEFAULT_PORT
var _worker_pid := -1
var _peer: StreamPeerTCP
var _buffer := ""
var _next_id := 0
var _pending: Dictionary = {}
var _responses: Dictionary = {}
var _last_error := ""
var _started_at_ms := 0
var _enabled := true
var _starting := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)


func configure(config: Dictionary = {}) -> void:
	_command = str(config.get("vision_worker_command", DEFAULT_COMMAND))
	_script_path = str(config.get("vision_worker_script", DEFAULT_SCRIPT))
	_context_root = str(config.get("context_root", ""))
	_ocr_command = str(config.get("vision_worker_ocr_command", ""))
	_port = clampi(int(config.get("vision_worker_port", DEFAULT_PORT)), 1024, 65535)
	_enabled = bool(config.get("vision_worker_enabled", true))


func get_status() -> Dictionary:
	var connected := _peer != null and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED
	return {
		"enabled": _enabled,
		"connected": connected,
		"starting": _starting,
		"pid": _worker_pid,
		"port": _port,
		"pending": _pending.size(),
		"capacity": MAX_PENDING,
		"last_error": _last_error,
		"uptime_seconds": float(Time.get_ticks_msec() - _started_at_ms) / 1000.0 if _started_at_ms > 0 else 0.0,
		"process_mode": "ALWAYS",
	}


func request(operation: String, args: Dictionary) -> Dictionary:
	if not _enabled:
		return {"error": "vision worker disabled", "worker": get_status()}
	if _pending.size() >= MAX_PENDING:
		return {"error": "vision worker queue full", "worker": get_status()}
	if not await _ensure_connected():
		return {"error": _last_error if _last_error != "" else "vision worker unavailable", "worker": get_status()}

	_next_id += 1
	var request_id := "job_%d" % _next_id
	_pending[request_id] = true
	var payload := {"id": request_id, "operation": operation}
	for key in args:
		payload[key] = args[key]
	var encoded := JSON.stringify(payload) + "\n"
	if encoded.to_utf8_buffer().size() > MAX_BUFFER_BYTES:
		_pending.erase(request_id)
		return {"error": "vision worker request too large"}
	_peer.put_data(encoded.to_utf8_buffer())

	var deadline := Time.get_ticks_msec() + REQUEST_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		_poll_peer()
		if _responses.has(request_id):
			var response: Dictionary = _responses[request_id]
			_responses.erase(request_id)
			_pending.erase(request_id)
			return response
		await get_tree().process_frame
	_pending.erase(request_id)
	_responses.erase(request_id)
	_reset_worker_transport()
	_last_error = "vision worker request timed out: " + operation
	return {"error": _last_error, "worker": get_status()}


func stop_worker() -> void:
	_pending.clear()
	_reset_worker_transport()
	_starting = false


func _reset_worker_transport() -> void:
	_responses.clear()
	_buffer = ""
	if _peer != null:
		_peer.disconnect_from_host()
		_peer = null
	if _worker_pid > 0:
		OS.kill(_worker_pid)
	_worker_pid = -1


func _ensure_connected() -> bool:
	if _peer != null and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		return true
	if _starting:
		var start_deadline := Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
		while _starting and Time.get_ticks_msec() < start_deadline:
			_try_connect()
			if _peer != null and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				return true
			await get_tree().process_frame
		return _peer != null and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED
	return await _start_worker_and_connect()


func _start_worker_and_connect() -> bool:
	_reset_worker_transport()
	_pending.clear()
	_starting = true
	_last_error = ""
	var script_path := _script_path
	if script_path.begins_with("res://"):
		script_path = ProjectSettings.globalize_path(script_path)
	var context_root := _context_root
	if context_root == "":
		context_root = ProjectSettings.globalize_path("user://mcp_context")
	var args := [script_path, "--serve", "--host", "127.0.0.1", "--port", str(_port), "--context-root", context_root]
	if _ocr_command != "":
		args.append("--ocr-command")
		args.append(_ocr_command)
	_worker_pid = OS.create_process(_command, args, false)
	if _worker_pid < 0:
		_starting = false
		_last_error = "could not start vision worker command: " + _command
		return false
	_started_at_ms = Time.get_ticks_msec()
	var deadline := Time.get_ticks_msec() + CONNECT_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		_try_connect()
		if _peer != null and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			_starting = false
			return true
		await get_tree().process_frame
	_starting = false
	if _peer != null:
		_peer.disconnect_from_host()
		_peer = null
	if _worker_pid > 0:
		OS.kill(_worker_pid)
	_worker_pid = -1
	_last_error = "vision worker did not accept a connection on port %d" % _port
	return false


func _try_connect() -> void:
	if _peer != null:
		_peer.poll()
		var current_status := _peer.get_status()
		if current_status == StreamPeerTCP.STATUS_CONNECTED or current_status == StreamPeerTCP.STATUS_CONNECTING:
			return
		_peer = null
	var candidate := StreamPeerTCP.new()
	var error: int = candidate.connect_to_host("127.0.0.1", _port)
	if error == OK:
		_peer = candidate
		_peer.poll()
		_buffer = ""
	else:
		candidate.disconnect_from_host()


func _process(_delta: float) -> void:
	if _peer != null:
		_poll_peer()


func _poll_peer() -> void:
	if _peer == null:
		return
	_peer.poll()
	var peer_status := _peer.get_status()
	if peer_status == StreamPeerTCP.STATUS_CONNECTING:
		return
	if peer_status != StreamPeerTCP.STATUS_CONNECTED:
		_reset_worker_transport()
		_pending.clear()
		return
	var available := _peer.get_available_bytes()
	if available <= 0:
		return
	var packet: Array = _peer.get_data(available)
	if packet.size() < 2 or int(packet[0]) != OK:
		_last_error = "vision worker socket read failed"
		return
	var bytes: PackedByteArray = packet[1] as PackedByteArray
	if bytes == null:
		return
	_buffer += bytes.get_string_from_utf8()
	if _buffer.length() > MAX_BUFFER_BYTES:
		_buffer = ""
		_last_error = "vision worker response buffer exceeded limit"
		return
	while true:
		var newline := _buffer.find("\n")
		if newline < 0:
			break
		var line := _buffer.substr(0, newline).strip_edges()
		_buffer = _buffer.substr(newline + 1)
		if line == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			var response: Dictionary = parsed
			var response_id := str(response.get("id", ""))
			if _pending.has(response_id):
				_responses[response_id] = response
