extends RefCounted
class_name McpRuntimeClient

## Persistenter TCP-MCP-Client für den Editor-Dock.
## Ein Socket + ein Handshake; jede Aktion ist genau ein tools/call auf der
## laufenden Verbindung (behebt MCP-Anomalie MCP-06: 30-60 s/Aktion durch
## Node-Neustart + Handshake pro Atom). Kein OS-Input nötig.

signal connected_changed(connected: bool)
signal error_occurred(message: String)

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 9090
const MAX_BUFFER_BYTES := 4 * 1024 * 1024

var host := DEFAULT_HOST
var port := DEFAULT_PORT

var _socket: StreamPeerTCP = null
var _buffer := ""
var _next_request_id := 1
var _handshake_done := false
var _waiting_handshake := false
var _requests: Dictionary = {}


func connect_to(host_name: String = DEFAULT_HOST, port_number: int = DEFAULT_PORT) -> int:
	close()
	host = host_name
	port = port_number
	_socket = StreamPeerTCP.new()
	_socket.set_no_delay(true)
	var err := _socket.connect_to_host(host, port)
	if err != OK:
		_socket = null
		error_occurred.emit("connect failed: %s" % error_string(err))
		return err
	_waiting_handshake = true
	return OK


func close() -> void:
	_requests.clear()
	_buffer = ""
	_handshake_done = false
	_waiting_handshake = false
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
	_socket.put_data((JSON.stringify(message) + "\n").to_utf8_buffer())
	return request_id


## Muss periodisch aufgerufen werden (Dock: _process). Verarbeitet Handshake
## und eingehende Responses.
func poll() -> void:
	if _socket == null:
		return
	_socket.poll()
	var status := _socket.get_status()
	if status == StreamPeerTCP.STATUS_CONNECTING:
		return
	if status != StreamPeerTCP.STATUS_CONNECTED:
		var was_connected := _handshake_done
		close()
		if was_connected:
			connected_changed.emit(false)
			error_occurred.emit("connection lost")
		return
	if _waiting_handshake:
		_waiting_handshake = false
		_send_handshake()
	var available := _socket.get_available_bytes()
	if available <= 0:
		return
	var packet: Array = _socket.get_data(available)
	if packet.size() < 2 or int(packet[0]) != OK:
		error_occurred.emit("socket read failed")
		return
	var bytes: PackedByteArray = packet[1] as PackedByteArray
	if bytes == null:
		return
	_buffer += bytes.get_string_from_utf8()
	if _buffer.to_utf8_buffer().size() > MAX_BUFFER_BYTES:
		_buffer = ""
		error_occurred.emit("response buffer exceeded limit")
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


func _send_handshake() -> void:
	if _socket == null:
		return
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
	_socket.put_data((JSON.stringify(initialize) + "\n").to_utf8_buffer())
	var initialized := {
		"jsonrpc": "2.0",
		"id": _next_request_id,
		"method": "initialized",
		"params": {},
	}
	_next_request_id += 1
	_socket.put_data((JSON.stringify(initialized) + "\n").to_utf8_buffer())


func _on_initialize_response(_response: Dictionary) -> void:
	_handshake_done = true
	connected_changed.emit(true)