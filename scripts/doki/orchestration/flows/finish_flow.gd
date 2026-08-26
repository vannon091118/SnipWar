class_name DOKI_FinishFlow
extends RefCounted
## Zuständigkeit: finish-Schritt — prepared → verified.
## Baut Message, orchestriert die 9 Checks (1-6 weich / 7-9 hart) und schreibt
## Artefakte ERST nach Erfolg (Retry ohne Disk-Nebenwirkungen). Dazu verify_only
## für den commit-msg Hook.

var _repo_root: String
var _session_store: DOKI_SessionStore
var _chain_store: DOKI_ChainStore
var _index_store: DOKI_ChangeIndexStore
var _git: DOKI_GitHelper
var _change_index_engine: DOKI_ChangeIndexEngine
var _verifier: DOKI_Verifier
var _message_builder: DOKI_MessageBuilder
var _artifacts: DOKI_ArtifactWriter


func _init(
	repo_root: String,
	session_store: DOKI_SessionStore,
	chain_store: DOKI_ChainStore,
	index_store: DOKI_ChangeIndexStore,
	git: DOKI_GitHelper,
	change_index_engine: DOKI_ChangeIndexEngine,
	verifier: DOKI_Verifier,
	message_builder: DOKI_MessageBuilder,
	artifacts: DOKI_ArtifactWriter
) -> void:
	_repo_root = repo_root
	_session_store = session_store
	_chain_store = chain_store
	_index_store = index_store
	_git = git
	_change_index_engine = change_index_engine
	_verifier = verifier
	_message_builder = message_builder
	_artifacts = artifacts


## finish(body) → {ok, message, soft_errors} | {ok:false, errors, phase:"verify"}
func run(body: String) -> Dictionary:
	var state: Dictionary = _session_store.ensure_state(DOKI_SessionStore.STATE_PREPARED)
	if not state["ok"]:
		return state
	var session: Dictionary = state["session"]

	# Diff + Entitäten (index ist jetzt der Schreibpunkt — finish persistiert)
	var index: Dictionary = _index_store.read()
	var staged: Array = _git.staged_files()
	if staged.is_empty():
		return {"ok": false, "error": "Gestagte Änderungen fehlen (wurden sie zurückgezogen?)."}
	var diff_output: String = _git.diff_cached()
	var analyze: Dictionary = _change_index_engine.analyze(staged, diff_output, index, int(session["p_id"]))

	# Message assemblieren
	var message: Dictionary = _message_builder.assemble(session, body, analyze)
	var full_message: String = str(message["full_message"])
	var subject_line: String = str(message["subject"])

	# 9 Checks
	var verify_result: Dictionary = _verifier.validate(full_message, session, _chain_store.read(), staged.duplicate(), _git.unstaged_diffs(), {})
	var hard_errors: Array = verify_result["hard_errors"]
	if not hard_errors.is_empty():
		return {"ok": false, "errors": hard_errors, "soft_errors": verify_result["soft_errors"], "phase": "verify", "message": full_message}

	# Erst JETZT schreiben (Fehlschlag = Disk unberührt).
	# Deterministischer Artefakt-Timestamp aus der Chain (kein Time.get_date_string —
	# sonst bricht die Reproduzierbarkeit über Tagesgrenzen).
	var date_str: String = _chain_store.entry_timestamp(int(session.get("p_id", 1)))
	_artifacts.apply_commit_artifacts(session, message, analyze, index, subject_line, date_str)

	session["body_text"] = body
	session["state"] = DOKI_SessionStore.STATE_VERIFIED
	_session_store.save(session)

	return {"ok": true, "message": full_message, "soft_errors": verify_result["soft_errors"], "reason_lines": message.get("reason_lines", [])}


## verify_only(message) — für den commit-msg Hook (Checks 1-9, keine Nebenwirkungen).
func verify_only(message: String) -> Dictionary:
	var session: Dictionary = _session_store.read()
	if session.get("state") != DOKI_SessionStore.STATE_VERIFIED:
		return {"ok": false, "errors": ["verify-only: Session ist nicht im verified-Zustand. Vollständiger DOKI-Flow (prepare→finish) erforderlich."], "soft_errors": []}
	var result: Dictionary = _verifier.validate(message, session, _chain_store.read(), _git.staged_files(), _git.unstaged_diffs(), {})
	return {"ok": result["success"], "errors": result["hard_errors"], "soft_errors": result["soft_errors"]}