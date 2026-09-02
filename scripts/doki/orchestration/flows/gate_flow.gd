class_name DOKI_GateFlow
extends RefCounted
## Zuständigkeit: pre-commit Gate (nur Lesen/Prüfen) — erzwingt den DOKI-Flow.
## Ausnahmen: rebase (skip), amend eines bestehenden DOKI-Commits (skip).

## Auto-Managed narrative Dateien — beim Snapshot-Vergleich irrelevant
## (werden von finish/finalize selbst gestaged, nicht vom User).
const AUTO_MANAGED: Array = ["narrative_chain.json", "change_index.json", "CHANGELOG.md", ".commit_msg.txt", "arcs.json"]

var _repo_root: String
var _session_store: DOKI_SessionStore
var _git: DOKI_GitHelper
const IMPACT_RESOLVER: Script = preload("res://scripts/preflight_v2/change_impact_resolver.gd")


func _init(repo_root: String, session_store: DOKI_SessionStore, git: DOKI_GitHelper) -> void:
	_repo_root = repo_root
	_session_store = session_store
	_git = git


## gate() → {ok} | {ok:false, error} | {ok:true, skipped}
func run() -> Dictionary:
	# Rebase: Rebasierte Commits haben keine DOKI-Message — Gate überspringen.
	if _git.is_rebase_in_progress():
		return {"ok": true, "skipped": "rebase"}

	# Merge-Konvergenz (content-neutral): Ist der Branch ein Superset des Base,
	# erzeugt der Merge KEINE neue Arbeit — der Staged-Diff (ohne auto-managed)
	# ist leer. Analog zum Rebase-Skip: die eigentliche Arbeit wurde bereits auf
	# dem Branch committet, der Merge zeichnet nur die Konvergenz mit dem Base
	# auf (nötig, um z.B. einen CONFLICTING-PR-Status zu klären). Ein Merge MIT
	# echten Konflikt-Änderungen (Staged nicht leer) läuft weiterhin normal durch
	# die Zeremonie.
	if _git.is_merge_in_progress():
		var merge_staged: Array = _without_auto_managed(_git.staged_files())
		if merge_staged.is_empty():
			return {"ok": true, "skipped": "merge-noop"}

	var session: Dictionary = _session_store.read()
	var state: String = str(session.get("state", "idle"))

	# Amend-Erkennung: Session idle + HEAD-Message ist bereits ein DOKI-Commit.
	if state == DOKI_SessionStore.STATE_IDLE:
		if _git.head_message().contains("[COMPOSITE:"):
			return {"ok": true, "skipped": "amend"}
		return {"ok": false, "error": "Kein DOKI-Flow aktiv. Ablauf: git add → doki prepare → doki finish → git commit -F .commit_msg.txt"}

	if state != DOKI_SessionStore.STATE_VERIFIED:
		return {"ok": false, "error": "Session ist '%s' — es wurde kein verlifizierter Commit vorbereitet (doki finish)." % state}
	
	# V10-003: Always require AGENT_ACTIVITY_SEED, fail if missing
	var activity_seed: String = str(session.get("activity_seed", ""))
	if activity_seed.is_empty():
		return {"ok": false, "error": "AGENT_ACTIVITY_SEED fehlt in Session — prepare ohne Agent-Activity-Check-In gelaufen? Bitte `doki prepare` erneut."}
	
	# Verify AGENT_ACTIVITY_SEED against registry
	var agent_name: String = str(session.get("agent_name", ""))
	if agent_name.is_empty():
		return {"ok": false, "error": "AGENT_NAME fehlt in Session — prepare ohne Agent-Activity-Check-In gelaufen? Bitte `doki prepare` erneut."}
	var seed_check: Dictionary = _verify_agent_activity_seed(agent_name, activity_seed)
	if not bool(seed_check.get("ok", false)):
		return seed_check

	# .commit_msg.txt muss existieren und nicht leer sein
	var msg_path: String = _repo_root.path_join(".commit_msg.txt")
	if not FileAccess.file_exists(msg_path):
		return {"ok": false, "error": ".commit_msg.txt fehlt — der Commit darf nur über `doki finish` entstehen."}
	if FileAccess.get_file_as_string(msg_path).strip_edges().is_empty():
		return {"ok": false, "error": ".commit_msg.txt ist leer."}

	# Ownership-Gate (TASK-013, RISK-003): die Session muss dem ausführenden
	# Prozess gehören. Ein zweiter Agent, der denselben Worktree parallel hält,
	# wird fail-closed abgewiesen — der Commit einer fremden Session ist verboten.
	var owner_token: String = str(session.get("owner_token", ""))
	if owner_token.is_empty():
		return {"ok": false, "error": "Ownership-Token fehlt in Session — prepare ohne Ownership-Bindung gelaufen? Bitte `doki prepare` erneut."}
	var owner_check: Dictionary = _session_store.assert_owner(owner_token)
	if not bool(owner_check.get("ok", false)):
		return owner_check

	# Snapshot-Gate: gestagte Dateien müssen exakt der Session entsprechen
	# (verhindert: alte Message auf neuem Diff). Auto-Managed narrative Dateien
	# werden auf beiden Seiten ignoriert.
	var full_staged: Array = _git.staged_files()
	var staged: Array = _without_auto_managed(full_staged)
	var snapshot: Array = _without_auto_managed(session.get("file_snapshot", []))

	# Scope-Gate: der MACHINE-resolvable Verification-Scope (über den
	# auto-managed-gefilterten Staged-Diff — exakt wie im prepare, wo die
	# finalize-Artefakte noch NICHT gestaged sind) muss dem prepared Scope
	# entsprechen. Unknown/leerer Impact blockt fail-closed.
	# (F-606-Fortsetzung: ohne den Filter driftet der Scope, sobald finish die
	# Artefakte staged — doki-Contract constraints kommen hinzu ≠ prepare-Scope.)
	var scope: Dictionary = _resolve_scope(staged)
	if not bool(scope.get("ok", false)):
		return {"ok": false, "error": "Scope-Auflösung fehlgeschlagen: %s — Impact-Unknown/leer darf nie grün werden." % str(scope.get("error", "unresolved_impact"))}
	var prepared_scope: Array = session.get("impact", {}).get("constraints", []) if session.get("impact", {}) is Dictionary else []
	var resolved_constraints: Array = Array(scope["constraints"]).duplicate()

	prepared_scope.sort()
	resolved_constraints.sort()
	if prepared_scope != resolved_constraints:
		return {"ok": false, "error": "Verification-Scope weicht vom Prepare-Scope ab (Under-/Over-Scope). Bitte `doki prepare` erneut."}

	# Byte-/Path-Drift-Gate (TASK-011): die gestagten Bytes und der Pfadbestand
	# müssen exakt den prepare-Zeit-Digests entsprechen. Jeglicher Drift nach
	# prepare (Datei verändert, Datei hinzugefügt/entfernt) blockt den Commit,
	# OHNE die Datei zu normalisieren oder umzuschreiben (CON-005).
	var diff_output: String = _git.diff_cached()
	var live_byte_digest: String = IMPACT_RESOLVER.staged_byte_digest(_strip_auto_managed_diff(diff_output))
	var live_path_digest: String = IMPACT_RESOLVER.path_digest(staged)
	var prepared_byte_digest: String = str(session.get("staged_byte_digest", ""))
	var prepared_path_digest: String = str(session.get("scope_path_digest", ""))
	if prepared_byte_digest.is_empty() or prepared_path_digest.is_empty():
		return {"ok": false, "error": "Digest-Bindung fehlt in Session — prepare ohne Content-Addressed-Scope gelaufen? Bitte `doki prepare` erneut."}
	if live_byte_digest != prepared_byte_digest:
		return {"ok": false, "error": "Byte-Drift: gestagte Bytes weichen vom prepare-Stand ab (Datei nach prepare verändert). Bitte `doki prepare` erneut — die Datei wird NICHT umgeschrieben."}
	if live_path_digest != prepared_path_digest:
		return {"ok": false, "error": "Pfad-Drift: gestagter Pfadbestand weicht vom prepare-Stand ab (Datei nach prepare hinzugefügt/entfernt). Bitte `doki prepare` erneut."}

	# Path-Gate: der gestagte Pfadbestand muss dem Snapshot entsprechen.
	var staged_sorted: Array = staged.duplicate()
	var snapshot_sorted: Array = snapshot.duplicate()
	staged_sorted.sort()
	snapshot_sorted.sort()
	if staged_sorted != snapshot_sorted:
		var extra: Array = staged.filter(func(f): return not snapshot.has(f))
		var missing: Array = snapshot.filter(func(f): return not staged.has(f))
		return {"ok": false, "error": "Staged-Dateien weichen von der Session ab (Stale Message?). Zusätzlich: %s — Fehlend: %s. Bitte `doki prepare` erneut." % [str(extra), str(missing)]}

	return {"ok": true}


