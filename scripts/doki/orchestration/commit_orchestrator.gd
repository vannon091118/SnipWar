class_name DOKI_CommitOrchestrator
extends RefCounted
## Slanker Koordinator: verdrahtet Engines/Stores/Flows und delegiert.
## Zuständigkeiten liegen in den Modulen (SRP):
##   SessionBuilder  → Session + Prompt-Kontext ableiten
##   MessageBuilder  → Commit-Message + Begründungszeilen
##   ArtifactWriter  → CHANGELOG / Index / .commit_msg / Stagen / Cleanup
##   PrepareFlow     → prepare (idle → prepared)
##   FinishFlow      → finish + verify-only (prepared → verified)
##   FinalizeFlow    → finalize + repair (verified → idle)
##   GateFlow        → pre-commit Gate
##   StatusFlow      → status

const DATA_DIR_NAME: String = "data"

var repo_root: String
var data_dir: String
var chain_store: DOKI_ChainStore
var session_store: DOKI_SessionStore
var index_store: DOKI_ChangeIndexStore
var catalog: DOKI_NarratorCatalog
var moods: DOKI_MoodOverlay
var git: DOKI_GitHelper
var sideplot_engine: DOKI_SidePlotEngine
var arc_engine: DOKI_ArcEngine
var relationship_engine: DOKI_RelationshipEngine
var voice: DOKI_VoiceComposer
var change_index_engine: DOKI_ChangeIndexEngine
var verifier: DOKI_Verifier
var session_builder: DOKI_SessionBuilder
var message_builder: DOKI_MessageBuilder
var artifacts: DOKI_ArtifactWriter
var prepare_flow: DOKI_PrepareFlow
var finish_flow: DOKI_FinishFlow
var finalize_flow: DOKI_FinalizeFlow
var gate_flow: DOKI_GateFlow
var status_flow: DOKI_StatusFlow


func _init(repo_root_value: String) -> void:
	repo_root = repo_root_value
	data_dir = "res://scripts/doki/%s" % DATA_DIR_NAME
	chain_store = DOKI_ChainStore.new(repo_root)
	session_store = DOKI_SessionStore.new(repo_root)
	index_store = DOKI_ChangeIndexStore.new(repo_root)
	catalog = DOKI_NarratorCatalog.new(data_dir)
	moods = DOKI_MoodOverlay.new(data_dir)
	git = DOKI_GitHelper.new(repo_root)
	sideplot_engine = DOKI_SidePlotEngine.new(repo_root)
	arc_engine = DOKI_ArcEngine.new(data_dir)
	relationship_engine = DOKI_RelationshipEngine.new()
	voice = DOKI_VoiceComposer.new(catalog, moods)
	change_index_engine = DOKI_ChangeIndexEngine.new(index_store)
	verifier = DOKI_Verifier.new(catalog, repo_root)
	session_builder = DOKI_SessionBuilder.new(catalog, moods)
	message_builder = DOKI_MessageBuilder.new(voice)
	artifacts = DOKI_ArtifactWriter.new(repo_root, git, index_store)
	prepare_flow = DOKI_PrepareFlow.new(
		repo_root, chain_store, session_store, catalog, moods, git,
		sideplot_engine, arc_engine, relationship_engine, voice,
		change_index_engine, index_store, session_builder, artifacts
	)
	finish_flow = DOKI_FinishFlow.new(
		repo_root, session_store, chain_store, index_store, git,
		change_index_engine, verifier, message_builder, artifacts
	)
	finalize_flow = DOKI_FinalizeFlow.new(
		repo_root, chain_store, session_store, index_store, git, arc_engine, artifacts
	)
	gate_flow = DOKI_GateFlow.new(repo_root, session_store, git)
	status_flow = DOKI_StatusFlow.new(chain_store, session_store)


