class_name DOKI_SessionBuilder
extends RefCounted
## Zuständigkeit: Session-Zustand aus den Engine-Ergebnissen zusammensetzen
## (prepare) + den narrativen Prompt-Kontext bauen (Steuergelder zur VoiceComposer).
## Kein Dateizugriff, kein Git — reine Ableitung.

var _catalog: DOKI_NarratorCatalog
var _moods: DOKI_MoodOverlay


func _init(catalog: DOKI_NarratorCatalog, moods: DOKI_MoodOverlay) -> void:
	_catalog = catalog
	_moods = moods


## Baut die Session aus den prepare-Ergebnissen (deterministisch).
func build_session(
	derive_result: Dictionary,
	impulse: String,
	model_id: String,
	prev_composite: String,
	prev_mood: String,
	prev_narrator: String,
	prev_model: String,
	prev_class: String,
	staged: Array,
	head_hash: String,
	sideplot: Dictionary,
	relationship: Dictionary,
	arc: Dictionary,
	arc_forecast: Dictionary,
	mood_pool: Array,
	plot_id: int
) -> Dictionary:
	var narrator: Dictionary = _catalog.by_index(int(derive_result["n"]))
	var session := {
		"state": DOKI_SessionStore.STATE_PREPARED,
		"composite": str(derive_result["composite"]),
		"seed": int(derive_result["seed"]),
		"tree_hash": str(derive_result["tree_hash"]),
		"diff_hash": str(derive_result["diff_hash"]),
		"impulse": impulse,
		"model_id": model_id,
		"narrator": str(narrator.get("name", "")),
		"narrator_index": int(derive_result["n"]),
		"mood": str(derive_result["mood"]),
		"tone": str(derive_result.get("tone", "sachlich")),
		"structure": str(derive_result.get("structure", "chronologisch")),
		"callback": bool(derive_result.get("callback", false)),
		"prev_narrator": prev_narrator,
		"prev_model": prev_model,
		"prev_class": prev_class,
		"file_snapshot": staged.duplicate(),
		"git_head_before": head_hash,
		"p_id": plot_id,  # Plot-ID ist SEQUENZ (p1, p2, …) — wie im Original.
		# Das RNG-gezogene p bleibt als Referenz-Feld ("p").
		"c": int(derive_result["c"]),
		"j": int(derive_result["j"]),
		"n": int(derive_result["n"]),
		"a": int(derive_result["a"]),
		"p": int(derive_result["p"]),
		"arc_id": str(arc.get("id", "")),
		"arc_name": str(arc.get("name", "")),
		"arc_weight": float(arc_forecast.get("forecast_weight", 0.0)),
		"is_arc_climax": bool(arc_forecast.get("climax", false)),
		"arc_climax_eligible": bool(arc_forecast.get("climax_eligible", true)),
		"sideplot": sideplot,
		"impulse_class": str(derive_result["impulse_class"]),
		"relationship": relationship,
		"mood_pool": mood_pool.duplicate(),
		"prev_composite": prev_composite,
		"prev_mood": prev_mood,
	}
	return session


## Narrativer Kontext für den VoiceComposer (System-/User-Prompt).
func build_narrative_context(session: Dictionary, narrator: Dictionary, analyze: Dictionary) -> Dictionary:
	var prev_class: String = str(session.get("prev_class", ""))
	var files: Array = []
	for e in analyze.get("entities", []):
		if e.get("type") == "file":
			files.append(str(e.get("path", "")))
	return {
		"narrator": narrator,
		"attitudes": _catalog.effective_attitudes(narrator, str(session.get("mood", "")), _moods.modifiers()),
		"impulse": str(session.get("impulse", "")),
		"impulse_class": str(session.get("impulse_class", "CODE")),
		"body_text": "",
		"files": files,
		"sidejoke": "",
		"prev_narrator": str(session.get("prev_narrator", "")),
		"prev_class": prev_class,
		"is_direction_change": not prev_class.is_empty() and prev_class != str(session.get("impulse_class", "CODE")),
		"is_arc_climax": bool(session.get("is_arc_climax", false)),
		"arc_climax_eligible": bool(session.get("arc_climax_eligible", true)),
		"arc_name": str(session.get("arc_name", "")),
		"arc_id": str(session.get("arc_id", "")),
		"relationship": session.get("relationship", {}),
		"sideplot": session.get("sideplot", {}),
		"mood": str(session.get("mood", "")),
		"structure_info": {
			"structure": str(session.get("structure", "chronologisch")),
			"pattern": "",
		},
	}