## Resolves the current staged change to its required verification scope.
static func _resolve_scope(staged: Array) -> Dictionary:
	var resolver_script: Script = preload("res://scripts/preflight_v2/change_impact_resolver.gd")
	return resolver_script.resolve(staged)


static func _without_auto_managed(files: Array) -> Array:
	var result: Array = []
	for f in files:
		if not AUTO_MANAGED.has(str(f).get_file()):
			result.append(str(f))
	return result


## Filtert auto-managed Dateien aus einem `git diff --cached`-String heraus.
## Der Diff wird in Per-Datei-Sektionen gesplittet (jede beginnt mit `diff --git`),
## und Sektionen deren Dateiname in AUTO_MANAGED steht werden entfernt.
## Das verhindert Byte-Drift, wenn `finish` die DOKI-Artefakte staged.
static func _strip_auto_managed_diff(diff_output: String) -> String:
	if diff_output.is_empty():
		return ""
	var sections: PackedStringArray = diff_output.split("diff --git ")
	var kept: Array[String] = []
	for i in range(1, sections.size()):  # skip [0] = prefix before first diff
		var header: String = sections[i].split("\n")[0]
		# header sieht aus wie: a/path/to/file.json b/path/to/file.json
		var path_match := RegEx.new()
		path_match.compile("^[^ ]+ b/(.+)$")
		var m := path_match.search(header.strip_edges())
		if m != null:
			var filepath: String = m.get_string(1)
			if not AUTO_MANAGED.has(filepath.get_file()):
				kept.append("diff --git " + sections[i])
		else:
			kept.append("diff --git " + sections[i])
	return "".join(kept)


