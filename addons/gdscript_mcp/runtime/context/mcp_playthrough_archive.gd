extends RefCounted
class_name McpPlaythroughArchive

## McpPlaythroughArchive — persistent, local playthrough context + success store.
##
## Purpose: let an agent drive the game autonomously over time by remembering
## which actions succeeded. Every successful game-mechanic action is appended
## to user://mcp_playthrough/playthrough.jsonl together with:
##   - action metadata (tool/scenario, mechanic, context, result summary)
##   - a snapshot image (PNG, user://mcp_playthrough/frames/<id>.png) for
##     code+based AND image-based efficient agent work (no idle-loss)
##   - a state fingerprint (GameState.snapshot_run when available) so the
##     situation is reproducible later.
##
## The archive is the project's "DB / context storage": append-only JSONL,
## atomically rewritten, always local. No remote calls.

const ROOT_PATH := "user://mcp_playthrough"
const FRAME_DIR := "user://mcp_playthrough/frames"
const SNAPSHOT_DIR := "user://mcp_playthrough/snapshots"
const SCRIPT_DIR := "user://mcp_playthrough/scripts"
const LOG_FILE := "user://mcp_playthrough/playthrough.jsonl"
const LOG_FILE_TMP := "user://mcp_playthrough/playthrough.jsonl.tmp"
const SCRIPT_INDEX_FILE := "user://mcp_playthrough/scripts/index.jsonl"
const SCRIPT_INDEX_TMP := "user://mcp_playthrough/scripts/index.jsonl.tmp"
const MAX_LOG_ENTRIES := 2048
const MAX_SCRIPT_ENTRIES := 512

## Monotonic within a process; unix-time based so ids stay unique across runs
## (get_ticks_msec() restarts at 0 each process and would collide/overwrite
## frame files of an earlier session).
var _last_entry_id := 0


func _init() -> void:
	_ensure_dirs()


func log_success(action: String, metadata: Dictionary = {}, image: Image = null) -> Dictionary:
	_ensure_dirs()
	var entry_id := _next_entry()
	var status := str(metadata.get("verdict", "TO_CHECK"))
	var record := {
		"id": entry_id,
		"ts": Time.get_unix_time_from_system(),
		"action": action,
		"verdict": status,
		"solved_count": int(metadata.get("solved_count", 0)),
		"fail_count": int(metadata.get("fail_count", 0)),
		"block_reason": str(metadata.get("block_reason", "")),
		"meta": metadata.duplicate(true),
	}
	var img := image if (image != null and not image.is_empty()) else await _capture_frame()
	# Persist frame only for non-trivial outcomes (anomalies, milestones)
	if status in ["SOLVED", "MCP_ISSUE", "GAME_ISSUE", "BLOCKED"]:
		if img != null:
			var rel := FRAME_DIR.path_join("frame_%d.png" % entry_id)
			var abs := ProjectSettings.globalize_path(rel)
			var file := FileAccess.open(abs, FileAccess.WRITE)
			if file != null:
				file.store_buffer(img.save_png_to_buffer())
				file.close()
				record["frame"] = rel
	var snapshot: Variant = _capture_game_state()
	var preset_path := _save_snapshot(entry_id, snapshot)
	if preset_path != "":
		record["preset"] = preset_path
	_append_record(record)
	return record.duplicate(true)


## Active lookup by the agent: search successful actions + optional frame.
func search(query: String = "", limit: int = 20) -> Dictionary:
	var safe_limit := maxi(0, limit)
	var records := _read_records()
	var q := query.to_lower().strip_edges()
	var hits: Array = []
	for record in records:
		if q == "" or q in String(record.get("action", "")).to_lower() \
				or q in JSON.stringify(record.get("meta", {})).to_lower():
			hits.append(record)
	hits.reverse()
	if hits.size() > safe_limit:
		hits = hits.slice(0, safe_limit)
	return {"count": hits.size(), "entries": hits}


## Latest N records (newest first) — for the agent to continue a playthrough.
func latest(limit: int = 10) -> Dictionary:
	var safe_limit := maxi(0, limit)
	var records := _read_records()
	records.reverse()
	if records.size() > safe_limit:
		records = records.slice(0, safe_limit)
	return {"count": records.size(), "entries": records}


func stats() -> Dictionary:
	var records := _read_records()
	return {
		"entries": records.size(),
		"root": ProjectSettings.globalize_path(ROOT_PATH),
		"actions": _count_by_action(records),
	}


# ═══════════════════════════════════════════════════════════════════════════
# Script Archive — Agent-Scripts kategorisieren und zuweisen
# ═══════════════════════════════════════════════════════════════════════════

