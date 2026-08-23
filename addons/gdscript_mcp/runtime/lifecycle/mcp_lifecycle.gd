extends RefCounted
class_name McpLifecycle

## Owns the MCP session clock, cooperative budget and compact diagnostics.
## The Godot server remains responsive while the game is paused or unfocused.

enum State {
	STOPPED = 0,
	BOOTING = 1,
	LISTENING = 2,
	READY = 3,
	BUSY = 4,
}

const MAX_EVENTS := 64
const DEFAULT_FRAME_BUDGET_MS := 1.5

var _state: int = State.STOPPED
var _started_at_ms := 0
var _tool_calls := 0
var _tool_errors := 0
var _last_tool_name := ""
var _last_tool_ms := 0.0
var _tool_ms_sum := 0.0
var _tool_ms_max := 0.0
var _tick_count := 0
var _last_tick_ms := 0
var _tick_ms_sum := 0.0
var _tick_ms_max := 0.0
var _frame_budget_ms := DEFAULT_FRAME_BUDGET_MS
var _dropped_jobs := 0
var _last_game_process_ms := 0.0
var _last_error := ""
var _role := "runtime"
var _session_id := ""
var _event_cursor := 0
var _events: Array[Dictionary] = []


func configure(role: String, session_id: String, frame_budget_ms: float = DEFAULT_FRAME_BUDGET_MS) -> void:
	_role = role if role != "" else "runtime"
	_session_id = session_id
	_frame_budget_ms = clampf(frame_budget_ms, 0.25, 8.0)


func start() -> void:
	_state = State.BOOTING
	_started_at_ms = Time.get_ticks_msec()
	_tool_calls = 0
	_tool_errors = 0
	_last_tool_name = ""
	_last_tool_ms = 0.0
	_tool_ms_sum = 0.0
	_tool_ms_max = 0.0
	_tick_count = 0
	_last_tick_ms = 0
	_tick_ms_sum = 0.0
	_tick_ms_max = 0.0
	_dropped_jobs = 0
	_last_game_process_ms = 0.0
	_last_error = ""
	_event_cursor = 0
	_events.clear()


func mark_listening(_transport: String, _port: int) -> void:
	_state = State.LISTENING


func mark_ready() -> void:
	_state = State.READY


func mark_busy(busy: bool) -> void:
	if busy and _state == State.READY:
		_state = State.BUSY
	elif not busy and _state == State.BUSY:
		_state = State.READY


func stop() -> void:
	_state = State.STOPPED


func begin_tool(name: String) -> int:
	_tool_calls += 1
	_last_tool_name = name
	return Time.get_ticks_msec()


func end_tool(name: String, started_ms: int) -> void:
	var latency := float(Time.get_ticks_msec() - started_ms)
	_last_tool_name = name
	_last_tool_ms = latency
	_tool_ms_sum += latency
	_tool_ms_max = maxf(_tool_ms_max, latency)


func note_error(detail: String) -> void:
	_tool_errors += 1
	_last_error = detail
	note_event("error", detail, "mcp")


func note_event(level: String, text: String, source: String = "mcp", category: String = "runtime") -> void:
	_event_cursor += 1
	_events.append({
		"cursor": _event_cursor,
		"source": source,
		"level": level,
		"category": category,
		"text": text,
		"stamp": Time.get_datetime_string_from_system(),
		"visible": false,
	})
	while _events.size() > MAX_EVENTS:
		_events.pop_front()


func events_since(cursor: int = 0, limit: int = 100) -> Dictionary:
	var safe_limit := clampi(limit, 1, MAX_EVENTS)
	var result: Array = []
	var next_cursor := maxi(0, cursor)
	for event in _events:
		var event_cursor := int(event.get("cursor", 0))
		if event_cursor <= cursor:
			continue
		result.append(event.duplicate(true))
		next_cursor = event_cursor
		if result.size() >= safe_limit:
			break
	var oldest_cursor := int(_events[0].get("cursor", 0)) if not _events.is_empty() else 0
	return {
		"entries": result,
		"count": result.size(),
		"next_cursor": next_cursor,
		"cursor_reset": cursor > 0 and oldest_cursor > cursor + 1,
	}


func note_job_drop(detail: String) -> void:
	_dropped_jobs += 1
	note_event("warning", detail, "mcp", "budget")


func can_run_visual() -> bool:
	return _last_game_process_ms <= 0.0 or _last_game_process_ms < 14.0


func tick(delta: float, game_process_ms: float = 0.0, queue_depth: int = 0) -> void:
	var started := Time.get_ticks_usec()
	_tick_count += 1
	_last_game_process_ms = maxf(0.0, game_process_ms)
	_last_tick_ms = Time.get_ticks_msec()
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	_tick_ms_sum += elapsed
	_tick_ms_max = maxf(_tick_ms_max, elapsed)
	if queue_depth > 0 and elapsed > _frame_budget_ms:
		note_job_drop("MCP tick exceeded frame budget with queue depth %d" % queue_depth)
	if delta < 0.0:
		note_event("warning", "Negative lifecycle delta received", "mcp", "clock")


func uptime_seconds() -> float:
	if _started_at_ms <= 0:
		return 0.0
	return float(Time.get_ticks_msec() - _started_at_ms) / 1000.0


func get_state_name() -> String:
	return state_name(_state)


static func state_name(state: int) -> String:
	match state:
		State.BOOTING:
			return "booting"
		State.LISTENING:
			return "listening"
		State.READY:
			return "ready"
		State.BUSY:
			return "busy"
		_:
			return "stopped"


func status(extra: Dictionary = {}) -> Dictionary:
	var avg_ms := 0.0
	if _tool_calls > 0:
		avg_ms = _tool_ms_sum / float(_tool_calls)
	var tick_avg_ms := 0.0
	if _tick_count > 0:
		tick_avg_ms = _tick_ms_sum / float(_tick_count)
	var result := {
		"state": get_state_name(),
		"role": _role,
		"session_id": _session_id,
		"uptime_seconds": uptime_seconds(),
		"tool_calls": _tool_calls,
		"tool_errors": _tool_errors,
		"last_tool": {"name": _last_tool_name, "latency_ms": _last_tool_ms},
		"tool_latency_avg_ms": avg_ms,
		"tool_latency_max_ms": _tool_ms_max,
		"tick_count": _tick_count,
		"last_tick_ms": _last_tick_ms,
		"tick_avg_ms": tick_avg_ms,
		"tick_max_ms": _tick_ms_max,
		"frame_budget_ms": _frame_budget_ms,
		"game_process_ms": _last_game_process_ms,
		"dropped_jobs": _dropped_jobs,
		"last_error": _last_error,
	}
	for key in extra:
		result[key] = extra[key]
	return result
