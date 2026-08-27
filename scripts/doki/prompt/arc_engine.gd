class_name DOKI_ArcEngine
extends RefCounted
## Handlungsbögen — NEU implementiert. Das alte System hatte nur eine
## commitCount-Schwelle ohne Advance. Hier: deterministisches Gewicht aus
## ChangeIndex-Entitäten (gleiche Chain + gleicher Diff → gleiches Gewicht).
##
## Gewichtsformel: w += 0.5 (Basis) + 0.3 × neue Entitäten + 0.4 × wiedergefundene
## Entitäten (Overlap mit früheren Commits = Wiederkehr eines Themas).
## Wird climax_weight erreicht → ARC_CLIMAX im Prompt + Auto-Advance in finalize.

const BASE_WEIGHT: float = 0.5
const NEW_ENTITY_WEIGHT: float = 0.3
const RECUR_ENTITY_WEIGHT: float = 0.4
const MERGE_BONUS: float = 1.0

## Kategorien, die einen Arc-Vorstoß blockieren (kein CLIMAX möglich).
const NON_NARRATIVE_CLASSES: Array = ["FIX", "DOKU", "TRIVIAL", "TEST-ASSET"]
## Kategorien mit reduziertem Gewicht (Wartung, aber nicht trivial).
const MAINTENANCE_CLASSES: Array = ["REFACTOR", "BUILD"]

var _data: Dictionary = {}
var _path: String


func _init(data_dir: String) -> void:
	_path = data_dir.path_join("arcs.json")
	_reload()


func _reload() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if parsed is Dictionary:
		_data = parsed


func active_id() -> String:
	return str(_data.get("active", ""))


func arc(arc_id: String) -> Dictionary:
	return _data.get("arcs", {}).get(arc_id, {})


func active_arc() -> Dictionary:
	return arc(active_id())


func arc_count() -> int:
	return (_data.get("arcs", {}) as Dictionary).size()


## Deterministische Gewichtsprognose FÜR den kommenden Commit.
## Called from prepare (Diff ist staged) — Ergebnis fließt in session.
## impulse_class: Klassifikation aus VoiceComposer.classify_impulse().
## Kategorien steuern, ob ein Commit zum Arc-Vorstoß beiträgt und ob
## ARC_CLIMAX ausgelöst werden darf:
##   FIX/DOKU/TRIVIAL/TEST-ASSET → Gewicht 0, kein CLIMAX (Wartung)
##   REFACTOR/BUILD → reduziertes Gewicht, CLIMAX möglich
##   CODE/FEATURE → volles Gewicht, normaler CLIMAX
func forecast_weight(active_arc: Dictionary, change_entities: Array, is_merge: bool, impulse_class: String = "CODE") -> Dictionary:
	var weight: float = float(active_arc.get("weight", 0.0))
	var climax_weight: float = float(active_arc.get("climax_weight", 3.0))

	var known_entity_ids: Dictionary = {}
	for e in _data.get("arcs", {}).get(active_id(), {}).get("seen_entities", []):
		known_entity_ids[str(e)] = true

	var new_entities: int = 0
	var recur_entities: int = 0
	for e in change_entities:
		var entity_id: String = str(e)
		if entity_id.is_empty():
			continue
		if known_entity_ids.has(entity_id):
			recur_entities += 1
		else:
			new_entities += 1
			known_entity_ids[entity_id] = true

	# Kategorie-basierte Gewichtung
	var eligible: bool = true
	var base: float = BASE_WEIGHT
	if NON_NARRATIVE_CLASSES.has(impulse_class):
		# FIX, DOKU, TRIVIAL, TEST-ASSET: kein Gewichtsbeitrag, kein CLIMAX
		base = 0.0
		eligible = false
	elif MAINTENANCE_CLASSES.has(impulse_class):
		# REFACTOR, BUILD: reduziertes Gewicht
		base = BASE_WEIGHT * 0.5

	weight += base + NEW_ENTITY_WEIGHT * new_entities + RECUR_ENTITY_WEIGHT * recur_entities
	if is_merge:
		weight += MERGE_BONUS

	var climax: bool = eligible and weight >= climax_weight
	return {
		"forecast_weight": weight,
		"new_entities": new_entities,
		"recur_entities": recur_entities,
		"climax": climax,
		"climax_eligible": eligible,
		"impulse_class": impulse_class,
	}