## Archiviere ein funktionierendes Agent-Script in index.jsonl.
## name: eindeutiger Name (z.B. "camera_move_to")
## category: Kategorie (runtime, gameplay, e2e, ux, fix)
## path: user://-Pfad zum Script (z.B. "user://mcp_playthrough/scripts/camera_move_to.gd")
## verdict: PASS oder FAIL
## tested_with: Array von E2E-Szenarien die das Script bestanden haben
## description: Kurzbeschreibung
func log_script(name: String, category: String, path: String, verdict: String, tested_with: Array = [], description: String = "") -> Dictionary:
	_ensure_dirs()
	var record := {
		"name": name,
		"category": category,
		"path": path,
		"verdict": verdict,
		"tested_with": tested_with,
		"description": description,
		"session": Time.get_datetime_string_from_system().left(10),
		"ts": Time.get_unix_time_from_system(),
	}
	_append_script_record(record)
	return record.duplicate(true)


## Suche Scripts nach Kategorie oder Name.
## query: Suchbegriff ( leer = alle )
## category: Nur diese Kategorie ( leer = alle )
## limit: Maximale Ergebnisse
func search_scripts(query: String = "", category: String = "", limit: int = 20) -> Dictionary:
	var safe_limit := maxi(0, limit)
	var records := _read_script_records()
	var q := query.to_lower().strip_edges()
	var cat := category.to_lower().strip_edges()
	var hits: Array = []
	for record in records:
		if cat != "" and String(record.get("category", "")).to_lower() != cat:
			continue
		if q != "" and q not in String(record.get("name", "")).to_lower() \
				and q not in String(record.get("description", "")).to_lower():
			continue
		hits.append(record)
	hits.reverse()
	if hits.size() > safe_limit:
		hits = hits.slice(0, safe_limit)
	return {"count": hits.size(), "entries": hits}


## Die neuesten N Scripts (neueste zuerst) — für den nächsten Agenten.
func latest_scripts(limit: int = 10) -> Dictionary:
	var safe_limit := maxi(0, limit)
	var records := _read_script_records()
	records.reverse()
	if records.size() > safe_limit:
		records = records.slice(0, safe_limit)
	return {"count": records.size(), "entries": records}


## Statistiken über archivierte Scripts.
func script_stats() -> Dictionary:
	var records := _read_script_records()
	var by_category: Dictionary = {}
	var by_verdict: Dictionary = {}
	for record in records:
		var cat := str(record.get("category", "unknown"))
		by_category[cat] = by_category.get(cat, 0) + 1
		var ver := str(record.get("verdict", "unknown"))
		by_verdict[ver] = by_verdict.get(ver, 0) + 1
	return {
		"total": records.size(),
		"by_category": by_category,
		"by_verdict": by_verdict,
	}


func _append_script_record(record: Dictionary) -> void:
	var records := _read_script_records()
	# Update existing entry with same name, or append new
	var found := false
	for i in range(records.size()):
		if str(records[i].get("name", "")) == str(record.get("name", "")):
			records[i] = record
			found = true
			break
	if not found:
		records.append(record)
	if records.size() > MAX_SCRIPT_ENTRIES:
		records = records.slice(records.size() - MAX_SCRIPT_ENTRIES)
	var lines: Array[String] = []
	for r in records:
		lines.append(JSON.stringify(r))
	var tmp_path := ProjectSettings.globalize_path(SCRIPT_INDEX_TMP)
	var path := ProjectSettings.globalize_path(SCRIPT_INDEX_FILE)
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("\n".join(lines) + "\n")
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var rename_error := DirAccess.rename_absolute(tmp_path, path)
	if rename_error != OK:
		DirAccess.remove_absolute(tmp_path)


func _read_script_records() -> Array:
	var path := ProjectSettings.globalize_path(SCRIPT_INDEX_FILE)
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var records: Array = []
	var text := file.get_as_text()
	file.close()
	for line in text.split("\n"):
		var line_clean := line.strip_edges()
		if line_clean == "":
			continue
		var parsed: Variant = JSON.parse_string(line_clean)
		if parsed is Dictionary:
			records.append(parsed)
	return records


## Read all frames referenced by records (for image-based play). Keys are ids.
func frames(limit: int = 8) -> Dictionary:
	var safe_limit := maxi(0, limit)
	var records := _read_records()
	records.reverse()
	var frames: Dictionary = {}
	var count := 0
	for record in records:
		if count >= safe_limit:
			break
		var frame_path := String(record.get("frame", ""))
		if frame_path != "" and FileAccess.file_exists(frame_path):
			frames[str(record.get("id", ""))] = frame_path
			count += 1
	return {"count": count, "frames": frames}


