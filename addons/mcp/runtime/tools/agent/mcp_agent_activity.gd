extends RefCounted
class_name McpAgentActivity

## Agent-Activity-Telemetrie: Was der Agent gerade tut, was die letzten
## Schritte waren und was das aktuelle Ziel ist — ohne Rückfrage an den
## Agenten. Jeder Tool-Call wird automatisch erfasst; der Mensch sieht den
## Feed im Panel und über die MCP-Resource godot://agent/activity.

const MAX_ENTRIES := 200

var _goal := ""
var _entries: Array = []
var _entry_seq := 0


func set_goal(goal: String) -> Dictionary:
	_goal = goal.strip_edges()
	_record(&"agent_goal_set", {"goal": _goal}, 0.0, true, "")
	return {"ok": true, "goal": _goal}


func get_goal() -> String:
	return _goal


func record_tool(tool_name: String, args: Dictionary, duration_ms: float, ok: bool, error_text: String = "") -> void:
	_record("call:" + tool_name, _sanitize_args(args), duration_ms, ok, error_text)


func get_feed(limit: int = 20) -> Dictionary:
	var safe_limit := clampi(limit, 1, MAX_ENTRIES)
	var out: Array = []
	for i in range(MAX_ENTRIES):
		var idx := _entries.size() - 1 - i
		if idx < 0:
			break
		out.append(_entries[idx].duplicate(true))
		if out.size() >= safe_limit:
			break
	out.reverse()
	return {
		"goal": get_goal(),
		"entries": out,
		"count": out.size(),
		"total_calls": _entries.size(),
	}


func get_stats() -> Dictionary:
	var ok_count := 0
	var err_count := 0
	for e in _entries:
		if bool(e.get("ok", false)):
			ok_count += 1
		else:
			err_count += 1
	return {"goal": _goal, "records": _entries.size(), "ok": ok_count, "errors": err_count}


func _record(label: String, args: Dictionary, duration_ms: float, ok: bool, error_text: String) -> void:
	_entry_seq += 1
	_entries.append({
		"seq": _entry_seq,
	"label": label,
	"args": args,
	"ts_ms": Time.get_ticks_msec(),
	"duration_ms": duration_ms,
	"ok": ok,
	"error": error_text.strip_edges() if error_text != "" else "",
	})
	if _entries.size() > MAX_ENTRIES:
			_entries.pop_front()


## Args sanitisieren: nur kurze Werte (erste 200 Zeichen, keine Bilder/Blobs).
func _sanitize_args(args: Dictionary) -> Dictionary:
	var out := {}
	for key in args:
		if out.size() >= 8:
			break
		var val: Variant = args[key]
		if val is String:
			out[str(key)] = (val as String).substr(0, 200)
		elif val is bool or val is int or val is float:
			out[str(key)] = val
		elif val is Dictionary or val is Array:
			var size: int = (val as Array).size() if val is Array else (val as Dictionary).size()
			out[str(key)] = "<" + ("Array" if val is Array else "Dictionary") + ":" + str(size) + ">"
		else:
			out[str(key)] = "<" + str(typeof(val)) + ">"
	return out