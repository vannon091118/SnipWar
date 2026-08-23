extends RefCounted
class_name McpProtocol

## McpProtocol — JSON-RPC 2.0 wire format for the MCP bridge.
## Pure static helpers, kept separate from transport + host lifecycle so the
## protocol layer is physically isolated (addons/gdscript_mcp/runtime/protocol/).
##
## Protocol: Model Context Protocol (tools subset), newline-delimited JSON-RPC 2.0.

const PROTOCOL_VERSION_DEFAULT := "2024-11-05"
## Protocol revisions we can serve. The server echoes the client's requested
## version when it is one of these, otherwise falls back to the default.
const SUPPORTED_PROTOCOL_VERSIONS := ["2024-11-05", "2025-03-26", "2025-06-18", "2026-07-28"]


## Parse one newline-delimited JSON-RPC request line.
## Returns {"ok": true, "message": Dictionary} or {"ok": false, "error": String}.
static func parse_message(line: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(line)
	if parsed == null or not (parsed is Dictionary):
		return {"ok": false, "error": "invalid JSON"}
	return {"ok": true, "message": parsed}


## Encode a JSON-RPC response line (+ trailing newline).
static func encode_response(id: Variant, result: Variant, error_message: String = "", code: int = 0) -> String:
	var response := {"jsonrpc": "2.0", "id": id}
	if error_message != "":
		response["error"] = {"code": code, "message": error_message}
	else:
		response["result"] = result
	return JSON.stringify(response) + "\n"


static func text_content(text: String) -> Dictionary:
	return {"type": "text", "text": text}


## True when a tool result Variant signals an execution error (spec:
## tool execution errors are reported in tool results with isError: true).
static func result_is_error(result: Variant) -> bool:
	if result is Dictionary and str(result.get("error", "")) != "":
		return true
	return false


## Build the canonical MCP tool result payload.
static func tool_result(content: Array, is_error: bool = false) -> Dictionary:
	return {"content": content, "isError": is_error}


## Negotiate a protocol revision: echo the client's when supported.
static func negotiate_protocol_version(client_version: String) -> String:
	var requested := str(client_version).strip_edges()
	for supported in SUPPORTED_PROTOCOL_VERSIONS:
		if requested == supported:
			return supported
	return PROTOCOL_VERSION_DEFAULT