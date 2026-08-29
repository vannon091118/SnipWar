class_name FactionProfiles
extends RefCounted

## R-SIM-001: Deterministisches Persönlichkeitsprofil pro Fraktion.
## Vollständig unabhängig von DOKI — kein Import aus scripts/doki/.
## 14 Profile, abgeleitet aus der simulation_profiles.json.
## Index-Formel: (sim_seed + String(fid).hash()) % 14  →  0..13  → profile index+1

const PROFILES_PATH := "res://scripts/history/data/simulation_profiles.json"
static var _cache: Array = []

static func get_profile(fid: StringName, sim_seed: int) -> Dictionary:
	_ensure_loaded()
	var idx: int = (sim_seed + String(fid).hash()) % 14
	return _cache[idx] if idx < _cache.size() else _cache[0]

static func _ensure_loaded() -> void:
	if not _cache.is_empty():
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILES_PATH))
	if parsed is Dictionary:
		_cache = parsed.get("profiles", [])
