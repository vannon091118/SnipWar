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
const IMPACT_RESOLVER: Script = preload("res://scripts/preflight_v2/change_impact_resolver.gd")
const AUTO_MANAGED: Array = ["narrative_chain.json", "change_index.json", "CHANGELOG.md", ".commit_msg.txt", "arcs.json"]


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
	var agent_name := OS.get_environment("AGENT_NAME").strip_edges()
	var activity_seed := OS.get_environment("AGENT_ACTIVITY_SEED").strip_edges()
	if agent_name.is_empty() or activity_seed.is_empty():
		return {"ok": false, "error": "AGENT_NAME und AGENT_ACTIVITY_SEED müssen aus dem aktiven Check-In stammen."}
	if staged.is_empty():
		return {"ok": false, "error": "Keine gestagten Änderungen — erst `git add <dateien>`, dann prepare."}

	# V10-001: Verify AGENT_ACTIVITY_SEED against agent_activity.sh registry
	var seed_check: Dictionary = _verify_agent_activity_seed(agent_name, activity_seed)
	if not bool(seed_check.get("ok", false)):
		return seed_check

	# Single-Active-Owner (TASK-013, RISK-003): fail-closed, kein destruktives
	# Cleanup. Der Owner-Token ist prozess-eindeutig; ein zweiter aktiver Agent
	# wird abgewiesen — nie automatisch überschrieben.
	var owner_token: String = _ownership_token()
	var claim_result: Dictionary = _session_store.claim(owner_token)
	if not bool(claim_result.get("ok", false)):
		return claim_result

	# Scope-Auflösung (Session-Scoped Verification): der machine-resolvable
	# Verification-Scope des echten Diffs wird VOR dem Prompt bestimmt und in
	# der Session + .doki/scope.json (für den Preflight-Hook) persistiert.
	# Unknown/leer blockt fail-closed (nie ein grüner leere Run).
	var impact: Dictionary = IMPACT_RESOLVER.resolve(staged)
	if not bool(impact.get("ok", false)):
		_session_store.release_ownership(owner_token)
		return {"ok": false, "error": "Impact-Auflösung fehlgeschlagen: %s" % str(impact.get("error", "unresolved_impact"))}

	# Content-Addressed Scope (TASK-010/011): exakte Digests der gestagten
	# Bytes, des Pfadbestands und des resolved Constraint-Sets. Der Gate
	# recompute diese Werte und weist jeglichen Drift ab (Byte-/Scope-Drift
	# nach prepare → kein grüner Commit, ohne die Datei umzuschreiben).
	var diff_output: String = _git.diff_cached()
	var non_auto_staged: Array = _without_auto_managed(staged)
	var scope_path_digest: String = IMPACT_RESOLVER.path_digest(non_auto_staged)
	var scope_constraint_digest: String = IMPACT_RESOLVER.constraint_digest(impact.get("constraints", []))
	var staged_byte_digest: String = IMPACT_RESOLVER.staged_byte_digest(_strip_auto_managed_diff(diff_output))
	_write_scope_file(impact)
	_write_agent_binding(agent_name, activity_seed)

	# Die Commit-Größe ist nicht künstlich begrenzt; Kohärenz wird durch
	# Snapshot-, Scope- und Content-Digests geprüft.
	var user_files: Array = []
	for f in staged:
		if not DOKI_Verifier.AUTO_MANAGED.has(str(f).get_file()):
			user_files.append(str(f))

	var chain: Dictionary = _chain_store.read()
	if chain.get("anchor", {}).is_empty():
		_session_store.release_ownership(owner_token)
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
	session["impact"] = impact
	session["scope_path_digest"] = scope_path_digest
	session["scope_constraint_digest"] = scope_constraint_digest
	session["staged_byte_digest"] = staged_byte_digest
	session["baseline_identity"] = str(result.get("tree_hash", ""))
	session["owner_token"] = owner_token
	# V10-004: Store agent_name and activity_seed in session for gate verification
	session["agent_name"] = agent_name
	session["activity_seed"] = activity_seed
	# Limits in die Session — Check 9 (RNG-Replay) muss exakt dieselben
	# Ziehungs-Grenzen verwenden wie prepare, sonst divergiert der RNG-Zustand.
	session["limits"] = limits.duplicate()

	# Prompt bauen + Session + Datei schreiben
	# Search is executed by the runtime before prompt generation. The complete
	# JSON/text output is embedded into the prompt; failure is fail-closed.
	var search: Dictionary = {"ok": true, "complete": false, "query": "", "scope": staged.duplicate(), "global_search": "", "concept_search": ""}
	var search_requested := impulse.to_lower().contains("search") or impulse.to_lower().contains("analyse") or impulse.to_lower().contains("audit")
	if search_requested:
		search = _git.search_context(staged, impulse)
		if not search["ok"]:
			_session_store.release_ownership(owner_token)
			return {"ok": false, "error": str(search.get("error", "Automatische Suche fehlgeschlagen."))}
	var ctx: Dictionary = _session_builder.build_narrative_context(session, narrator, analyze)
	ctx["search_context"] = search
	ctx["search_contract"] = "Read the COMPLETE Global Search JSON and Concept Search output before writing the body."
	session["search_context"] = search
	session["prompt"] = _voice.build_prompts(ctx)
	
	# Transition state atomically with integrity hash (V2-001, V2-003).
	# Die gebaute Session (mit narrator/mood/composite/seed/file_snapshot/limits)
	# wird übergeben, damit sie persistiert wird — transition_state darf sonst nur
	# die leere Disk-Version überschreiben und alle Content-Felder wegwerfen.
	var transition_result: Dictionary = _session_store.transition_state(DOKI_SessionStore.STATE_PREPARED, activity_seed, session)
	if not bool(transition_result.get("ok", false)):
		_session_store.release_ownership(owner_token)
		return transition_result
	
	var prompt_path: String = _artifacts.write_prompt_file(session["prompt"], str(session["narrator"]), str(session["mood"]))
	return {"ok": true, "session": transition_result["session"], "prompt_path": prompt_path, "scope": impact}


