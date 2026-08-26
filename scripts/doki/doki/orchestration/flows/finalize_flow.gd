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
		# Idempotent: wenn idle, ist nichts zu tun (kein Fehler)
		return {"ok": true, "idempotent": true, "error": ""}
	var session: Dictionary = state["session"]

	var head: String = _git.head_hash_full()
	if head == str(session.get("git_head_before", "")):
		return {"ok": false, "error": "finalize: HEAD unverändert — Git-Commit fehlt. (`doki repair` für Recovery)"}

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

	# ChangeIndex mit Git-Hash verknüpfen (Entitäten aus finish)
	var index: Dictionary = _index_store.read()
	_index_store.link_commit(
		index,
		head,
		int(session.get("p_id", 0)),
		str(session.get("composite", "")),
		int(session.get("c", 0)),
		entity_ids
	)
	_index_store.save(index)

	# Arc-Advance
	var arc_result: Dictionary = _arc_engine.advance(entity_ids, not (session.get("sideplot", {}) as Dictionary).is_empty())

	# Chain + Index stagen — sie reisen mit dem NÄCHSTEN Commit (der aktuelle
	# Commit ist bereits erstellt). Sonst bliebe der Repo-Zustand dirty und
	# Check 8 (DocSync) blockte den nächsten Commit. Kein neuer Commit nötig.
	var stage_res: Dictionary = _git.stage(["narrative_chain.json", "change_index.json"])
	if not stage_res["ok"]:
		return {"ok": false, "error": "finalize: narrative Dateien konnten nicht gestaged werden: %s" % str(stage_res.get("stderr", "?"))}

	# Verbrauchte Transienten aufräumen (kein Dirty-State)
	_artifacts.cleanup_transients()

	_session_store.reset()
	return {"ok": true, "idempotent": false, "entry": entry, "arc": arc_result}


## repair() → {ok, repaired:[...]}
func repair() -> Dictionary:
	var session: Dictionary = _session_store.read()
	var head: String = _git.head_hash_full()
	var repaired: Array = []

	# 1. Crash zwischen commit und finalize: Chain-Eintrag nachholen
	if session.get("state") == DOKI_SessionStore.STATE_VERIFIED and head != str(session.get("git_head_before", "")):
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