## V10-003: Verify AGENT_ACTIVITY_SEED against agent_activity.sh registry
func _verify_agent_activity_seed(agent_name: String, activity_seed: String) -> Dictionary:
	# Call agent_activity.sh seed <agent> to get registered seed
	# Resolve bash path: Windows needs full path (Git Bash), Unix uses PATH
	# (gleicher Fix wie prepare_flow — nacktes "bash" bricht unter Windows).
	var output: Array = []
	var repo_root: String = ProjectSettings.globalize_path("res://")
	var script_path: String = repo_root + "scripts/agent_activity.sh"
	var bash_path: String = OS.get_environment("SHELL")
	if bash_path.is_empty() or not FileAccess.file_exists(bash_path):
		for candidate in ["C:/Program Files/Git/usr/bin/bash.exe", "C:/Program Files/Git/bin/bash.exe"]:
			if FileAccess.file_exists(candidate):
				bash_path = candidate
				break
	if bash_path.is_empty():
		bash_path = "bash"  # Fallback: hope it's in PATH
	var exit_code: int = OS.execute(bash_path, [script_path, "seed", agent_name], output, true)
	if exit_code != 0:
		return {"ok": false, "error": "AGENT_ACTIVITY_SEED verification failed: agent '%s' not checked in or registry error (exit=%d)." % [agent_name, exit_code]}
	var registered_seed: String = str(output[0]).strip_edges() if output.size() > 0 else ""
	if registered_seed.is_empty():
		return {"ok": false, "error": "AGENT_ACTIVITY_SEED verification failed: no seed registered for agent '%s'." % agent_name}
	if registered_seed != activity_seed:
		return {"ok": false, "error": "AGENT_ACTIVITY_SEED mismatch: provided seed does not match registered seed for agent '%s'." % agent_name}
	return {"ok": true}