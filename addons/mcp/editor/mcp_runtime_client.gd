extends RefCounted
class_name McpRuntimeClient

## Persistenter TCP-MCP-Client für den Editor-Dock.
## Ein Socket + ein Handshake; jede Aktion ist genau ein tools/call auf der
## laufenden Verbindung (behebt MCP-Anomalie MCP-06: 30-60 s/Aktion durch
## Node-Neustart + Handshake pro Atom). Kein OS-Input nötig.
##
## Der Client hat bewusst einen begrenzten Verbindungs-/Handshake-Pfad:
## fehlende Runtime-Prozesse werden nicht still verschluckt und ein alter
## Socket kann den Dock nicht dauerhaft in einem falschen Zustand halten.

signal connected_changed(connected: bool)
signal error_occurred(message: String)

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 9090
const MAX_BUFFER_BYTES := 4 * 1024 * 1024
const CONNECT_TIMEOUT_MS := 4000
const HANDSHAKE_TIMEOUT_MS := 4000

var host := DEFAULT_HOST
var port := DEFAULT_PORT

var _socket: StreamPeerTCP = null
var _buffer := ""
var _next_request_id := 1
var _handshake_done := false
var _waiting_handshake := false
var _requests: Dictionary = {}
var _connect_started_ms := 0
var _handshake_started_ms := 0
var _no_delay_applied := false
var _last_error := ""


func connect_to(host_name: String = DEFAULT_HOST, port_number: int = DEFAULT_PORT) -> int:
	close()
	host = host_name
	port = port_number
	_last_error = ""
	_connect_started_ms = Time.get_ticks_msec()
	_handshake_started_ms = 0
	_socket = StreamPeerTCP.new()
	var err := _socket.connect_to_host(host, port)
	# TCP_NODELAY wird NICHT hier gesetzt: Auf Windows ist der Connect
	# asynchron, direkt nach connect_to_host() ist der Socket noch nicht offen
	# und set_no_delay() scheitert mit „Unable to set TCP no delay option“.
	# Das Flag wird in poll() gesetzt, sobald STATUS_CONNECTED erreicht ist.
	if err != OK:
		_fail_connection("connect failed: %s" % error_string(err))
		return err
	_waiting_handshake = true
	return OK


func close() -> void:
	_requests.clear()
	_buffer = ""
	_handshake_done = false
	_waiting_handshake = false
	_connect_started_ms = 0
	_handshake_started_ms = 0
	_no_delay_applied = false
	if _socket != null:
		_socket.disconnect_from_host()
		_socket = null


func is_connected_to() -> bool:
	if _socket == null:
		return false
	_socket.poll()
	return _socket.get_status() == StreamPeerTCP.STATUS_CONNECTED


func is_ready() -> bool:
	return is_connected_to() and _handshake_done


func get_status() -> Dictionary:
	var socket_status := "none"
	if _socket != null:
		match _socket.get_status():
			StreamPeerTCP.STATUS_CONNECTING:
				socket_status = "connecting"
			StreamPeerTCP.STATUS_CONNECTED:
				socket_status = "connected"
			StreamPeerTCP.STATUS_ERROR:
				socket_status = "error"
			_:
				socket_status = "closed"
	return {
		"host": host,
		"port": port,
		"socket": socket_status,
		"ready": _handshake_done,
		"waiting_handshake": _waiting_handshake,
		"last_error": _last_error,
		"requests": _requests.size(),
	}


## Wait for connect + initialize without blocking the editor thread.
## Returns a liveness receipt suitable for editor_run_project.
func wait_until_ready(timeout_ms: int = HANDSHAKE_TIMEOUT_MS) -> Dictionary:
	var started_ms := Time.get_ticks_msec()
	var deadline := started_ms + maxi(1, timeout_ms)
	while Time.get_ticks_msec() < deadline:
		poll()
		if is_ready():
			return {
				"ok": true,
				"ready": true,
				"elapsed_ms": Time.get_ticks_msec() - started_ms,
				"status": get_status(),
			}
		if _socket == null:
			return {
				"ok": false,
				"ready": false,
				"elapsed_ms": Time.get_ticks_msec() - started_ms,
				"error": _last_error if _last_error != "" else "runtime socket closed",
				"status": get_status(),
			}
		var main_loop := Engine.get_main_loop()
		if main_loop is SceneTree:
			await (main_loop as SceneTree).process_frame
		else:
			OS.delay_msec(1)
	if _socket != null:
		_fail_connection("MCP handshake timeout after %d ms" % timeout_ms)
	return {
		"ok": false,
		"ready": false,
		"elapsed_ms": Time.get_ticks_msec() - started_ms,
		"error": _last_error,
		"status": get_status(),
	}


## Sendet tools/call; Antwort kommt asynchron über den callback.
## Liefert die Request-ID oder -1 bei Fehler.
func call_tool(tool_name: String, args: Dictionary, callback: Callable) -> int:
	if not is_ready() or _socket == null:
		return -1
	var request_id := _next_request_id
	_next_request_id += 1
	_requests[request_id] = callback
	var message := {
		"jsonrpc": "2.0",
		"id": request_id,
		"method": "tools/call",
		"params": {"name": tool_name, "arguments": args},
	}
	var write_error: Error = _socket.put_data((JSON.stringify(message) + "\n").to_utf8_buffer())
	if write_error != OK:
		_requests.erase(request_id)
		_last_error = "request send failed: %s" % error_string(write_error)
		error_occurred.emit(_last_error)
		return -1
	return request_id


