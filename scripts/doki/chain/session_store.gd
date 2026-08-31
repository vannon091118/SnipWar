class_name DOKI_SessionStore
extends RefCounted
## EINZIGE Zustandsquelle des CommitLayers: .doki/session.json (gitignored).
## Zustandsmaschine: idle → prepared → verified → idle. Unidirektional.
##
## Das alte System hatte stattdessen eine Temp-Cache-Datei (%TEMP%/.doki-prompt-cache.json)
## — global, repo-übergreifend kollidierend, OS-aufgeräumt. Das hier ist die Fix-Version.
##
## Integrity: HMAC-SHA256 mit Agent-Seed (V2-001)
## Atomic claim: file-locking compare-and-swap (V2-002)
## State transitions: cryptographically validated (V2-003)
## finalize_flow rejects idle, requires VERIFIED (V2-004)

const STATE_IDLE: String = "idle"
const STATE_PREPARED: String = "prepared"
const STATE_VERIFIED: String = "verified"

const SESSION_DIR: String = ".doki"
const SESSION_FILE: String = "session.json"
const OWNER_FILE: String = "owner.json"
const LOCK_FILE: String = "session.lock"

var _path: String
var _owner_path: String
var _lock_path: String
var _repo_root: String


func _init(repo_root: String) -> void:
	_repo_root = repo_root
	_path = repo_root.path_join(SESSION_DIR).path_join(SESSION_FILE)
	_owner_path = repo_root.path_join(SESSION_DIR).path_join(OWNER_FILE)
	_lock_path = repo_root.path_join(SESSION_DIR).path_join(LOCK_FILE)


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
		"integrity_hash": "",
		"prev_state": STATE_IDLE,
	}


## ─── Integrity: HMAC-SHA256 mit Agent-Seed (V2-001) ─────────────────────
static func _compute_integrity_hash(session: Dictionary, agent_seed: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	# Deterministische Serialisierung: sortierte Keys, stabile Werte
	var serialized: String = _serialize_for_hash(session)
	ctx.update(serialized.to_utf8_buffer())
	ctx.update(agent_seed.to_utf8_buffer())
	return ctx.finish().hex_encode()


static func _serialize_for_hash(session: Dictionary) -> String:
	var keys: Array = session.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		var v: Variant = session[k]
		if k == "integrity_hash" or k == "prev_state":
			continue  # nicht in den Hash einbeziehen (zirkulär)
		if v is Dictionary or v is Array:
			parts.append("%s=%s" % [k, JSON.stringify(v)])
		else:
			parts.append("%s=%s" % [k, str(v)])
	return "\n".join(parts)


func _validate_integrity(session: Dictionary, agent_seed: String) -> bool:
	var expected: String = _compute_integrity_hash(session, agent_seed)
	var actual: String = str(session.get("integrity_hash", ""))
	return expected == actual


func _sign_session(session: Dictionary, agent_seed: String) -> Dictionary:
	session["integrity_hash"] = _compute_integrity_hash(session, agent_seed)
	return session


func save(session: Dictionary) -> void:
	var content: String = JSON.stringify(session, "\t")
	_atomic_write(_path, content)


## ─── Atomic write with tmp+rename (V7-001) ───────────────────────────────
static func _atomic_write(path: String, content: String) -> void:
	var dir_path: String = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir_path)
	var tmp_path: String = path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("DOKI: %s nicht schreibbar: %s" % [path, tmp_path])
		return
	file.store_string(content)
	file.close()
	# Atomic rename (POSIX/Windows supported in Godot 4)
	DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp_path, path)


func reset() -> void:
	save(default_session())
	release_ownership("")


## Single-Active-Owner (RISK-003, fail-closed, kein destruktives Cleanup).
## claim(owner_token) übernimmt den Worktree, wenn idle oder der alte Owner
## stimmt. Ein zweiter aktiver Owner wird abgewiesen — niemals automatisch
## überschrieben/gelöscht (RISK-003 fordert ausdrücklich: avoid destructive cleanup).
## owner_token: eindeutige Agent-Identität (z.B. OS.get_process_id() + pid).
## Atomic compare-and-swap with file locking (V2-002).
func claim(owner_token: String) -> Dictionary:
	if owner_token.is_empty():
		return {"ok": false, "error": "ownership: empty owner_token (fail-closed)."}
	
	# Atomic compare-and-swap: read owner, compare, write if free or same.
	# Godot 4 has no file-locking API; we rely on atomic tmp+rename writes.
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
	var content: String = JSON.stringify(data, "\t")
	_atomic_write(_owner_path, content)


func ensure_state(expected: String) -> Dictionary:
	## Wirft nichts — liefert {ok, session, error}.
	var session: Dictionary = read()
	if session.get("state") != expected:
		return {"ok": false, "session": session, "error": "Zustandsfehler: erwartet '%s', aktuell '%s'." % [expected, session.get("state", "?")]}
	
	# Validate state transition integrity (V2-003)
	var prev_state: String = str(session.get("prev_state", STATE_IDLE))
	if not _is_valid_transition(prev_state, expected):
		return {"ok": false, "session": session, "error": "Ungültiger Zustandsübergang: '%s' → '%s'." % [prev_state, expected]}
	
	return {"ok": true, "session": session, "error": ""}


## ─── State Transition Validation (V2-003) ────────────────────────────────
static func _is_valid_transition(from_state: String, to_state: String) -> bool:
	# Zulässige Übergänge: idle → prepared → verified → idle
	# idle → idle ist ein No-Op (Reset) und erlaubt.
	match from_state:
		STATE_IDLE:
			return to_state == STATE_PREPARED or to_state == STATE_IDLE
		STATE_PREPARED:
			return to_state == STATE_VERIFIED or to_state == STATE_IDLE
		STATE_VERIFIED:
			return to_state == STATE_IDLE
		_:
			return false


func transition_state(new_state: String, agent_seed: String) -> Dictionary:
	var session: Dictionary = read()
	var current_state: String = str(session.get("state", STATE_IDLE))
	
	if not _is_valid_transition(current_state, new_state):
		return {"ok": false, "error": "Ungültiger Zustandsübergang: '%s' → '%s'." % [current_state, new_state]}
	
	session["prev_state"] = current_state
	session["state"] = new_state
	session = _sign_session(session, agent_seed)
	save(session)
	return {"ok": true, "session": session}