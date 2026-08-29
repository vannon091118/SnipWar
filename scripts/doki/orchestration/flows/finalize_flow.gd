class_name DOKI_FinalizeFlow
extends RefCounted
## Zuständigkeit: finalize-Schritt — verified → idle (idempotent) + repair
## (Recovery nach Crash / rebase / amend). Staged NICHTS (v0.1.1-Fix).

var _repo_root: String
var _chain_store: DOKI_ChainStore
var _session_store: DOKI_SessionStore
var _index_store: DOKI_ChangeIndexStore
var _git: DOKI_GitHelper
var _arc_engine: DOKI_ArcEngine
var _artifacts: DOKI_ArtifactWriter


func _init(
	repo_root: String,
	chain_store: DOKI_ChainStore,
	session_store: DOKI_SessionStore,
	index_store: DOKI_ChangeIndexStore,
	git: DOKI_GitHelper,
	arc_engine: DOKI_ArcEngine,
	artifacts: DOKI_ArtifactWriter
) -> void:
	_repo_root = repo_root
	_chain_store = chain_store
	_session_store = session_store
	_index_store = index_store
	_git = git
	_arc_engine = arc_engine
	_artifacts = artifacts


## finalize_flow() → {ok, idempotent, entry, arc}
func run() -> Dictionary:
	var state: Dictionary = _session_store.ensure_state(DOKI_SessionStore.STATE_VERIFIED)
	if not state["ok"]:
		# Idempotent: idle → prüfen, ob ein Amend den letzten Chain-Hash verändert hat
		# (dann Eintrag-Hash nachziehen), sonst nichts zu tun (kein Fehler).
		var amend_fix: Dictionary = _sync_amended_entry_hash()
		if not amend_fix["ok"]:
			return amend_fix
		return {"ok": true, "idempotent": true, "error": ""}
	var session: Dictionary = state["session"]

	var head: String = _git.head_hash_full()
	if head == str(session.get("git_head_before", "")):
		return {"ok": false, "error": "finalize: HEAD unverändert — Git-Commit fehlt. (`doki repair` für Recovery)"}

	# Idempotenz-Guard: Wenn finalize schon einmal lief (z. B. Stage-Fehler oder
	# Crash zwischen commit und reset), trägt der letzte Chain-Eintrag bereits
	# diesen Commit (gleicher Hash + Composite). Dann nur Stage nachholen + Reset —
	# KEIN zweiter append/Arc-Advance/CHANGELOG-Eintrag (Doppel-Einträge brechen
	# Check 9a: c-Folge wäre nicht mehr lückenlos).
	var existing_entries: Array = _chain_store.entries()
	if not existing_entries.is_empty():
		var last_existing: Dictionary = existing_entries[existing_entries.size() - 1]
		if str(last_existing.get("hash", "")) == head and str(last_existing.get("composite", "")) == str(session.get("composite", "")):
			var restage: Dictionary = _git.stage(["narrative_chain.json", "change_index.json", "scripts/doki/data/arcs.json", "CHANGELOG.md"])
			if not restage["ok"]:
				return {"ok": false, "error": "finalize: narrative Dateien konnten nicht gestaged werden: %s" % str(restage.get("stderr", "?"))}
			_artifacts.cleanup_transients()
			_session_store.reset()
			return {"ok": true, "idempotent": true, "entry": last_existing, "note": "finalize bereits ausgeführt — Stage nachgeholt"}

	# Chain-Append (Summary = erste Body-Zeile)
	var summary: String = DOKI_MessageBuilder.summary_from_body(str(session.get("body_text", "")))
	if summary.is_empty():
		summary = str(session.get("impulse", ""))
	var ci_analyze: Dictionary = session.get("_entities", {})
	var data_changes: Array = ci_analyze.get("data_changes", []) if not ci_analyze.is_empty() else []
	var entity_ids: Array = ci_analyze.get("entity_ids", []) if not ci_analyze.is_empty() else []
	var entry: Dictionary = _chain_store.append_entry(
		head,
		str(session.get("composite", "")),
		str(session.get("mood", "")),
		str(session.get("narrator", "")),
		str(session.get("model_id", "")),
		summary,
		str(session.get("subject", "")),
		str(session.get("prev_narrator", "")),
		str(session.get("prev_model", "")),
		data_changes,
		str(session.get("arc_id", "")),
		int(session.get("p_id", 0)),
		int(session.get("c", 0)),
		int(session.get("j", 0)),
		int(session.get("n", 0)),
		int(session.get("a", 0)),
		int(session.get("p", 0))
	)

	# ChangeIndex mit Git-Hash verknüpfen — der analysierte Index kommt aus der
	# Session (finish), sonst gingen die neuen Entitäten verloren.
	var index: Dictionary = session.get("_index", {})
	if index.is_empty():
		index = _index_store.read()
	_index_store.link_commit(
		index,
		head,
		int(session.get("p_id", 0)),
		str(session.get("composite", "")),
		int(session.get("c", 0)),
		entity_ids
	)

	# Arc-Advance (schreibt arcs.json — Arc-State, z. B. completed + neuer aktiver Arc).
	# Der NÄCHSTER-ARC-Vorschlag des Narrators (aus finish geparst) wird übernommen.
	var impulse_class: String = str(session.get("impulse_class", "CODE"))
	var next_arc: Dictionary = session.get("next_arc", {})
	var arc_result: Dictionary = _arc_engine.advance(entity_ids, not (session.get("sideplot", {}) as Dictionary).is_empty(), impulse_class, next_arc)

	# CHANGELOG + change_index persistieren und sofort für den nächsten Commit
	# nachziehen. Diese vier Dateien sind DOKI-eigene Folgeartefakte, kein neuer
	# Nutzer-Scope.
	var date_str: String = _chain_store.entry_timestamp(int(session.get("p_id", 1)))
	_artifacts.apply_finalize_artifacts(session, index, date_str)
	var stage_res: Dictionary = _git.stage(["narrative_chain.json", "change_index.json", "scripts/doki/data/arcs.json", "CHANGELOG.md"])
	if not stage_res["ok"]:
		return {"ok": false, "error": "finalize: narrative Dateien konnten nicht gestaged werden: %s" % str(stage_res.get("stderr", "?"))}

	# Verbrauchte Transienten aufräumen (kein Dirty-State)
	_artifacts.cleanup_transients()

	_session_store.reset()
	return {"ok": true, "idempotent": false, "entry": entry, "arc": arc_result}


