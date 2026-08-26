class_name DOKI_MoodOverlay
extends RefCounted
## Lädt moods.json (Mood-Pool, Attitude-Modifier, j-Dekodierung, Beispiele).
## Port aus narrative_params.json.

var _data: Dictionary = {}


func _init(data_dir: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_dir.path_join("moods.json")))
	if parsed is Dictionary:
		_data = parsed


func mood_pool() -> Array:
	return _data.get("mood_pool", [])


func modifiers() -> Dictionary:
	return _data.get("attitude_modifiers", {})


func decoding() -> Dictionary:
	return _data.get("decoding", {})


func mood_example(narrator_name: String, mood: String) -> String:
	var examples: Dictionary = _data.get("narrator_mood_combination", {}).get("examples", {})
	return str(examples.get("%s+%s" % [narrator_name, mood], ""))


## Fester Mood-Pool (Fallback, wenn moods.json fehlt).
static func default_pool() -> Array:
	return ["sachlich", "sarkastisch", "erschöpft", "triumphierend", "selbstironisch", "neugierig", "müde-zufrieden", "alarmiert", "trocken", "warm"]