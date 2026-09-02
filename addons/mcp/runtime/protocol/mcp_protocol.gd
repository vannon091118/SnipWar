extends RefCounted
class_name McpProtocol

## McpProtocol — JSON-RPC 2.0 wire format for the MCP bridge.
## Pure static helpers, kept separate from transport + host lifecycle so the
## protocol layer is physically isolated (addons/mcp/runtime/protocol/).
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


## Default response budget: well below the 4 MiB transport buffer so a single
## oversized tool result (e.g. runtime_ux_analyze with include_visual on a
## large UI) can never break the newline-delimited JSON framing (MCP-Anomalie M1).
const DEFAULT_RESPONSE_BUDGET_BYTES := 200_000


## Trim a tool result to a byte budget. Returns:
##   {value, fits, original_bytes, trimmed_bytes, truncated_fields}
## Oversized arrays/dictionaries become truncated markers, oversized strings
## are cut with an explicit "..." suffix — a client can detect truncation via
## the marker instead of failing to parse (A6).
static func trim_result_to_budget(value: Variant, budget: int = DEFAULT_RESPONSE_BUDGET_BYTES) -> Dictionary:
	var safe_budget := maxi(1024, budget)
	var original := JSON.stringify(value) + "\n"
	var original_size := original.to_utf8_buffer().size()
	if original_size <= safe_budget:
		return {"value": value, "fits": true, "original_bytes": original_size,
			"trimmed_bytes": original_size, "truncated_fields": []}
	var state := {"budget": safe_budget, "used": 0, "truncated": []}
	var trimmed: Variant = _trim_value(value, state)
	var trimmed_size := (JSON.stringify(trimmed) + "\n").to_utf8_buffer().size()
	return {"value": trimmed, "fits": false, "original_bytes": original_size,
		"trimmed_bytes": trimmed_size, "truncated_fields": state["truncated"]}


static func _trim_value(value: Variant, state: Dictionary) -> Variant:
	if value is Dictionary:
		return _trim_dictionary(value, state)
	if value is Array:
		return _trim_array(value, state)
	if value is String or value is StringName:
		var text := str(value)
		var bytes := (JSON.stringify(text) + "\n").to_utf8_buffer().size()
		if int(state["used"]) + bytes <= int(state["budget"]):
			state["used"] = int(state["used"]) + bytes
			return value
		var remaining := maxi(64, int(state["budget"]) - int(state["used"]) - 64)
		var cut := text.substr(0, remaining) + "...(truncated)"
		state["used"] = int(state["budget"])
		state["truncated"].append("<string>")
		return cut
	state["used"] = int(state["used"]) + (JSON.stringify(value) + "\n").to_utf8_buffer().size()
	return value


static func _trim_dictionary(dict: Dictionary, state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var kept := 0
	var total := dict.size()
	var keys := dict.keys()
	keys.sort_custom(func(a, b): return str(a) < str(b))
	for key in keys:
		var entry := {str(key): dict[key]}
		var entry_bytes := (JSON.stringify(entry) + "\n").to_utf8_buffer().size()
		if int(state["used"]) + entry_bytes > int(state["budget"]) and kept > 0:
			result["_truncated"] = {"kept": kept, "total": total}
			state["truncated"].append(
				state.get("path", "") + "." + str(key) if str(state.get("path", "")) != "" else str(key))
			return result
		result[str(key)] = _trim_value(dict[key], state)
		kept += 1
	# Marker auch dann setzen, wenn KEIN Key verworfen wurde, aber ein Wert
	# per String-Cut gekürzt wurde — sonst ist ein Dict mit einem einzigen
	# großen String unerkannt getrümmert (Truncation-Vertrag A6).
	if kept < total or not (state["truncated"] as Array).is_empty():
		result["_truncated"] = {
			"kept": kept,
			"total": total,
			"truncated_fields": (state["truncated"] as Array).duplicate(true),
		}
		state["truncated"].append(state.get("path", "") + "<dict>")
	return result


static func _trim_array(array: Array, state: Dictionary) -> Array:
	var result: Array = []
	var total := array.size()
	for index in range(total):
		var entry := [array[index]]
		var entry_bytes := (JSON.stringify(entry) + "\n").to_utf8_buffer().size()
		if int(state["used"]) + entry_bytes > int(state["budget"]) and not result.is_empty():
			result.append({"_truncated": {"kept": result.size(), "total": total}})
			state["truncated"].append(state.get("path", "") + "<array>")
			return result
		result.append(_trim_value(array[index], state))
	if result.size() < total or not (state["truncated"] as Array).is_empty():
		result.append({"_truncated": {"kept": result.size(), "total": total}})
		state["truncated"].append(state.get("path", "") + "<array>")
	return result