## Nach `git commit --amend` hat sich der HEAD-Hash geändert, der letzte
## Chain-Eintrag trägt aber noch den alten. Hier: Eintrag per Composite-Abgleich
## aktualisieren (gleicher Commit, neuer Hash) und Chain stagen.
func _sync_amended_entry_hash() -> Dictionary:
	var chain: Dictionary = _chain_store.read()
	var head: String = _git.head_hash_full()
	var head_msg: String = _git.head_message()
	var sync: Dictionary = amended_entry_hash_sync(chain, head, head_msg)
	if not sync["ok"]:
		return sync
	if not bool(sync["changed"]):
		return {"ok": true}
	chain = sync["chain"]
	_chain_store.save(chain)
	var stage_res: Dictionary = _git.stage(["narrative_chain.json"])
	if not stage_res["ok"]:
		return {"ok": false, "error": "finalize: narrative_chain.json konnte nicht gestaged werden: %s" % str(stage_res.get("stderr", "?"))}
	return {"ok": true}


## Reine Hash-Sync-Entscheidung (git-frei, für Selfcheck testbar): Wenn der
## letzte Chain-Eintrag denselben Composite trägt wie der aktuelle HEAD
## (gleicher Commit, neuer Hash nach `git commit --amend`), Hash aktualisieren.
## Rückgabe {ok, changed, chain} — save/stage macht der Caller.
static func amended_entry_hash_sync(chain: Dictionary, head: String, head_msg: String) -> Dictionary:
	var entries: Array = chain.get("entries", [])
	if entries.is_empty():
		return {"ok": true, "changed": false, "chain": chain}
	var last: Dictionary = entries[entries.size() - 1]
	var re := RegEx.new()
	re.compile("\\[COMPOSITE:(c\\d+j\\d+n\\d+a\\d+p\\d+)\\]")
	var m: RegExMatch = re.search(head_msg)
	if m == null:
		return {"ok": true, "changed": false, "chain": chain}
	var head_composite: String = m.get_string(1)
	if head_composite == str(last.get("composite", "")) and str(last.get("hash", "")) != head:
		last["hash"] = head
		entries[entries.size() - 1] = last
		chain["entries"] = entries
		return {"ok": true, "changed": true, "chain": chain}
	return {"ok": true, "changed": false, "chain": chain}


## ─── Recovery-Log: DOKI-interne Diagnose-Spur ────────────────────────────
## Verwaiste/reparierte Sessions werden nach .doki/recovery_log.json protokolliert
## (.doki ist gitignored). Bewusst KEINE Chain-/Index-Datei: diese dürfen im
## verwaisten verified-Fall per Vertrag unangetastet bleiben.
static func recovery_log_path(repo_root: String) -> String:
	return repo_root.path_join(".doki").path_join("recovery_log.json")


static func record_recovery(repo_root: String, kind: String, reason: String) -> void:
	var path: String = recovery_log_path(repo_root)
	var entries: Array = []
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Array:
			entries = parsed
	entries.append({
		"kind": kind,
		"reason": reason,
		"at": Time.get_datetime_string_from_system(),
	})
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(entries, "\t"))
		file.close()


