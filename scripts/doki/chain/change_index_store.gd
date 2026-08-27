class_name DOKI_ChangeIndexStore
extends RefCounted
## Registry für F-xxx (Dateien) und C-xxx (Komponenten/Klassen/Funktionen) IDs.
## change_index.json (Repo-Root):
## {
##   "version": 2,
##   "entities": { "F-001": { id, type, name, path, status, first_p, last_p, history: [{p_id, action, lines}] } },
##   "commits":  { "<git-hash>": { p_id, composite, c, entities: ["F-001", ...] } }
## }
## IDs bleiben über Commits stabil: Lookup nach (path, type, name) → bestehende ID.

var _path: String


func _init(repo_root: String) -> void:
	_path = repo_root.path_join("change_index.json")


func path() -> String:
	return _path


func exists() -> bool:
	return FileAccess.file_exists(_path)


func read() -> Dictionary:
	if not exists():
		return _default()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if parsed is Dictionary:
		# Godot 4.7 parst ALLE JSON-Zahlen als Float — hier normalisieren
		# (first_p/last_p/p_id/line-Nummern müssen ganzzahlig sein).
		for entity in (parsed as Dictionary).get("entities", {}).values():
			for key in ["first_p", "last_p"]:
				if entity.has(key):
					entity[key] = int(entity[key])
			for h in entity.get("history", []):
				h["p_id"] = int(h.get("p_id", 0))
				var line_numbers: Array = []
				for x in h.get("lines", []):
					line_numbers.append(int(x))
				h["lines"] = line_numbers
		for comm in (parsed as Dictionary).get("commits", {}).values():
			comm["c"] = int(comm.get("c", 0))
			comm["p_id"] = int(comm.get("p_id", 0))
		return parsed
	return _default()


func _default() -> Dictionary:
	return {"version": 2, "entities": {}, "commits": {}}


func save(index: Dictionary) -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_error("DOKI: change_index.json nicht schreibbar: %s" % _path)
		return
	file.store_string(JSON.stringify(index, "\t"))
	file.close()


## Repo-Root für laterale Datei-Pfade (normalisierte "/").
func normalize_path(p: String) -> String:
	return p.replace("\\", "/")


## Findet existierende Entität per (path, type, name) — stabil über Commits.
func find_entity(index: Dictionary, path: String, type: String, name: String) -> String:
	var norm: String = normalize_path(path)
	for entity_id in index.get("entities", {}):
		var e: Dictionary = index["entities"][entity_id]
		if e.get("type") == type and e.get("name") == name and normalize_path(str(e.get("path", ""))) == norm:
			return entity_id
	return ""


## Nächste freie ID: F-### bzw. C-###.
## prefix kommt MIT Bindestrich ("F-"/"C-") → hier nicht nochmal formatieren,
## sonst entsteht ein Doppel-Dash (F--001, bekanntes Format-Bug).
func next_id(index: Dictionary, prefix: String) -> String:
	var max_num: int = 0
	for entity_id in index.get("entities", {}):
		if str(entity_id).begins_with(prefix):
			var num: int = int(str(entity_id).substr(prefix.length()))
			if num > max_num:
				max_num = num
	return "%s%03d" % [prefix, max_num + 1]


## Entität anlegen oder bestehende finden; returns entity_id.
func ensure_entity(index: Dictionary, path: String, type: String, name: String, p_id: int) -> String:
	var existing: String = find_entity(index, path, type, name)
	if not existing.is_empty():
		return existing
	var entity_id: String = next_id(index, "F-" if type == "file" else "C-")
	index["entities"][entity_id] = {
		"id": entity_id,
		"type": type,
		"name": name,
		"path": normalize_path(path),
		"status": "created",
		"first_p": p_id,
		"last_p": p_id,
		"history": [],
	}
	return entity_id


## Verknüpft einen Commit mit Entitäten (nach erfolgreichem Git-Commit).
func link_commit(index: Dictionary, git_hash: String, p_id: int, composite: String, c: int, entity_ids: Array) -> void:
	index["commits"][git_hash] = {
		"p_id": p_id,
		"composite": composite,
		"c": c,
		"entities": entity_ids,
	}