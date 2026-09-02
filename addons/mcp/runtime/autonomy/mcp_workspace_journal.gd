extends RefCounted
class_name McpWorkspaceJournal

## Slice B - isolierter Run-Workspace mit Baseline-Fingerprint, Preimages,
## Hash/Diff-Nachweis und explizitem Datei-Rollback.

const PATH_VALIDATOR_SCRIPT := preload("res://addons/mcp/runtime/autonomy/mcp_path_validator.gd")
const WORKSPACE_ROOT := "user://mcp_workspaces"
const STATE_CLEAN := "CLEAN"
const STATE_DIRTY := "DIRTY"
const STATE_ROLLING_BACK := "ROLLING_BACK"
const STATE_ROLLBACK_FAILED := "ROLLBACK_FAILED"

var run_id := ""
var root_path := ""
var project_id := ""
var session_id := ""
var owner_pid := 0
var renderer := ""
var state := STATE_CLEAN

var _baseline: Dictionary = {}
var _run_sequence := 0
var _tx: Dictionary = {}
var _tx_order: Array = []
var _tx_seq := 1


func begin_run(p_project_id: String, p_session_id: String, p_renderer: String, p_owner_pid: int) -> Dictionary:
	_run_sequence += 1
	# Millisecond wall-clock plus an instance-local sequence keeps runs distinct
	# when an agent closes and reopens a workspace within the same second.
	run_id = "run_%d_%d" % [int(Time.get_unix_time_from_system() * 1000.0), _run_sequence]
	project_id = p_project_id
	session_id = p_session_id
	renderer = p_renderer
	owner_pid = p_owner_pid
	root_path = WORKSPACE_ROOT.path_join(run_id)
	state = STATE_CLEAN
	_baseline.clear()
	_tx.clear()
	_tx_order.clear()
	_tx_seq = 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root_path))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root_path.path_join("preimages")))
	# Capture and retain the actual run-start fingerprint. The previous call
	# scanned the directory but discarded the result, so every workspace claimed
	# an empty baseline even when it contained imported files.
	_baseline = _scan_baseline()
	_write_manifest()
	return status()


func status() -> Dictionary:
	return {
		"run_id": run_id,
		"root_path": root_path,
		"globalized_root": ProjectSettings.globalize_path(root_path) if root_path != "" else "",
		"project_id": project_id,
		"session_id": session_id,
		"owner_pid": owner_pid,
		"renderer": renderer,
		"state": state,
		"baseline_files": _baseline.size(),
		"transactions": _tx.size(),
		"rollback_available": _tx.size() > 0,
	}


func is_bound() -> bool:
	return run_id != "" and session_id != ""


func verify_session(p_session_id: String) -> Dictionary:
	if not is_bound():
		return {"ok": false, "error": "no run workspace bound"}
	if p_session_id != session_id:
		return {"ok": false, "error": "session mismatch", "expected": session_id, "actual": p_session_id}
	return {"ok": true}


## Journalisiert eine Datei vor ihrer Modifikation.
## Nur Pfade innerhalb des Workspace-Roots (default).
func journal_preimage(path: String, content: String, is_text: bool = true) -> Dictionary:
	return _journalize(path, content, is_text, true)


## Journalisiert eine res://-Projektdatei vor einem Export-Rollback.
## Bewusst ausserhalb des Workspace-Roots erlaubt, aber nur res://-Pfade
## (fail-closed: kein user://-, kein absoluter OS-Pfad, kein Traversal).
func journal_preimage_external(path: String, content: String, is_text: bool = true) -> Dictionary:
	return _journalize(path, content, is_text, false)


