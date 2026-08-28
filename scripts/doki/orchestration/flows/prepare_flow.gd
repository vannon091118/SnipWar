class_name DOKI_PrepareFlow
extends RefCounted
## Zuständigkeit: prepare-Schritt — idle → prepared.
## Deterministisch: Composite aus Chain + TreeHash + DiffHash + Impuls,
## Session bauen, Prompt schreiben. Kein Zeit-/Zufalls-Input.

var _repo_root: String
var _chain_store: DOKI_ChainStore
var _session_store: DOKI_SessionStore
var _catalog: DOKI_NarratorCatalog
var _moods: DOKI_MoodOverlay
var _git: DOKI_GitHelper
var _sideplot_engine: DOKI_SidePlotEngine
var _arc_engine: DOKI_ArcEngine
var _relationship_engine: DOKI_RelationshipEngine
var _voice: DOKI_VoiceComposer
var _change_index_engine: DOKI_ChangeIndexEngine
var _index_store: DOKI_ChangeIndexStore
var _session_builder: DOKI_SessionBuilder
var _artifacts: DOKI_ArtifactWriter


func _init(
	repo_root: String,
	chain_store: DOKI_ChainStore,
	session_store: DOKI_SessionStore,
	catalog: DOKI_NarratorCatalog,
	moods: DOKI_MoodOverlay,
	git: DOKI_GitHelper,
	sideplot_engine: DOKI_SidePlotEngine,
	arc_engine: DOKI_ArcEngine,
	relationship_engine: DOKI_RelationshipEngine,
	voice: DOKI_VoiceComposer,
	change_index_engine: DOKI_ChangeIndexEngine,
	index_store: DOKI_ChangeIndexStore,
	session_builder: DOKI_SessionBuilder,
	artifacts: DOKI_ArtifactWriter
) -> void:
	_repo_root = repo_root
	_chain_store = chain_store
	_session_store = session_store
	_catalog = catalog
	_moods = moods
	_git = git
	_sideplot_engine = sideplot_engine
	_arc_engine = arc_engine
	_relationship_engine = relationship_engine
	_voice = voice
	_change_index_engine = change_index_engine
	_index_store = index_store
	_session_builder = session_builder
	_artifacts = artifacts


