class_name DOKI_PromptEngine
extends RefCounted
## Daten-getriebener Prompt-Assembler. Liest Templates aus prompt_templates.json
## und ersetzt Platzhalter {key} mit Engine-Ergebnissen.
##
## Der Junction-Punkt aller DOKI-Engines:
##   NarratorCatalog    → name, role, voice_traits, style_sample, tone_brief, attitudes
##   MoodOverlay        → mood_expression, category_calibration, mood_example, attitude_modifiers
##   ArcEngine          → arc_name, arc_weight, is_arc_climax, arc_climax_eligible
##   RelationshipEngine → relationship (target, knowledge, sentiment, tone_directive)
##   SidePlotEngine     → sideplot (merge context)
##   VoiceComposer      → impulse_class, structure_info, files, search_context
##   SessionBuilder     → all session values (composite, narrator, mood, etc.)
##
## Phase 7 des DOKI Master-Plans: ersetzt die hardcoded Strings in voice_composer.gd
## durch JSON-Templates. Neue Regeln = JSON-Eintrag, keine Code-Änderung.

var _templates: Dictionary
var _loaded: bool = false


func _init(data_dir: String) -> void:
	_load_templates(data_dir.path_join("prompt_templates.json"))


func _load_templates(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_error("DOKI_PromptEngine: Template-Datei nicht gefunden: %s" % path)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_templates = parsed
		_loaded = true


func is_loaded() -> bool:
	return _loaded


## Holt ein Template aus einem Section-Block.
func get_template(section: String, key: String) -> String:
	var sec: Dictionary = _templates.get(section, {})
	return str(sec.get(key, ""))


## Holt ein Array-Template (z.B. trivial_pool).
func get_array(key: String) -> Array:
	var arr = _templates.get(key, [])
	return arr if arr is Array else []


## Holt ein Dict-Template (z.B. structure_hints, subject_templates).
func get_dict(key: String) -> Dictionary:
	var d = _templates.get(key, {})
	return d if d is Dictionary else {}


## Rendert ein Template: ersetzt {key} Platzhalter mit Werten aus vars.
func render(template: String, vars: Dictionary) -> String:
	var result: String = template
	for key in vars.keys():
		result = result.replace("{%s}" % key, str(vars[key]))
	return result


## Rendert den Attitude-Text (5-Stufen) aus den Templates.
func attitude_text(value: int, high_label: String, low_label: String) -> String:
	var texts: Dictionary = get_dict("attitude_texts")
	if value >= 9:
		return render(str(texts.get("high_9", high_label)), {"label": high_label})
	if value >= 7:
		return render(str(texts.get("high_7", high_label)), {"label": high_label})
	if value >= 5:
		return str(texts.get("balanced", "ausgeglichen"))
	if value >= 3:
		return render(str(texts.get("low_3", low_label)), {"label": low_label})
	return render(str(texts.get("low_1", low_label)), {"label": low_label})


## Holt den Structure-Hint für einen Narrator (aus Templates, mit Fallback).
func structure_hint(narrator_name: String, file_count: int) -> String:
	var hints: Dictionary = get_dict("structure_hints")
	var hint: String = str(hints.get(narrator_name, ""))
	if hint.is_empty():
		return "Erzählend. %d Dateien. Finde deine eigene Stimme." % file_count
	return hint


## Holt den Trivial-Pool-Eintrag (deterministisch via Djb2).
func trivial_entry(impulse: String, file_count: int) -> String:
	var pool: Array = get_array("trivial_pool")
	if pool.is_empty():
		return ""
	var idx: int = DOKI_RngEngine.djb2(impulse) % pool.size()
	var entry: String = str(pool[idx])
	return render(entry, {
		"file_count": file_count,
		"file_count_x1000": file_count * 1000,
		"impulse": impulse,
	})


## Holt die positive Mood-Regel (aus Templates, mit Fallback).
func mood_rule() -> String:
	var rules: Dictionary = get_dict("mood_rules")
	return str(rules.get("positive", "Nenne deinen Mood NIEMALS beim Namen."))