func _journalize(path: String, content: String, is_text: bool, within_root: bool) -> Dictionary:
	var valid: Dictionary = PATH_VALIDATOR_SCRIPT.is_allowed_path(path)
	if not bool(valid.get("ok", false)):
		return {"ok": false, "error": str(valid.get("reason", "invalid path"))}
	if within_root:
		var within: Dictionary = PATH_VALIDATOR_SCRIPT.is_within_root(path, root_path)
		if not bool(within.get("ok", false)):
			return {"ok": false, "error": str(within.get("reason", "path outside workspace"))}
	else:
		# Export-Rollback: nur res://-Projektdateien sind als externe Preimage
		# erlaubt — niemals user:// oder OS-Pfade.
		if not String(path).begins_with("res://"):
			return {"ok": false, "error": "external preimage requires a res:// project path"}
	var tx_id := "tx_%d_%d" % [Time.get_unix_time_from_system(), _tx_seq]
	_tx_seq += 1
	var before_hash: String = PATH_VALIDATOR_SCRIPT.sha256_of_file(path) if FileAccess.file_exists(path) else ""
	var does_exist := FileAccess.file_exists(path)
	var preimage_rel := "preimages".path_join(tx_id + (".txt" if is_text else ".bin"))
	var preimage_abs: String = ProjectSettings.globalize_path(root_path.path_join(preimage_rel))
	var file := FileAccess.open(preimage_abs, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "cannot create preimage: " + preimage_abs}
	file.store_string(content)
	file.close()
	_tx[tx_id] = {
		"path": path,
		"before_hash": before_hash,
		"after_hash": "",
		"preimage": preimage_rel,
		"existed": does_exist,
		"kind": "text" if is_text else "binary",
		"state": "pending",
		"external": not within_root,
	}
	_tx_order.append(tx_id)
	state = STATE_DIRTY
	return {"ok": true, "transaction_id": tx_id, "before_hash": before_hash}


func commit(tx_id: String, after_hash: String, p_session_id: String) -> Dictionary:
	var session_ok: Dictionary = verify_session(p_session_id)
	if not bool(session_ok.get("ok", false)):
		return session_ok
	if not _tx.has(tx_id):
		return {"ok": false, "error": "unknown transaction"}
	_tx[tx_id]["after_hash"] = after_hash
	_tx[tx_id]["state"] = "committed"
	return {"ok": true, "transaction_id": tx_id, "after_hash": after_hash}


func rollback(tx_id: String, p_session_id: String) -> Dictionary:
	var session_ok: Dictionary = verify_session(p_session_id)
	if not bool(session_ok.get("ok", false)):
		return session_ok
	if not _tx.has(tx_id):
		return {"ok": false, "error": "unknown transaction"}
	state = STATE_ROLLING_BACK
	var entry: Dictionary = _tx[tx_id]
	var preimage_abs: String = ProjectSettings.globalize_path(root_path.path_join(str(entry.get("preimage", ""))))
	if not FileAccess.file_exists(preimage_abs):
		state = STATE_ROLLBACK_FAILED
		return {"ok": false, "error": "preimage missing", "transaction_id": tx_id}
	var file := FileAccess.open(preimage_abs, FileAccess.READ)
	if file == null:
		state = STATE_ROLLBACK_FAILED
		return {"ok": false, "error": "cannot open preimage", "transaction_id": tx_id}
	var data: Variant
	if str(entry.get("kind", "text")) == "text":
		data = file.get_as_text()
	else:
		data = file.get_buffer(file.get_length())
	file.close()
	var target_abs: String = ProjectSettings.globalize_path(str(entry.get("path", "")))
	if bool(entry.get("existed", true)):
		var out := FileAccess.open(target_abs, FileAccess.WRITE)
		if out == null:
			state = STATE_ROLLBACK_FAILED
			return {"ok": false, "error": "cannot write restored file", "transaction_id": tx_id}
		if data is String:
			out.store_string(data)
		else:
			out.store_buffer(data)
		out.close()
	else:
		DirAccess.remove_absolute(target_abs)
	_tx[tx_id]["state"] = "rolled_back"
	_tx_order.erase(tx_id)
	if _tx_order.is_empty():
		state = STATE_CLEAN
	else:
		state = STATE_DIRTY
	return {"ok": true, "transaction_id": tx_id, "restored_hash": PATH_VALIDATOR_SCRIPT.sha256_of_file(str(entry.get("path", "")))}


