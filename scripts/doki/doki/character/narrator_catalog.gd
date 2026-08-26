class_name DOKI_NarratorCatalog
extends RefCounted
## Lädt narrators.json (14 Charaktere) und bietet deterministischen Zugriff.
## Einheitliches Datenmodell — das alte System hatte zwei auseinanderlaufende
## Modelle (Code-Klasse Character vs. reiches JSON). Hier gibt es nur das JSON.

var _characters: Array = []


func _init(data_dir: String) -> void:
	_load(data_dir.path_join("narrators.json"))


func _load(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_characters = parsed.get("characters", [])


func all() -> Array:
	return _characters


func by_index(index: int) -> Dictionary:
	for c in _characters:
		if int(c.get("index", 0)) == index:
			return c
	return {}


func by_name(name: String) -> Dictionary:
	for c in _characters:
		if str(c.get("name", "")) == name:
			return c
	return {}


func name_by_index(index: int) -> String:
	return str(by_index(index).get("name", ""))


func validate_name(name: String) -> bool:
	return not by_name(name).is_empty()


## Effektive Attitudes: Basis + Mood-Deltas, geclampt auf 0-10.
func effective_attitudes(narrator: Dictionary, mood: String, modifiers: Dictionary) -> Dictionary:
	var base: Dictionary = narrator.get("attitudes", {})
	var deltas: Dictionary = modifiers.get(mood, {})
	var result: Dictionary = {}
	for key in base.keys():
		var value: int = int(base[key]) + int(deltas.get(key, 0))
		result[key] = clampi(value, 0, 10)
	return result