## prepare(impulse, model_id) → {ok, session, prompt_path}
func run(impulse: String, model_id: String) -> Dictionary:
	var state: Dictionary = _session_store.ensure_state(DOKI_SessionStore.STATE_IDLE)
	if not state["ok"]:
		return state

	if not _git.check_repo():
		return {"ok": false, "error": "Kein Git-Repository: %s" % _repo_root}

	var staged: Array = _git.staged_files()
	if staged.is_empty():
		return {"ok": false, "error": "Keine gestagten Änderungen — erst `git add <dateien>`, dann prepare."}

	# Atomicity-Gate (früh, wie Check 10): ein Commit = EINE logische Einheit.
	# Mehr als MAX_FILES_PER_COMMIT User-Dateien → sofort blocken, bevor der
	# Prompt geschrieben wird (Mega-Commits fressen Story-Platz und Info).
	var user_files: Array = []
	for f in staged:
		if not DOKI_Verifier.AUTO_MANAGED.has(str(f).get_file()):
			user_files.append(str(f))
	if user_files.size() > DOKI_Verifier.MAX_FILES_PER_COMMIT:
		return {"ok": false, "error": "Atomicity-Gate: %d Dateien gestaged (max %d). Bitte in atomare Commits aufteilen — ein Commit = eine logische Einheit." % [user_files.size(), DOKI_Verifier.MAX_FILES_PER_COMMIT]}

	var chain: Dictionary = _chain_store.read()
	if chain.get("anchor", {}).is_empty():
		return {"ok": false, "error": "DOKI nicht initialisiert — erst `doki init`."}

	var entries: Array = chain.get("entries", [])
	var prev_composite: String = DOKI_RngEngine.GENESIS_COMPOSITE
	var prev_mood: String = DOKI_RngEngine.GENESIS_MOOD
	if not entries.is_empty():
		var last: Dictionary = entries[entries.size() - 1]
		prev_composite = str(last.get("composite", DOKI_RngEngine.GENESIS_COMPOSITE))
		prev_mood = str(last.get("mood", DOKI_RngEngine.GENESIS_MOOD))

	# Kausaler Seed: Tree + Diff + Impuls → Composite (deterministisch)
	var tree_hash: String = _git.head_tree_hash()
	var diff_output: String = _git.diff_cached()
	var diff_hash: int = DOKI_RngEngine.djb2(diff_output)
	var mood_pool: Array = _moods.mood_pool()
	if mood_pool.is_empty():
		mood_pool = DOKI_MoodOverlay.default_pool()
	var arc: Dictionary = _arc_engine.active_arc()
	var p_limit: int = maxi(1, entries.size() + 1)
	var limits: Dictionary = {"j": 99, "n": 14, "a": maxi(1, _arc_engine.arc_count()), "p": p_limit}
	var result: Dictionary = DOKI_RngEngine.derive(prev_composite, tree_hash, str(diff_hash), impulse, limits, prev_mood, mood_pool)
	result["impulse_class"] = DOKI_VoiceComposer.classify_impulse(impulse)
	# j → narrative Anweisungen dekodieren (tone/structure/callback) — wie im Original.
	var decoded: Dictionary = DOKI_RngEngine.decode_j(int(result["j"]), mood_pool, _moods.decoding())
	result["tone"] = str(decoded.get("tone", "sachlich"))
	result["structure"] = str(decoded.get("structure", "chronologisch"))
	result["callback"] = bool(decoded.get("callback", false))

	# Narrator + Mood + Decoding
	var narrator: Dictionary = _catalog.by_index(int(result["n"]))
	var prev_info: Dictionary = _chain_store.previous_narrator(str(narrator.get("name", "")))
	var prev_narrator: String = str(prev_info.get("name", ""))
	var prev_model: String = str(prev_info.get("model_id", ""))

	# Vorherige Klasse aus dem letzten Chain-Eintrag (für Richtungswechsel)
	var prev_class: String = ""
	if not entries.is_empty():
		var last_summary: String = str(entries[entries.size() - 1].get("summary", ""))
		if not last_summary.is_empty():
			prev_class = DOKI_VoiceComposer.classify_impulse(last_summary)

	# SidePlot (Merge) + ChangeIndex-Vorschau (für Arc-Gewicht, NICHT persistieren)
	var sideplot: Dictionary = _sideplot_engine.build_context(entries)
	var index: Dictionary = _index_store.read()
	var analyze: Dictionary = _change_index_engine.analyze(staged, diff_output, index, int(result["p"]))
	var arc_forecast: Dictionary = _arc_engine.forecast_weight(arc, analyze["entity_ids"], not sideplot.is_empty(), str(result["impulse_class"]))

	# Beziehung zum Vorgänger-Narrator
	var relationship: Dictionary = {}
	if not prev_narrator.is_empty():
		relationship = _relationship_engine.build_context(str(narrator.get("name", "")), prev_narrator, entries)

	var plot_id: int = entries.size() + 1  # Plot-ID sequenziell (wie original p1, p2, …)
	var session: Dictionary = _session_builder.build_session(
		result, impulse, model_id,
		prev_composite, prev_mood, prev_narrator, prev_model, prev_class,
		staged, _git.head_hash_full(), sideplot, relationship, arc, arc_forecast, mood_pool,
		plot_id
	)
	# Limits in die Session — Check 9 (RNG-Replay) muss exakt dieselben
	# Ziehungs-Grenzen verwenden wie prepare, sonst divergiert der RNG-Zustand.
	session["limits"] = limits.duplicate()

	# Prompt bauen + Session + Datei schreiben
	# Narrative Runtime is downstream-only. Context is intentionally not read
	# during prepare: a missing/stale Python archive must never block or alter
	# deterministic Composite/Narrator selection. Post-push tooling may export
	# narrative_runtime/context separately.
	var ctx: Dictionary = _session_builder.build_narrative_context(session, narrator, analyze)
	session["prompt"] = _voice.build_prompts(ctx)
	_session_store.save(session)
	var prompt_path: String = _artifacts.write_prompt_file(session["prompt"], str(session["narrator"]), str(session["mood"]))

	return {"ok": true, "session": session, "prompt_path": prompt_path}