class_name DOKI_SessionStore
extends RefCounted
## EINZIGE Zustandsquelle des CommitLayers: .doki/session.json (gitignored).
## Zustandsmaschine: idle → prepared → verified → idle. Unidirektional.
##
## Das alte System hatte stattdessen eine Temp-Cache-Datei (%TEMP%/.doki-prompt-cache.json)
## — global, repo-übergreifend kollidierend, OS-aufgeräumt. Das hier ist die Fix-Version.

const STATE_IDLE: String = "idle"
const STATE_PREPARED: String = "prepared"
const STATE_VERIFIED: String = "verified"

const SESSION_DIR: String = ".doki"
const SESSION_FILE: String = "session.json"
const OWNER_FILE: String = "owner.json"

var _path: String
var _owner_path: String
var _repo_root: String


func _init(repo_root: String) -> void:
	_repo_root = repo_root
	_path = repo_root.path_join(SESSION_DIR).path_join(SESSION_FILE)
	_owner_path = repo_root.path_join(SESSION_DIR).path_join(OWNER_FILE)


func path() -> String:
	return _path


func read() -> Dictionary:
	if not FileAccess.file_exists(_path):
		return default_session()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	# Halbgeschriebene / crash-geschädigte Session (ohne state-Feld) → Default.
	# Sonst liefe die Zustandsmaschine mit „Zustand ?“ weiter.
	if parsed is Dictionary and (parsed as Dictionary).has("state"):
		return parsed
	return default_session()


func default_session() -> Dictionary:
	return {
		"state": STATE_IDLE,
		"composite": "",
		"seed": 0,
		"tree_hash": "",
		"diff_hash": "",
		"impulse": "",
		"narrator": "",
		"narrator_index": 0,
		"mood": "",
		"tone": "",
		"structure": "",
		"callback": false,
		"model_id": "",
		"prev_narrator": "",
		"file_snapshot": [],
		"impact": {},
		"git_head_before": "",
		"scope_path_digest": "",
		"scope_constraint_digest": "",
		"staged_byte_digest": "",
		"baseline_identity": "",
		"p_id": 0,
		"c": 0,
		"j": 0,
		"n": 0,
		"a": 0,
		"p": 0,
		"arc_id": "",
		"arc_name": "",
		"is_arc_climax": false,
		"sideplot": {},
		"impulse_class": "CODE",
		"relationship": {},
		"body_text": "",
		"reason_lines": [],
	}


func save(session: Dictionary) -> void:
	var dir_path: String = _path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_error("DOKI: session.json nicht schreibbar: %s" % _path)
		return
	file.store_string(JSON.stringify(session, "\t"))
	file.close()


func reset() -> void:
	save(default_session())
	release_ownership("")


## Single-Active-Owner (RISK-003, fail-closed, kein destruktives Cleanup).
## claim(owner_token) übernimmt den Worktree, wenn idle oder der alte Owner
## stimmt. Ein zweiter aktiver Owner wird abgewiesen — niemals automatisch
## überschrieben/gelöscht (RISK-003 fordert ausdrücklich: avoid destructive cleanup).
## owner_token: eindeutige Agent-Identität (z.B. OS.get_process_id() + pid).
func claim(owner_token: String) -> Dictionary:
	if owner_token.is_empty():
		return {"ok": false, "error": "ownership: empty owner_token (fail-closed)."}
	var current: Dictionary = _read_owner()
	var active: String = str(current.get("owner_token", ""))
	if active.is_empty() or active == owner_token:
		_write_owner({"owner_token": owner_token, "claimed_at": Time.get_ticks_msec()})
		return {"ok": true, "owner_token": owner_token}
	# Ein anderer Agent hält aktiv den Worktree → fail-closed.
	return {"ok": false, "error": "ownership: worktree von anderem Agenten aktiv gehalten (token=%s). Andere Session erst finalisieren oder abbrechen — kein automatisches Cleanup." % active}


func release_ownership(owner_token: String) -> void:
	if not owner_token.is_empty():
		var current: Dictionary = _read_owner()
		if str(current.get("owner_token", "")) != owner_token:
			return  # nicht unser Lock → nicht freigeben
	DirAccess.remove_absolute(_owner_path)


func assert_owner(owner_token: String) -> Dictionary:
	var current: Dictionary = _read_owner()
	if str(current.get("owner_token", "")) != owner_token:
		return {"ok": false, "error": "ownership: Session gehört anderem Owner (token mismatch) — Zugriff verweigert."}
	return {"ok": true}


func _read_owner() -> Dictionary:
	if not FileAccess.file_exists(_owner_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_owner_path))
	return parsed if parsed is Dictionary else {}


func _write_owner(data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(_owner_path.get_base_dir())
	var file := FileAccess.open(_owner_path, FileAccess.WRITE)
	if file == null:
		push_error("DOKI: owner.json nicht schreibbar: %s" % _owner_path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func ensure_state(expected: String) -> Dictionary:
	## Wirft nichts — liefert {ok, session, error}.
	var session: Dictionary = read()
	if session.get("state") != expected:
		return {"ok": false, "session": session, "error": "Zustandsfehler: erwartet '%s', aktuell '%s'." % [expected, session.get("state", "?")]}
	return {"ok": true, "session": session, "error": ""}