class_name DOKI_GateFlow
extends RefCounted
## Zuständigkeit: pre-commit Gate (nur Lesen/Prüfen) — erzwingt den DOKI-Flow.
## Ausnahmen: rebase (skip), amend eines bestehenden DOKI-Commits (skip).

## Auto-Managed narrative Dateien — beim Snapshot-Vergleich irrelevant
## (werden von finish/finalize selbst gestaged, nicht vom User).
const AUTO_MANAGED: Array = ["narrative_chain.json", "change_index.json", "CHANGELOG.md", ".commit_msg.txt"]

var _repo_root: String
var _session_store: DOKI_SessionStore
var _git: DOKI_GitHelper


func _init(repo_root: String, session_store: DOKI_SessionStore, git: DOKI_GitHelper) -> void:
	_repo_root = repo_root
	_session_store = session_store
	_git = git


## gate() → {ok} | {ok:false, error} | {ok:true, skipped}
func run() -> Dictionary:
	# Rebase: Rebasierte Commits haben keine DOKI-Message — Gate überspringen.
	if _git.is_rebase_in_progress():
		return {"ok": true, "skipped": "rebase"}

	var session: Dictionary = _session_store.read()
	var state: String = str(session.get("state", "idle"))

	# Amend-Erkennung: Session idle + HEAD-Message ist bereits ein DOKI-Commit.
	if state == DOKI_SessionStore.STATE_IDLE:
		if _git.head_message().contains("[COMPOSITE:"):
			return {"ok": true, "skipped": "amend"}
		return {"ok": false, "error": "Kein DOKI-Flow aktiv. Ablauf: git add → doki prepare → doki finish → git commit -F .commit_msg.txt"}

	if state != DOKI_SessionStore.STATE_VERIFIED:
		return {"ok": false, "error": "Session ist '%s' — es wurde kein verlifizierter Commit vorbereitet (doki finish)." % state}

	# .commit_msg.txt muss existieren und nicht leer sein
	var msg_path: String = _repo_root.path_join(".commit_msg.txt")
	if not FileAccess.file_exists(msg_path):
		return {"ok": false, "error": ".commit_msg.txt fehlt — der Commit darf nur über `doki finish` entstehen."}
	if FileAccess.get_file_as_string(msg_path).strip_edges().is_empty():
		return {"ok": false, "error": ".commit_msg.txt ist leer."}

	# Snapshot-Gate: gestagte Dateien müssen exakt der Session entsprechen
	# (verhindert: alte Message auf neuem Diff). Auto-Managed narrative Dateien
	# werden auf beiden Seiten ignoriert — sie stammen aus finish/finalize,
	# nicht aus dem User-Diff.
	var staged: Array = _without_auto_managed(_git.staged_files())
	var snapshot: Array = _without_auto_managed(session.get("file_snapshot", []))
	staged.sort()
	snapshot.sort()
	if staged != snapshot:
		var extra: Array = staged.filter(func(f): return not snapshot.has(f))
		var missing: Array = snapshot.filter(func(f): return not staged.has(f))
		return {"ok": false, "error": "Staged-Dateien weichen von der Session ab (Stale Message?). Zusätzlich: %s — Fehlend: %s. Bitte `doki prepare` erneut." % [str(extra), str(missing)]}

	return {"ok": true}


static func _without_auto_managed(files: Array) -> Array:
	var result: Array = []
	for f in files:
		if not AUTO_MANAGED.has(str(f).get_file()):
			result.append(str(f))
	return result