## Persistiert den resolved Verification-Scope als JSON-Manifest für den
## Preflight-Hook (.doki ist gitignored): {constraints:[...], contracts:[...]}.
func _write_agent_binding(agent_name: String, activity_seed: String) -> void:
	var binding := {"agent_name": agent_name, "activity_seed": activity_seed, "owner_token": "agent:%s:seed:%s" % [agent_name, activity_seed]}
	var content: String = JSON.stringify(binding, "\t")
	_atomic_write(_repo_root.path_join(".doki/agent_binding.json"), content)


func _write_scope_file(impact: Dictionary) -> void:
	var dir_path: String = _repo_root.path_join(".doki")
	DirAccess.make_dir_recursive_absolute(dir_path)
	var content: String = JSON.stringify({"constraints": impact.get("constraints", []), "contracts": impact.get("contracts", [])}, "\t")
	_atomic_write(dir_path.path_join("scope.json"), content)


## ─── Atomic write helper ─────────────────────────────────────────────────
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
	DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp_path, path)


## Prozesseeindeutiger Ownership-Token (Single-Active-Owner, RISK-003).
func _ownership_token() -> String:
	var agent_name := OS.get_environment("AGENT_NAME").strip_edges()
	var activity_seed := OS.get_environment("AGENT_ACTIVITY_SEED").strip_edges()
	if agent_name.is_empty() or activity_seed.is_empty():
		return ""
	return "agent:%s:seed:%s" % [agent_name, activity_seed]


## V10-001: Verify AGENT_ACTIVITY_SEED against agent_activity.sh registry
func _verify_agent_activity_seed(agent_name: String, activity_seed: String) -> Dictionary:
	# Call agent_activity.sh seed <agent> to get registered seed
	var output: Array = []
	var repo_root: String = ProjectSettings.globalize_path("res://")
	var script_path: String = repo_root + "scripts/agent_activity.sh"
	# Resolve bash path: Windows needs full path (Git Bash), Unix uses PATH
	var bash_path: String = OS.get_environment("SHELL")
	if bash_path.is_empty() or not FileAccess.file_exists(bash_path):
		# Try common Windows Git Bash locations
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


static func _without_auto_managed(files: Array) -> Array:
	var result: Array = []
	for f in files:
		if not AUTO_MANAGED.has(str(f).get_file()):
			result.append(str(f))
	return result


## Filtert auto-managed Dateien aus einem `git diff --cached`-String heraus.
## Muss mit gate_flow.gd:_strip_auto_managed_diff übereinstimmen.
static func _strip_auto_managed_diff(diff_output: String) -> String:
	if diff_output.is_empty():
		return ""
	var sections: PackedStringArray = diff_output.split("diff --git ")
	var kept: Array[String] = []
	for i in range(1, sections.size()):
		var header: String = sections[i].split("\n")[0]
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
