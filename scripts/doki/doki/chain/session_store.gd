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

var _path: String


func _init(repo_root: String) -> void:
	_path = repo_root.path_join(SESSION_DIR).path_join(SESSION_FILE)


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
		"git_head_before": "",
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


func ensure_state(expected: String) -> Dictionary:
	## Wirft nichts — liefert {ok, session, error}.
	var session: Dictionary = read()
	if session.get("state") != expected:
		return {"ok": false, "session": session, "error": "Zustandsfehler: erwartet '%s', aktuell '%s'." % [expected, session.get("state", "?")]}
	return {"ok": true, "session": session, "error": ""}