## In-engine play: apply a stored snapshot back onto GameState (reproducible
## situation = preset load). The snapshot is a RunSaveData saved as .tres.
func apply_snapshot(entry_id: String) -> Dictionary:
	var record := _find_record(entry_id)
	if record.is_empty():
		return {"ok": false, "reason": "not_found"}
	var preset_path := String(record.get("preset", ""))
	if preset_path == "" or not ResourceLoader.exists(preset_path):
		return {"ok": false, "reason": "no_preset"}
	var snapshot: Variant = ResourceLoader.load(preset_path)

	# Prefer adapter for cross-project state restore
	var ml: Object = Engine.get_main_loop()
	if ml is SceneTree:
		var adapter: Node = (ml as SceneTree).root.get_node_or_null("/root/McpProjectAdapter")
		if adapter != null and adapter.has_method("snapshot_restore"):
			var restored: bool = adapter.snapshot_restore(snapshot)
			return {"ok": restored, "preset": preset_path, "action": str(record.get("action", "")),
				"reconnect": true} if restored else {"ok": false, "reason": "restore_rejected"}

	var game_state: Node = _get_game_state()
	if game_state == null or not game_state.has_method("restore_run"):
		return {"ok": false, "reason": "no_game_state"}
	var restored: bool = game_state.call("restore_run", snapshot)
	if not restored:
		return {"ok": false, "reason": "restore_rejected"}
	return {"ok": true, "preset": preset_path, "action": str(record.get("action", "")), "reconnect": true}


func _get_game_state() -> Node:
	var ml: Object = Engine.get_main_loop()
	if ml is SceneTree:
		var adapter: Node = (ml as SceneTree).root.get_node_or_null("/root/McpProjectAdapter")
		if adapter != null and adapter.has_method("snapshot_capture"):
			return adapter
		return (ml as SceneTree).root.get_node_or_null("/root/GameState")
	return null


func _capture_game_state() -> Variant:
	var ml: Object = Engine.get_main_loop()
	if ml is SceneTree:
		# Prefer adapter for cross-project state snapshots
		var adapter: Node = (ml as SceneTree).root.get_node_or_null("/root/McpProjectAdapter")
		if adapter != null and adapter.has_method("snapshot_capture"):
			return adapter.snapshot_capture()
	var game_state := _get_game_state()
	if game_state != null and game_state.has_method("snapshot_run"):
		return game_state.call("snapshot_run")
	return null


## Real viewport frame (full renderer). Headless/dummy renderer: RID is null,
## get_image() crashes — guard via cmdline flag + await frame_post_draw.
func _capture_frame() -> Image:
	if OS.has_feature("headless") or "--headless" in OS.get_cmdline_args():
		return null
	var ml: Object = Engine.get_main_loop()
	if not (ml is SceneTree):
		return null
	var viewport := (ml as SceneTree).root
	if viewport == null:
		return null
	var texture: Texture2D = viewport.get_texture()
	if texture == null:
		return null
	if not texture.get_rid().is_valid():
		return null
	# Godot 4.7: await frame_post_draw before get_image().
	await RenderingServer.frame_post_draw
	var image := texture.get_image()
	return image if (image != null and not image.is_empty()) else null


## Save a RunSaveData preset to disk; returns the user:// path or "".
func _save_snapshot(entry_id: int, snapshot: Variant) -> String:
	if not (snapshot is Resource):
		return ""
	var rel := SNAPSHOT_DIR.path_join("preset_%d.tres" % entry_id)
	var abs := ProjectSettings.globalize_path(rel)
	var err := ResourceSaver.save(snapshot, abs)
	return rel if err == OK else ""


func _ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT_PATH))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FRAME_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SNAPSHOT_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCRIPT_DIR))


func _append_record(record: Dictionary) -> void:
	# JSONL append with atomic rewrite (keep under MAX_LOG_ENTRIES).
	var records := _read_records()
	records.append(record)
	if records.size() > MAX_LOG_ENTRIES:
		records = records.slice(records.size() - MAX_LOG_ENTRIES)
	var lines: Array[String] = []
	for r in records:
		lines.append(JSON.stringify(r))
	# Atomic rewrite (tmp + rename, project convention): a crash mid-write must
	# not corrupt the whole archive.
	var tmp_path := ProjectSettings.globalize_path(LOG_FILE_TMP)
	var path := ProjectSettings.globalize_path(LOG_FILE)
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("\n".join(lines) + "\n")
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var rename_error := DirAccess.rename_absolute(tmp_path, path)
	if rename_error != OK:
		DirAccess.remove_absolute(tmp_path)


func _read_records() -> Array:
	var path := ProjectSettings.globalize_path(LOG_FILE)
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var records: Array = []
	var text := file.get_as_text()
	file.close()
	for line in text.split("\n"):
		var line_clean := line.strip_edges()
		if line_clean == "":
			continue
		var parsed: Variant = JSON.parse_string(line_clean)
		if parsed is Dictionary:
			records.append(parsed)
	return records


func _next_entry() -> int:
	_last_entry_id += 1
	var candidate := int(Time.get_unix_time_from_system() * 1000.0) + _last_entry_id
	for record in _read_records():
		candidate = maxi(candidate, int(record.get("id", 0)) + 1)
	return candidate


func _count_by_action(records: Array) -> Dictionary:
	var counts: Dictionary = {}
	for record in records:
		var action := String(record.get("action", "unknown"))
		counts[action] = counts.get(action, 0) + 1
	return counts


func _find_record(entry_id: String) -> Dictionary:
	for record in _read_records():
		if str(record.get("id", "")) == entry_id:
			return record
	return {}