func rollback_all(p_session_id: String) -> Dictionary:
	var session_ok: Dictionary = verify_session(p_session_id)
	if not bool(session_ok.get("ok", false)):
		return session_ok
	var failed: Array = []
	for tx_id in _tx_order.duplicate(true):
		var result: Dictionary = rollback(tx_id, p_session_id)
		if not bool(result.get("ok", false)):
			failed.append({"transaction_id": tx_id, "error": result.get("error", "")})
	if not failed.is_empty():
		state = STATE_ROLLBACK_FAILED
		return {"ok": false, "failures": failed}
	state = STATE_CLEAN
	return {"ok": true, "rolled_back": true}


func verify_baseline(p_session_id: String) -> Dictionary:
	var session_ok: Dictionary = verify_session(p_session_id)
	if not bool(session_ok.get("ok", false)):
		return session_ok
	var current := _scan_baseline()
	var dirty: Array = []
	var new_files: Array = []
	for path in current:
		if not _baseline.has(path):
			new_files.append(path)
		elif str(_baseline[path]) != str(current[path]):
			dirty.append({"path": path, "before": _baseline[path], "after": current[path]})
	for path in _baseline:
		if not current.has(path):
			dirty.append({"path": path, "before": _baseline[path], "after": ""})
	var clean_result := dirty.is_empty() and new_files.is_empty()
	return {"ok": clean_result, "clean": clean_result, "dirty": dirty, "new_files": new_files}


func finish(p_session_id: String) -> Dictionary:
	var session_ok: Dictionary = verify_session(p_session_id)
	if not bool(session_ok.get("ok", false)):
		return session_ok
	var pending: Array = []
	for tx_id in _tx:
		if str(_tx[tx_id].get("state", "")) == "pending":
			pending.append(tx_id)
	if not pending.is_empty():
		state = STATE_DIRTY
		return {"ok": false, "error": "uncommitted transactions", "pending": pending}
	return {"ok": true, "run_id": run_id}


func list_workspace_files() -> Array:
	var result: Array = []
	_collect_files(root_path, result)
	return result


func _collect_files(dir_path: String, result: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry in [".", ".."]:
			entry = dir.get_next()
			continue
		var full := dir_path + "/" + entry
		if dir.current_is_dir():
			if entry != "preimages":
				_collect_files(full, result)
		else:
			if entry not in ["manifest.jsonl", "manifest.json"]:
				var rel := full.trim_prefix(root_path + "/")
				result.append(rel)
		entry = dir.get_next()
	dir.list_dir_end()


func _scan_baseline() -> Dictionary:
	return scan_dir_files(root_path)


func scan_dir_files(dir_path: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return result
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry in [".", ".."]:
			entry = dir.get_next()
			continue
		var full := dir_path + "/" + entry
		if dir.current_is_dir():
			if entry != "preimages":
				var sub := scan_dir_files(full)
				for key in sub:
					result[key] = sub[key]
		elif entry not in ["manifest.jsonl", "manifest.json"]:
			var rel := full.trim_prefix(root_path + "/")
			result[rel] = PATH_VALIDATOR_SCRIPT.sha256_of_file(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return result


func _write_manifest() -> void:
	var manifest := {
		"run_id": run_id,
		"project_id": project_id,
		"session_id": session_id,
		"owner_pid": owner_pid,
		"renderer": renderer,
		"created_at": Time.get_unix_time_from_system(),
		"baseline": _baseline,
	}
	var file := FileAccess.open(ProjectSettings.globalize_path(root_path.path_join("manifest.json")), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(manifest, "\t"))
		file.close()