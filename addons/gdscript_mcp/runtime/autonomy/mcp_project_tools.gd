extends RefCounted
class_name McpProjectTools

## Slice C - eigene Read/Create/Patch/Search/Symbol-Schicht.
## Read erlaubt res:// und user:// read-only; Write ausschliesslich
## innerhalb des Workspace-Roots.

const PATH_VALIDATOR_SCRIPT := preload("res://addons/gdscript_mcp/runtime/autonomy/mcp_path_validator.gd")
const JOURNAL_PATH := "res://addons/gdscript_mcp/runtime/autonomy/mcp_workspace_journal.gd"
const IMPORT_SUBDIR := "imports"

var _journal: RefCounted = null
var _workspace_root := ""
var _session_id := ""
var _imports: Dictionary = {}


func setup(workspace_root: String, session_id: String, journal: RefCounted = null) -> void:
	_workspace_root = PATH_VALIDATOR_SCRIPT.normalize(workspace_root) if workspace_root != "" else ""
	_session_id = session_id
	_journal = journal
	if _journal == null:
		var jscript: Resource = load(JOURNAL_PATH)
		if jscript != null:
			_journal = jscript.new()


func is_workspace_bound() -> bool:
	return _workspace_root != ""


func workspace_root() -> String:
	return _workspace_root