## Liest das Recovery-Log zurück (für Selfcheck/Diagnose; leer, wenn keins).
static func recovery_read(repo_root: String) -> Array:
	var path: String = recovery_log_path(repo_root)
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Array else []


## Verwaister-verified-Entscheidung (rein, git-frei — für den Selfcheck testbar).
## DOKI validiert die verified-Session mit drei Prüfungen:
##   a) Existiert der erwartete Commit?   → HEAD ist NICHT mehr der Anker
##   b) Stimmt HEAD mit dem Session-Anker überein? → HEAD == git_head_before
##   c) Existiert .commit_msg.txt?        → Diagnose (Message verloren?)
## Der erwartete Commit existiert genau dann, wenn HEAD den Session-Anker
## (git_head_before) verlassen hat. Bleibt HEAD auf dem Anker, wurde `git commit
## -F .commit_msg.txt` nie ausgeführt bzw. der Commit ist verloren → die
## verified-Session ist VERWAIST. commit_msg_exists verstärkt nur die Begründung,
## ändert die Entscheidung aber nicht (die Message überlebt einen echten Commit).
static func verified_orphan_decision(head: String, git_head_before: String, commit_msg_exists: bool) -> Dictionary:
	var commit_created: bool = not git_head_before.is_empty() and not head.is_empty() and head != git_head_before
	if commit_created:
		return {"orphaned": false, "reason": ""}
	var anchor_label: String = git_head_before.substr(0, 7) if not git_head_before.is_empty() else "(leer — korrupt)"
	var msg_note: String = "ausstehende Message .commit_msg.txt noch vorhanden" if commit_msg_exists else "ausstehende Message fehlt"
	var reason: String = "Verwaiste verified-Session atomar auf idle zurückgesetzt: HEAD steht noch auf dem Session-Anker %s, es wurde kein DOKI-Commit erzeugt; %s — Chain- und Index-Dateien blieben unberührt." % [anchor_label, msg_note]
	return {"orphaned": true, "reason": reason}


## repair() → {ok, repaired:[...]}
func repair() -> Dictionary:
	var session: Dictionary = _session_store.read()
	var head: String = _git.head_hash_full()
	var repaired: Array = []

	# ─ 1. verified validieren (Recovery-Kern) ──────────────────────────────
	# Verwaister-Fall: die verified-Session hat KEINEN passenden Commit (HEAD
	# steht noch auf dem Anker). Dann: atomar auf idle zurücksetzen, KEINE
	# Chain-/Index-Dateien verändern, Recovery-Grund protokollieren. Erst danach
	# läuft der normale Flow wieder: prepare → finish → DOKI-Commit → SHA-Prüfung
	# (finalize) → finalize.
	if session.get("state") == DOKI_SessionStore.STATE_VERIFIED:
		var decision: Dictionary = verified_orphan_decision(
			head,
			str(session.get("git_head_before", "")),
			FileAccess.file_exists(_repo_root.path_join(".commit_msg.txt"))
		)
		if bool(decision["orphaned"]):
			var reason: String = str(decision["reason"])
			record_recovery(_repo_root, "orphaned_verified", reason)
			_session_store.reset()
			repaired.append(reason)
			# Früh-Return: im verwaisten Fall sind Chain/Index tabu — der
			# Anker-Re-Anchor (Fall 3) würde eine Chain-Datei schreiben.
			return {"ok": true, "repaired": repaired}
		# Commit existiert → Crash zwischen commit und finalize: finalize nachholen.
		var result: Dictionary = run()
		if not result["ok"]:
			return result
		repaired.append("finalize nachgeholt (Hash %s)." % head.substr(0, 7))
		session = _session_store.read()

	# 2. Abgebrochener Flow: zurücksetzen
	if session.get("state") == DOKI_SessionStore.STATE_PREPARED:
		_session_store.reset()
		repaired.append("Abgebrochener prepare-Flow zurückgesetzt.")

	# 3. Chain-Anker an HEAD neu verankern (rebase/amend: Hashes neu geschrieben)
	var chain: Dictionary = _chain_store.read()
	var anchor_hash: String = str(chain.get("anchor", {}).get("hash", ""))
	if anchor_hash != head:
		chain["anchor"] = {
			"hash": head,
			"subject": _git.head_subject(),
			"date": _git.head_date(),
		}
		var repair_log: Array = chain.get("repairs", [])
		repair_log.append({"at_hash": head, "note": "Anker nach rebase/amend/force-push neu verankert."})
		chain["repairs"] = repair_log
		_chain_store.save(chain)
		repaired.append("Chain-Anker auf HEAD %s neu verankert." % head.substr(0, 7))

	return {"ok": true, "repaired": repaired}