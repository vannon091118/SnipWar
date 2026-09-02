extends RefCounted
class_name McpRunTrace

## McpRunTrace — einheitlicher Evidence-Record pro Run (F4).
##
## Bindet alle Beobachtungen eines autonomen QA-/Repair-Laufs an EINE Trace-ID:
##   - jeden Tool-Call (ok/Fehler, Latenz, kompakte Ergebnis-Summary)
##   - GameState-Fingerprints (game_state_summary) zu Beginn und am Ende
##   - Lifecycle-/Log-Events (Log-Delta)
##   - Visual-Evidence-Hinweise (Screenshot/OCR) — die Artefakte selbst liegen
##     im Context-Store, der Trace referenziert sie über context_id
##   - Verdict (PASS/FAIL) + Dauer
##
## Der Server startet/beendet den Trace automatisch an den Run-Grenzen
## (runtime_autonomy_workspace_begin/end) und exportiert ihn nach
## user://mcp_traces/<run_id>.json. Zusätzlich gibt es ein Host-Tool
## runtime_run_trace für manuelle Begin/End/Status/List/Read-Steuerung.

const TRACE_DIR := "user://mcp_traces"

var _run_id := ""
var _goal := ""
var _started_ms := 0
var _entries: Array[Dictionary] = []
var _tool_calls := 0
var _tool_errors := 0


## Startet einen neuen Trace. Fehlschlag, wenn bereits einer aktiv ist.
func begin(run_id: String, goal: String = "") -> Dictionary:
	if _run_id != "":
		return {"ok": false, "error": "trace already active: " + _run_id}
	if run_id.strip_edges() == "":
		return {"ok": false, "error": "run_id must not be empty"}
	_run_id = run_id.strip_edges()
	_goal = goal
	_started_ms = Time.get_ticks_msec()
	_entries = []
	_tool_calls = 0
	_tool_errors = 0
	_record("run_begin", {"run_id": _run_id, "goal": _goal})
	return {"ok": true, "run_id": _run_id}


## Beendet den Trace, exportiert ihn und liefert ein kompaktes Ergebnis.
func end(verdict: String = "", summary: Dictionary = {}) -> Dictionary:
	if _run_id == "":
		return {"ok": false, "error": "no active trace"}
	_record("run_end", {
		"verdict": verdict,
		"duration_ms": Time.get_ticks_msec() - _started_ms,
		"summary": summary,
	})
	var trace := snapshot(verdict)
	var trace_id := _run_id
	var export_path := export()
	_run_id = ""
	return {
		"ok": true,
		"run_id": trace_id,
		"verdict": verdict,
		"duration_ms": Time.get_ticks_msec() - _started_ms,
		"tool_calls": _tool_calls,
		"tool_errors": _tool_errors,
		"export_path": export_path,
	}


func active() -> bool:
	return _run_id != ""


func get_run_id() -> String:
	return _run_id


## Ein einzelner Tool-Call. summary bleibt kompakt (keine riesigen Payloads).
func record_tool(tool_name: String, ok: bool, latency_ms: float, error: String, summary: Variant = null, visual_evidence: Variant = null) -> void:
	if _run_id == "":
		return
	_tool_calls += 1
	if not ok:
		_tool_errors += 1
	var entry := {
		"kind": "tool",
		"tool": tool_name,
		"ok": ok,
		"latency_ms": snappedf(latency_ms, 0.1),
		"index": _tool_calls,
	}
	if error != "":
		entry["error"] = error
	if summary != null:
		entry["summary"] = summary
	if visual_evidence != null:
		entry["visual_evidence"] = visual_evidence
	_record("", entry)


## Beliebiger strukturierter Eintrag (Fingerprint, Event, Chain-Verdict, …).
func record(kind: String, data: Dictionary) -> void:
	if _run_id == "":
		return
	_record(kind, data)


## Komfort: Fingerprint-Eintrag (label + data).
func fingerprint(label: String, data: Variant) -> void:
	if _run_id == "":
		return
	_record("fingerprint", {"label": label, "data": data})


func snapshot(verdict: String = "") -> Dictionary:
	return {
		"run_id": _run_id,
		"goal": _goal,
		"verdict": verdict,
		"started_ms": _started_ms,
		"duration_ms": Time.get_ticks_msec() - _started_ms,
		"tool_calls": _tool_calls,
		"tool_errors": _tool_errors,
		"entries": _entries.duplicate(true),
	}


## Schreibt den Trace als JSON nach user://mcp_traces/<run_id>.json.
func export() -> String:
	if _run_id == "":
		return ""
	var dir := ProjectSettings.globalize_path(TRACE_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var safe_id := _run_id.replace("/", "_").replace("\\", "_").replace(":", "_")
	var path := "%s/%s.json" % [dir, safe_id]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(snapshot(), "  "))
	file.close()
	return path


## Listet exportierte Traces (Dateiname + Größe + mtime), neueste zuerst.
func list_exported() -> Array:
	var dir := ProjectSettings.globalize_path(TRACE_DIR)
	var traces: Array = []
	var da := DirAccess.open(dir)
	if da != null:
		da.list_dir_begin()
		var entry := da.get_next()
		while entry != "":
			if entry.ends_with(".json"):
				var abs := dir.path_join(entry)
				var size_bytes := 0
				var size_file := FileAccess.open(abs, FileAccess.READ)
				if size_file != null:
					size_bytes = size_file.get_length()
					size_file.close()
				traces.append({
					"run_id": entry.trim_suffix(".json"),
					"file": abs,
					"size_bytes": size_bytes,
					"modified_unix": FileAccess.get_modified_time(abs),
				})
			entry = da.get_next()
		da.list_dir_end()
	traces.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("modified_unix", 0.0)) > float(b.get("modified_unix", 0.0))
	)
	return traces


## Löscht exportierte Traces, deren mtime älter als max_days ist.
## Liefert die Anzahl gelöschter Dateien.
func prune(max_days: float) -> Dictionary:
	var dir := ProjectSettings.globalize_path(TRACE_DIR)
	var now := Time.get_unix_time_from_system()
	var cutoff := now - maxf(0.0, max_days) * 86400.0
	var removed_ids: Array = []
	var da := DirAccess.open(dir)
	if da != null:
		da.list_dir_begin()
		var entry := da.get_next()
		while entry != "":
			if entry.ends_with(".json"):
				var abs := dir.path_join(entry)
				if FileAccess.get_modified_time(abs) < cutoff:
					if DirAccess.remove_absolute(abs) == OK:
						removed_ids.append(entry.trim_suffix(".json"))
			entry = da.get_next()
		da.list_dir_end()
	removed_ids.sort()
	return {"ok": true, "removed": removed_ids.size(), "removed_ids": removed_ids, "max_days": max_days}


## Liest ein exportiertes Trace-JSON (run_id = Dateiname).
func read_exported(run_id: String) -> Dictionary:
	var safe_id := run_id.replace("/", "_").replace("\\", "_").replace(":", "_")
	var dir := ProjectSettings.globalize_path(TRACE_DIR)
	var path := "%s/%s.json" % [dir, safe_id]
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "trace not found: " + run_id}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "trace unreadable: " + run_id}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return {"ok": false, "error": "trace is not valid JSON: " + run_id}
	return {"ok": true, "trace": parsed}


func _record(kind: String, data: Dictionary) -> void:
	var entry := data.duplicate(true)
	entry["ts_ms"] = Time.get_ticks_msec() - _started_ms
	if kind != "":
		entry["kind"] = kind
	_entries.append(entry)