## Synchronous-looking helper for editor liveness probes. It still polls the
## same persistent transport and yields to the editor between frames.
func call_tool_and_wait(tool_name: String, args: Dictionary = {}, timeout_ms: int = 2500) -> Dictionary:
	var response: Dictionary = {}
	var completed := false
	var request_id := call_tool(tool_name, args, func(value: Dictionary):
		response = value
		completed = true
	)
	if request_id < 0:
		return {"ok": false, "error": _last_error if _last_error != "" else "request could not be sent"}
	var started_ms := Time.get_ticks_msec()
	var deadline := started_ms + maxi(1, timeout_ms)
	while not completed and Time.get_ticks_msec() < deadline:
		poll()
		if completed:
			break
		var main_loop := Engine.get_main_loop()
		if main_loop is SceneTree:
			await (main_loop as SceneTree).process_frame
		else:
			OS.delay_msec(1)
	if not completed:
		_requests.erase(request_id)
		return {
			"ok": false,
			"error": "MCP request timeout: " + tool_name,
			"elapsed_ms": Time.get_ticks_msec() - started_ms,
		}
	return {
		"ok": not response.has("error"),
		"response": response,
		"elapsed_ms": Time.get_ticks_msec() - started_ms,
	}


## Muss periodisch aufgerufen werden (Dock: _process). Verarbeitet Handshake
## und eingehende Responses.
func poll() -> void:
	if _socket == null:
		return
	_socket.poll()
	var status := _socket.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTING:
		if _connect_started_ms > 0 and Time.get_ticks_msec() - _connect_started_ms >= CONNECT_TIMEOUT_MS:
			_fail_connection("connect timeout after %d ms" % CONNECT_TIMEOUT_MS)
		return
	if status != StreamPeerTCP.STATUS_CONNECTED:
		_fail_connection("connection lost" if _handshake_done else "connection failed")
		return
	# Socket ist jetzt wirklich offen — TCP_NODELAY hier setzen, sonst kostet
	# jeder MCP-Roundtrip durch Nagle zusätzliche Latenz („Unable to set TCP
	# no delay option“ vorher war still verloren).
	if not _no_delay_applied:
		_socket.set_no_delay(true)
		_no_delay_applied = true
	if _waiting_handshake:
		_waiting_handshake = false
		_handshake_started_ms = Time.get_ticks_msec()
		if not _send_handshake():
			return
	elif not _handshake_done and _handshake_started_ms > 0 and Time.get_ticks_msec() - _handshake_started_ms >= HANDSHAKE_TIMEOUT_MS:
		_fail_connection("MCP initialize timeout after %d ms" % HANDSHAKE_TIMEOUT_MS)
		return
	var available := _socket.get_available_bytes()
	if available <= 0:
		return
	var packet: Array = _socket.get_data(available)
	if packet.size() < 2 or int(packet[0]) != OK:
		_fail_connection("socket read failed")
		return
	var bytes: PackedByteArray = packet[1] as PackedByteArray
	if bytes == null:
		_fail_connection("socket returned invalid data")
		return
	_buffer += bytes.get_string_from_utf8()
	if _buffer.to_utf8_buffer().size() > MAX_BUFFER_BYTES:
		_fail_connection("response buffer exceeded limit")
		return
	_parse_lines()


func _parse_lines() -> void:
	while true:
		var newline := _buffer.find("\n")
		if newline < 0:
			return
		var line := _buffer.substr(0, newline).strip_edges()
		_buffer = _buffer.substr(newline + 1)
		if line == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if not (parsed is Dictionary):
			continue
		var response: Dictionary = parsed
		var response_id: Variant = response.get("id", null)
		if response_id is int and _requests.has(int(response_id)):
			var callback: Callable = _requests[int(response_id)]
			_requests.erase(int(response_id))
			callback.call(response)


func _send_handshake() -> bool:
	if _socket == null:
		return false
	_next_request_id = 1
	_requests.clear()
	var init_id := _next_request_id
	_next_request_id += 1
	_requests[init_id] = Callable(self, "_on_initialize_response")
	var initialize := {
		"jsonrpc": "2.0",
		"id": init_id,
		"method": "initialize",
		"params": {"protocolVersion": "2024-11-05"},
	}
	var initialize_error: Error = _socket.put_data((JSON.stringify(initialize) + "\n").to_utf8_buffer())
	if initialize_error != OK:
		_fail_connection("initialize send failed: %s" % error_string(initialize_error))
		return false
	var initialized := {
		"jsonrpc": "2.0",
		"id": _next_request_id,
		"method": "initialized",
		"params": {},
	}
	_next_request_id += 1
	var initialized_error: Error = _socket.put_data((JSON.stringify(initialized) + "\n").to_utf8_buffer())
	if initialized_error != OK:
		_fail_connection("initialized send failed: %s" % error_string(initialized_error))
		return false
	return true


func _on_initialize_response(response: Dictionary) -> void:
	if response.has("error"):
		_fail_connection("MCP initialize failed: " + str(response.get("error", {})))
		return
	_handshake_done = true
	_handshake_started_ms = 0
	_last_error = ""
	connected_changed.emit(true)


func _fail_connection(message: String) -> void:
	var was_ready := _handshake_done
	_last_error = message
	close()
	if was_ready:
		connected_changed.emit(false)
	error_occurred.emit(message)