## ═══ init — Genesis: Chain am aktuellen HEAD verankern ══════════════════
## seed_last > 0: die letzten N Bestands-Commits als deterministische
## Chain-Einträge verankern (die „Geschichte vor DOKI").
func init_flow(seed_last: int = 0) -> Dictionary:
	if not git.check_repo():
		return {"ok": false, "error": "Kein Git-Repository: %s" % repo_root}
	var chain: Dictionary = chain_store.read()
	if not chain.get("anchor", {}).is_empty():
		return {"ok": false, "error": "DOKI ist bereits initialisiert (Anchor: %s)." % str(chain["anchor"].get("hash", "?"))}
	chain = chain_store.init_genesis(git.head_hash_full(), git.head_subject(), git.head_date())

	# History-Seeding (letzte N Commits → Chain, deterministisch)
	var seeded: int = 0
	if seed_last > 0:
		var commits: Array = git.last_commits(seed_last)
		if commits.is_empty():
			return {"ok": false, "error": "init --seed-last: keine Commits gefunden."}
		var entries: Array = []
		var prev_composite: String = DOKI_RngEngine.GENESIS_COMPOSITE
		var prev_mood: String = DOKI_RngEngine.GENESIS_MOOD
		var prev_narrator: String = ""
		var mood_pool: Array = moods.mood_pool()
		if mood_pool.is_empty():
			mood_pool = DOKI_MoodOverlay.default_pool()
		var arc: Dictionary = arc_engine.active_arc()
		var limits: Dictionary = {"j": 99, "n": 14, "a": maxi(1, arc_engine.arc_count()), "p": 1}
		for commit in commits:
			var seq: int = entries.size() + 1
			var subject: String = str(commit["subject"])
			limits["p"] = maxi(1, seq)
			# Kein echter Diff verfügbar (Bestands-Commit) — diff_hash deterministisch
			# aus Subject+Hash (nur für History; echte Commits nutzen den Diff).
			var derived: Dictionary = DOKI_RngEngine.derive(
				prev_composite,
				git.commit_tree_hash(str(commit["hash"])),
				str(DOKI_RngEngine.djb2(subject + str(commit["hash"]))),
				subject, limits, prev_mood, mood_pool
			)
			var narrator: Dictionary = catalog.by_index(int(derived["n"]))
			var entry := {
				"hash": str(commit["hash"]),
				"composite": str(derived["composite"]),
				"mood": str(derived["mood"]),
				"narrator": str(narrator.get("name", "?")),
				"model_id": "history",
				"date": str(commit["date"]),
				"summary": _truncate_subject(subject),
				"arc": str(arc.get("id", "")),
				"p_id": seq,
				"c": int(derived["c"]),
				"j": int(derived["j"]),
				"n": int(derived["n"]),
				"a": int(derived["a"]),
				"p": int(derived["p"]),
				"data_changes": [],
				"seeded": true,
			}
			if not prev_narrator.is_empty():
				entry["prev_narrator"] = prev_narrator
			entries.append(entry)
			prev_composite = str(derived["composite"])
			prev_mood = str(derived["mood"])
			prev_narrator = str(narrator.get("name", ""))
		chain_store.seed_history(entries)
		seeded = entries.size()

	# change_index + CHANGELOG sicherstellen (leer ok)
	if not index_store.exists():
		index_store.save(index_store.read())
	if not FileAccess.file_exists(repo_root.path_join("CHANGELOG.md")):
		var file := FileAccess.open(repo_root.path_join("CHANGELOG.md"), FileAccess.WRITE)
		if file != null:
			file.store_string("# CHANGELOG\n\nNarrative Historie des SnipWar-Repos (CommitLayer v2).\n")
			file.close()
	# Die Doku-Artefakte + Chain sofort stagen — sie reisen mit dem ersten
	# DOKI-Commit (und Check 8 + Gate bleiben sauber).
	git.stage(["CHANGELOG.md", "change_index.json", "narrative_chain.json"])
	session_store.reset()
	return {"ok": true, "anchor": chain.get("anchor", {}), "genesis_date": chain.get("genesis_date", ""), "seeded": seeded}


static func _truncate_subject(s: String) -> String:
	if s.length() <= 200:
		return s
	return s.substr(0, 197) + "..."


## ─── Delegation an Flow-Module ──────────────────────────────────────────
func prepare(impulse: String, model_id: String) -> Dictionary:
	return prepare_flow.run(impulse, model_id)


func finish(body: String) -> Dictionary:
	return finish_flow.run(body)


## ─── amend — DOKI-Message eines bestehenden Commits nachbearbeiten ────────
## Ablauf: HEAD-Message lesen, nur den Narrator-Body ersetzen (Subject, Tokens,
## Arc-Zeile, Begründungszeilen bleiben), chain-verankert verifizieren (Checks
## 1-8; Check 9 braucht die Session und ist für Amend dokumentiert übersprungen),
## .commit_msg.txt schreiben. Danach: `git commit --amend -F .commit_msg.txt`.
func amend(body: String) -> Dictionary:
	var head_msg: String = git.head_message()
	if not head_msg.contains("[COMPOSITE:"):
		return {"ok": false, "error": "HEAD ist kein DOKI-Commit — `doki amend` gilt nur für DOKI-Messages."}
	var reconstruction: Dictionary = reconstruct_amend_message(head_msg, body)
	if not reconstruction["ok"]:
		return reconstruction
	var new_message: String = str(reconstruction["message"])

	# Chain-verankerte Verifikation (Checks 1-8)
	var verify_result: Dictionary = verifier.validate_amend(new_message, chain_store.read(), git.unstaged_diffs())
	if not verify_result["success"]:
		return {"ok": false, "errors": verify_result["hard_errors"], "soft_errors": verify_result["soft_errors"], "phase": "verify", "message": new_message}

	artifacts.write_commit_msg(new_message)
	return {"ok": true, "message": new_message, "soft_errors": verify_result["soft_errors"]}


## Reine String-Logik der Amend-Rekonstruktion (git-frei, für Selfcheck testbar):
## Body-Sektion zwischen [NARRATOR:X] und der Zeile [MODEL: ersetzen; Subject,
## Tokens, Arc-Zeile und Begründungszeilen bleiben. [MODEL: muss am Zeilenanfang
## stehen — ein „[MODEL:" im Fließtext des Bodys darf die Sektion nicht
## vorzeitig beenden (Regex-Fix, Regression im Selfcheck abgesichert).
static func reconstruct_amend_message(head_msg: String, body: String) -> Dictionary:
	if not head_msg.contains("[COMPOSITE:"):
		return {"ok": false, "error": "HEAD ist kein DOKI-Commit — `doki amend` gilt nur für DOKI-Messages."}
	var re := RegEx.new()
	re.compile("(\\[NARRATOR:[^]]*\\])(?s)(.*?)(\\n\\[MODEL:)")
	var m: RegExMatch = re.search(head_msg)
	if m == null:
		return {"ok": false, "error": "HEAD-Message hat keine parsebare Body-Sektion ([NARRATOR: … [MODEL:)."}
	var prefix: String = head_msg.substr(0, m.get_start(1))  # Subject + Leerzeile
	var new_message: String = prefix + m.get_string(1) + "\n\n" + body.strip_edges() + "\n\n[MODEL:" + head_msg.substr(m.get_end(3))
	return {"ok": true, "message": new_message}


func verify_only(message: String) -> Dictionary:
	return finish_flow.verify_only(message)


func finalize_flow_run() -> Dictionary:
	return finalize_flow.run()


func repair() -> Dictionary:
	return finalize_flow.repair()


func gate() -> Dictionary:
	return gate_flow.run()


func status() -> Dictionary:
	return status_flow.run()