## Nach erfolgreichem Commit: Gewicht fortschreiben; bei Climax → Arc wechseln.
## impulse_class: Klassifikation des Commits (steuert Climax-Berechtigung).
## next_arc: NÄCHSTER-ARC-Vorschlag des Narrators ({name, theme}) — wird beim
## Anlegen des neuen Bogens übernommen (statt des Platzhalters „Nächster Akt").
func advance(new_entities: Array, is_merge: bool, impulse_class: String = "CODE", next_arc: Dictionary = {}) -> Dictionary:
	var forecast: Dictionary = forecast_weight(active_arc(), new_entities, is_merge, impulse_class)
	var weight: float = forecast["forecast_weight"]
	var climax: bool = forecast["climax"]
	var old_id: String = active_id()
	var old_arc: Dictionary = arc(old_id)

	var result := {
		"old_arc_id": old_id,
		"old_arc_name": str(old_arc.get("name", "")),
		"advanced": false,
		"new_arc_id": old_id,
		"new_arc_name": str(old_arc.get("name", "")),
		"completed": false,
	}

	if climax:
		# Arc abschließen — die gesehenen Entitäten gehören dem abgeschlossenen Arc
		old_arc["status"] = "completed"
		old_arc["weight"] = weight
		old_arc["completed_at"] = "arc_climax"
		old_arc["seen_entities"] = _merge_seen(old_arc.get("seen_entities", []), new_entities)
		_data["arcs"][old_id] = old_arc
		result["completed"] = true
		result["advanced"] = true
		# Nächsten Arc bestimmen: a{old+1} oder neuen anlegen
		var next_id: String = "a%d" % (int(old_id.substr(1)) + 1)
		if not (_data.get("arcs", {}) as Dictionary).has(next_id):
			_data["arcs"][next_id] = {
				"id": next_id,
				"name": "Nächster Akt",
				"version": "",
				"theme": "Neuer Handlungsbogen — Thema offen (wird vom ersten Commit des Arcs geprägt).",
				"span": "heute → offen",
				"status": "active",
				"weight": 0.0,
				"climax_weight": 3.0,
			}
		# NÄCHSTER-ARC-Vorschlag des Narrators übernehmen (falls im Body vorhanden)
		var next_name: String = str(next_arc.get("name", "")).strip_edges()
		var next_theme: String = str(next_arc.get("theme", "")).strip_edges()
		if not next_name.is_empty():
			_data["arcs"][next_id]["name"] = next_name
		if not next_theme.is_empty():
			_data["arcs"][next_id]["theme"] = next_theme
		_data["arcs"][next_id]["status"] = "active"
		_data["arcs"][next_id]["weight"] = 0.0
		_data["active"] = next_id
		result["new_arc_id"] = next_id
		result["new_arc_name"] = str(_data["arcs"][next_id].get("name", ""))
	else:
		# Kein Climax: Entitäten auf dem aktiven Arc fortschreiben
		old_arc["weight"] = weight
		old_arc["seen_entities"] = _merge_seen(old_arc.get("seen_entities", []), new_entities)
		_data["arcs"][old_id] = old_arc

	_save()
	return result


static func _merge_seen(seen: Array, new_entities: Array) -> Array:
	var merged: Array = seen.duplicate()
	var seen_set := {}
	for e in merged:
		seen_set[str(e)] = true
	for e in new_entities:
		var entity_id: String = str(e)
		if not entity_id.is_empty() and not seen_set.has(entity_id):
			seen_set[entity_id] = true
			merged.append(entity_id)
	return merged


func _save() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_error("DOKI: arcs.json nicht schreibbar: %s" % _path)
		return
	file.store_string(JSON.stringify(_data, "\t"))
	file.close()