## READ - read-only, res:// und user://.
func read(path_string: String) -> Dictionary:
	var normalized: String = PATH_VALIDATOR_SCRIPT.normalize(path_string)
	var valid: Dictionary = PATH_VALIDATOR_SCRIPT.is_allowed_path(normalized)
	if not bool(valid.get("ok", false)):
		return {"ok": false, "error": str(valid.get("reason", "invalid path"))}
	if not FileAccess.file_exists(normalized):
		return {"ok": false, "error": "file not found: " + normalized}
	var file := FileAccess.open(normalized, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot open: " + normalized}
	var text := file.get_as_text()
	file.close()
	return {
		"ok": true,
		"path": normalized,
		"text": text,
		"sha256": PATH_VALIDATOR_SCRIPT.sha256_of_file(normalized),
		"bytes": text.to_utf8_buffer().size(),
	}


## WRITE - nur innerhalb des Workspace-Root; Journal-Preimage erforderlich.
func write(path_string: String, content: String, expected_hash: String = "", session_id: String = "") -> Dictionary:
	var session := session_id if session_id != "" else _session_id
	if not is_workspace_bound():
		return {"ok": false, "error": "no workspace bound; writes blocked"}
	var normalized: String = PATH_VALIDATOR_SCRIPT.normalize(path_string)
	var within: Dictionary = PATH_VALIDATOR_SCRIPT.is_within_root(normalized, _workspace_root)
	if not bool(within.get("ok", false)):
		return {"ok": false, "error": str(within.get("reason", "write outside workspace"))}
	if normalized.begins_with("res://"):
		return {"ok": false, "error": "res:// writes are blocked; use workspace path"}
	if _journal == null:
		return {"ok": false, "error": "journal unavailable; write blocked"}
	var before_text := ""
	var before_hash := ""
	if FileAccess.file_exists(normalized):
		var rf := FileAccess.open(normalized, FileAccess.READ)
		if rf != null:
			before_text = rf.get_as_text()
			rf.close()
			before_hash = PATH_VALIDATOR_SCRIPT.sha256_of_file(normalized)
	if expected_hash != "" and expected_hash != before_hash:
		return {"ok": false, "error": "hash mismatch (refused)", "before": before_hash, "expected": expected_hash}
	var tx: Dictionary = _journal.call("journal_preimage", normalized, before_text, true)
	if not bool(tx.get("ok", false)):
		return {"ok": false, "error": "preimage failed: " + str(tx.get("error", ""))}
	var tx_id := str(tx.get("transaction_id", ""))
	var dir_part := normalized.get_base_dir()
	if dir_part != "" and not DirAccess.dir_exists_absolute(dir_part):
		DirAccess.make_dir_recursive_absolute(dir_part)
	var tmp_path := normalized + ".tmp"
	var wf := FileAccess.open(tmp_path, FileAccess.WRITE)
	if wf == null:
		return {"ok": false, "error": "cannot create tmp file"}
	wf.store_string(content)
	wf.close()
	if FileAccess.file_exists(normalized):
		DirAccess.remove_absolute(normalized)
	if DirAccess.rename_absolute(tmp_path, normalized) != OK:
		return {"ok": false, "error": "cannot rename tmp file"}
	var after_hash := PATH_VALIDATOR_SCRIPT.sha256_of_file(normalized)
	_journal.call("commit", tx_id, after_hash, session)
	return {
		"ok": true,
		"path": normalized,
		"transaction_id": tx_id,
		"before_hash": before_hash,
		"after_hash": after_hash,
		"changed": true,
		"rollback_available": true,
		"diagnostics": {"status": "complete", "entries": []},
	}


## IMPORT - kopiert eine res://-Projektdatei in den Workspace (journaled),
## registriert Origin-Pfad + Origin-Hash für den gated Export.
func import_file(path_string: String) -> Dictionary:
	if not is_workspace_bound():
		return {"ok": false, "error": "no workspace bound"}
	var normalized: String = PATH_VALIDATOR_SCRIPT.normalize(path_string)
	if not normalized.begins_with("res://"):
		return {"ok": false, "error": "import source must be a res:// project path"}
	if not FileAccess.file_exists(normalized):
		return {"ok": false, "error": "import source not found: " + normalized}
	var rel := normalized.trim_prefix("res://")
	var target := _workspace_root.path_join(IMPORT_SUBDIR).path_join(rel)
	var source_text := ""
	var source := FileAccess.open(normalized, FileAccess.READ)
	if source != null:
		source_text = source.get_as_text()
		source.close()
	var origin_hash := PATH_VALIDATOR_SCRIPT.sha256_of_file(normalized)
	var written := write(target, source_text, "")
	if not bool(written.get("ok", false)):
		return written
	_imports[normalized] = {"workspace_path": target, "origin_hash": origin_hash}
	return {
		"ok": true,
		"origin": normalized,
		"workspace_path": target,
		"origin_hash": origin_hash,
		"transaction_id": written.get("transaction_id", ""),
	}


func list_imports() -> Dictionary:
	var entries: Array = []
	for origin in _imports:
		entries.append({
			"origin": origin,
			"workspace_path": _imports[origin]["workspace_path"],
			"origin_hash": _imports[origin]["origin_hash"],
		})
	return {"ok": true, "imports": entries, "count": entries.size()}


## EXPORT - gated Zurückschreiben einer importierten Datei nach res://.
## Fail-closed: dry-run ohne apply=true, Origin-Changed-Check (force zum
## Übersteuern), Validierung (GDScript/JSON) blockiert invaliden Inhalt,
## externes Journal-Preimage ermöglicht Rollback des Projektpfads.
func export_file(path_string: String, apply: bool = false, force: bool = false) -> Dictionary:
	if not is_workspace_bound():
		return {"ok": false, "error": "no workspace bound"}
	var normalized: String = PATH_VALIDATOR_SCRIPT.normalize(path_string)
	if not _imports.has(normalized):
		return {"ok": false, "error": "no import entry for " + normalized + "; import the file first"}
	var entry: Dictionary = _imports[normalized]
	var workspace_path := str(entry.get("workspace_path", ""))
	var workspace_read := read(workspace_path)
	if not bool(workspace_read.get("ok", false)):
		return workspace_read
	var content := str(workspace_read.get("text", ""))
	var workspace_hash := str(workspace_read.get("sha256", ""))
	var current_origin_hash := PATH_VALIDATOR_SCRIPT.sha256_of_file(normalized)
	var origin_unchanged := str(entry.get("origin_hash", "")) == current_origin_hash
	if not origin_unchanged and not force:
		return {
			"ok": false,
			"error": "origin file changed since import; refusing overwrite (force=true to override)",
			"current_origin_hash": current_origin_hash,
			"import_origin_hash": entry.get("origin_hash", ""),
		}
	var validation := validate_text(normalized, content)
	if not bool(validation.get("ok", false)):
		return {"ok": false, "error": "validation failed: " + str(validation.get("error", "")), "validation": validation}
	if not apply:
		return {
			"ok": true,
			"applied": false,
			"dry_run": true,
			"validation": validation,
			"workspace_hash": workspace_hash,
			"current_origin_hash": current_origin_hash,
		}
	var original_text := ""
	var original := FileAccess.open(normalized, FileAccess.READ)
	if original != null:
		original_text = original.get_as_text()
		original.close()
	var tx: Dictionary = _journal.call("journal_preimage_external", normalized, original_text, true)
	if not bool(tx.get("ok", false)):
		return {"ok": false, "error": "external preimage failed: " + str(tx.get("error", ""))}
	var tx_id := str(tx.get("transaction_id", ""))
	var tmp_path := normalized + ".tmp"
	var wf := FileAccess.open(tmp_path, FileAccess.WRITE)
	if wf == null:
		return {"ok": false, "error": "cannot create tmp file"}
	wf.store_string(content)
	wf.close()
	if FileAccess.file_exists(normalized):
		DirAccess.remove_absolute(normalized)
	if DirAccess.rename_absolute(tmp_path, normalized) != OK:
		return {"ok": false, "error": "cannot rename tmp file"}
	var after_hash := PATH_VALIDATOR_SCRIPT.sha256_of_file(normalized)
	_journal.call("commit", tx_id, after_hash, _session_id)
	_imports[normalized]["last_export_hash"] = after_hash
	var barrier: Dictionary = await resource_barrier(normalized)
	return {
		"ok": true,
		"applied": true,
		"transaction_id": tx_id,
		"origin": normalized,
		"before_hash": str(entry.get("origin_hash", "")),
		"after_hash": after_hash,
		"validation": validation,
		"resource_barrier": barrier,
		"rollback_available": true,
	}


## Validierung vor dem Export: GDScript- und JSON-Parser, sonst kein Parser
## (Datei wird nur auf Hash-Ebene geprüft). Fail-closed bei Parse-Fehlern.
static func validate_text(path: String, content: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	var diagnostics: Array = []
	if ext == "gd":
		var script := GDScript.new()
		script.source_code = content
		var err := script.reload()
		if err != OK:
			var err_msg := error_string(err)
			diagnostics.append({
				"file": path,
				"line": 1,
				"column": 0,
				"severity": "error",
				"message": err_msg,
			})
			return {
				"ok": false,
				"error": err_msg,
				"check": "gd_parse",
				"status": "error",
				"diagnostics": diagnostics,
			}
		return {
			"ok": true,
			"check": "gd_parse",
			"status": "complete",
			"diagnostics": [],
		}
	if ext == "json":
		var json := JSON.new()
		var err := json.parse(content)
		if err != OK:
			diagnostics.append({
				"file": path,
				"line": json.get_error_line(),
				"column": 0,
				"severity": "error",
				"message": json.get_error_message(),
			})
			return {
				"ok": false,
				"error": json.get_error_message(),
				"check": "json_parse",
				"status": "error",
				"diagnostics": diagnostics,
			}
		return {
			"ok": true,
			"check": "json_parse",
			"status": "complete",
			"diagnostics": [],
		}
	return {"ok": true, "check": "none", "status": "skipped", "diagnostics": [], "skipped": true}


## Wartet frameweise darauf, dass eine exportierte Ressource / Script
## im ResourceLoader und Dateisystem ohne Race-Condition bereitsteht.
static func resource_barrier(path: String, timeout_ms: int = 1500) -> Dictionary:
	var normalized: String = PATH_VALIDATOR_SCRIPT.normalize(path)
	var start_ms := Time.get_ticks_msec()
	var tree := Engine.get_main_loop()

	while Time.get_ticks_msec() - start_ms < timeout_ms:
		if FileAccess.file_exists(normalized):
			if normalized.begins_with("res://"):
				if ResourceLoader.exists(normalized):
					return {
						"ok": true,
						"path": normalized,
						"settled": true,
						"duration_ms": Time.get_ticks_msec() - start_ms,
					}
			else:
				return {
					"ok": true,
					"path": normalized,
					"settled": true,
					"duration_ms": Time.get_ticks_msec() - start_ms,
				}
		if tree is SceneTree:
			await (tree as SceneTree).process_frame
		else:
			OS.delay_msec(16)

	return {
		"ok": false,
		"path": normalized,
		"settled": false,
		"error": "resource_barrier timeout after %d ms" % timeout_ms,
	}


## PATCH - fail-closed: kein old_text bei 0 oder mehreren Treffern.
func patch_content(path_string: String, old_text: String, new_text: String, expected_hash: String = "", session_id: String = "") -> Dictionary:
	var current := read(path_string)
	if not bool(current.get("ok", false)):
		return current
	var before_hash := str(current.get("sha256", ""))
	if expected_hash != "" and expected_hash != before_hash:
		return {"ok": false, "error": "stale source; hash mismatch", "before": before_hash, "expected": expected_hash}
	var content: String = str(current.get("text", ""))
	if old_text != "":
		var occurrences := content.count(old_text)
		if occurrences == 0:
			return {"ok": false, "error": "old_text not found"}
		if occurrences > 1:
			return {"ok": false, "error": "old_text ambiguous", "count": occurrences}
		content = content.replace(old_text, new_text)
	else:
		content = new_text
	return write(path_string, content, before_hash, session_id)


## SEARCH - Textsuche in allen Workspace-Dateien (read-only).
func search(needle: String, limit: int = 50) -> Dictionary:
	if not is_workspace_bound():
		return {"ok": false, "error": "no workspace bound"}
	var hits: Array = []
	for rel in _list_all_files():
		var full: String = _workspace_root + "/" + rel
		var fr := FileAccess.open(full, FileAccess.READ)
		if fr == null:
			continue
		var text := fr.get_as_text()
		fr.close()
		if text.find(needle) >= 0:
			var lines: Array = []
			var index := 0
			for line in text.split("\n"):
				if needle in line:
					lines.append({"line": index + 1, "text": line.strip_edges()})
					if lines.size() >= 5:
						break
				index += 1
			hits.append({"path": full, "matches": lines})
	if hits.size() > maxi(0, limit):
		hits = hits.slice(0, maxi(0, limit))
	return {"ok": true, "count": hits.size(), "hits": hits}


## SYMBOLS - einfache Erkennung fuer GDScript.
func find_symbols(path_string: String) -> Dictionary:
	var result: Dictionary = {"classes": [], "funcs": [], "vars": []}
	var current_class := ""
	var read_result := read(path_string)
	if not bool(read_result.get("ok", false)):
		return result
	for line in str(read_result.get("text", "")).split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("class_name "):
			var parts := stripped.split(" ")
			if parts.size() >= 2:
				current_class = parts[1]
				result["classes"].append(current_class)
		elif stripped.begins_with("func "):
			var name_part := stripped.trim_prefix("func ").split("(")[0].strip_edges()
			result["funcs"].append({"name": name_part, "class": current_class})
		elif stripped.begins_with("var ") or stripped.begins_with("const "):
			var key := "var " if stripped.begins_with("var ") else "const "
			var name_part := stripped.trim_prefix(key).split("=")[0].split(" ")[0].strip_edges()
			result["vars"].append(name_part)
	return result


func rollback_transaction(tx_id: String, session_id: String = "") -> Dictionary:
	if _journal == null:
		return {"ok": false, "error": "no journal"}
	return _journal.call("rollback", tx_id, session_id if session_id != "" else _session_id)


func workspace_file_count() -> int:
	return _list_all_files().size()


func _list_all_files() -> Array:
	return _list_files_recursive(_workspace_root)


func _list_files_recursive(dir_path: String) -> Array:
	var result: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry in [".", ".."]:
			entry = dir.get_next()
			continue
		var full: String = dir_path + "/" + entry
		if dir.current_is_dir():
			if not entry in ["preimages"]:
				result.append_array(_list_files_recursive(full))
		else:
			if not entry.ends_with(".tmp"):
				result.append(full.trim_prefix(_workspace_root + "/"))
		entry = dir.get_next()
	dir.list_dir_end()
	return result